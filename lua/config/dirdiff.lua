local M = {}

local file_highlights = {
  A = "GitAddedLine",
  D = "GitDeletedLine",
  M = "GitModifiedLine",
}

local state = {
  empty_file = nil,
  first_file_line = nil,
  files = {},
  left_dir = nil,
  left_win = nil,
  line_entries = {},
  list_buf = nil,
  list_win = nil,
  right_dir = nil,
  right_win = nil,
}

local namespace = vim.api.nvim_create_namespace("directory-diff")

local function is_directory(path)
  return path ~= "" and vim.fn.isdirectory(path) == 1
end

local function ensure_empty_file()
  if state.empty_file and vim.fn.filereadable(state.empty_file) == 1 then
    return state.empty_file
  end

  state.empty_file = vim.fn.tempname()
  vim.fn.writefile({}, state.empty_file)

  return state.empty_file
end

local function scan_files(root)
  local files = {}

  local function scan(directory, prefix)
    local handle = vim.uv.fs_scandir(directory)

    if not handle then
      return
    end

    while true do
      local name, kind = vim.uv.fs_scandir_next(handle)

      if not name then
        break
      end

      if name ~= ".git" then
        local full_path = directory .. "/" .. name
        local relative_path = prefix == "" and name or prefix .. "/" .. name

        if kind == "directory" or (kind == "link" and vim.fn.isdirectory(full_path) == 1) then
          scan(full_path, relative_path)
        elseif kind == "file" or kind == "link" then
          files[relative_path] = true
        end
      end
    end
  end

  scan(root, "")

  return files
end

local function files_differ(left_path, right_path)
  vim.fn.system({ "cmp", "-s", left_path, right_path })
  return vim.v.shell_error ~= 0
end

local function changed_files(left_dir, right_dir)
  local left_files = scan_files(left_dir)
  local right_files = scan_files(right_dir)
  local all_files = {}
  local changes = {}

  for path in pairs(left_files) do
    all_files[path] = true
  end

  for path in pairs(right_files) do
    all_files[path] = true
  end

  for path in pairs(all_files) do
    local left_path = left_dir .. "/" .. path
    local right_path = right_dir .. "/" .. path
    local status = nil

    if not left_files[path] then
      status = "A"
    elseif not right_files[path] then
      status = "D"
    elseif files_differ(left_path, right_path) then
      status = "M"
    end

    if status then
      table.insert(changes, {
        path = path,
        status = status,
      })
    end
  end

  table.sort(changes, function(a, b)
    return a.path < b.path
  end)

  return changes
end

local function path_for_side(side, entry)
  if side == "left" then
    local path = state.left_dir .. "/" .. entry.path
    return vim.fn.filereadable(path) == 1 and path or ensure_empty_file()
  end

  local path = state.right_dir .. "/" .. entry.path
  return vim.fn.filereadable(path) == 1 and path or ensure_empty_file()
end

local function current_entry()
  if not state.list_buf or not vim.api.nvim_buf_is_valid(state.list_buf) then
    return nil
  end

  local line = vim.api.nvim_win_get_cursor(state.list_win)[1]
  local entry = state.line_entries[line]

  if entry then
    return entry
  end

  for index = line + 1, #state.line_entries do
    if state.line_entries[index] then
      return state.line_entries[index]
    end
  end

  for index = line - 1, 1, -1 do
    if state.line_entries[index] then
      return state.line_entries[index]
    end
  end

  return nil
end

local function edit_window(window, path)
  vim.api.nvim_set_current_win(window)
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  vim.bo.buflisted = false
  vim.wo.diff = false
  vim.cmd.diffthis()
end

local function ensure_diff_windows()
  if state.left_win and vim.api.nvim_win_is_valid(state.left_win) and state.right_win and vim.api.nvim_win_is_valid(state.right_win) then
    return
  end

  vim.api.nvim_set_current_win(state.list_win)
  vim.cmd("botright vertical new")
  state.left_win = vim.api.nvim_get_current_win()
  vim.cmd("botright vertical new")
  state.right_win = vim.api.nvim_get_current_win()
end

local function open_current_diff()
  local entry = current_entry()

  if not entry then
    return
  end

  ensure_diff_windows()
  vim.cmd("diffoff!")
  edit_window(state.left_win, path_for_side("left", entry))
  edit_window(state.right_win, path_for_side("right", entry))
  vim.api.nvim_set_current_win(state.list_win)
end

local function path_parts(path)
  local parts = {}

  for part in path:gmatch("[^/]+") do
    table.insert(parts, part)
  end

  return parts
end

local function sorted_keys(tbl)
  local keys = {}

  for key in pairs(tbl) do
    table.insert(keys, key)
  end

  table.sort(keys)

  return keys
end

local function build_file_tree()
  local root = {
    dirs = {},
    files = {},
  }

  for _, entry in ipairs(state.files) do
    local node = root
    local parts = path_parts(entry.path)

    for index, part in ipairs(parts) do
      if index == #parts then
        table.insert(node.files, {
          name = part,
          entry = entry,
        })
      else
        node.dirs[part] = node.dirs[part] or {
          dirs = {},
          files = {},
        }
        node = node.dirs[part]
      end
    end
  end

  return root
end

local function root_label()
  local cwd_name = vim.fs.basename(vim.fn.getcwd())

  if cwd_name and cwd_name ~= "" then
    return cwd_name
  end

  return "changes"
end

local function render_tree_node(node, depth, lines)
  local prefix = string.rep("| ", depth)

  for _, dirname in ipairs(sorted_keys(node.dirs)) do
    table.insert(lines, prefix .. dirname .. "/")
    state.line_entries[#lines] = false
    render_tree_node(node.dirs[dirname], depth + 1, lines)
  end

  table.sort(node.files, function(a, b)
    return a.name < b.name
  end)

  for _, file in ipairs(node.files) do
    table.insert(lines, prefix .. file.entry.status .. " " .. file.name)
    state.line_entries[#lines] = file.entry
    state.first_file_line = state.first_file_line or #lines
  end
end

local function render_file_list()
  local lines = {}
  state.first_file_line = nil
  state.line_entries = {}

  if #state.files > 0 then
    table.insert(lines, "../")
    state.line_entries[#lines] = false

    table.insert(lines, "./")
    state.line_entries[#lines] = false

    table.insert(lines, root_label() .. "/")
    state.line_entries[#lines] = false

    render_tree_node(build_file_tree(), 1, lines)
  end

  if #lines == 0 then
    lines = { "No changed files" }
    state.line_entries = {}
  end

  vim.bo[state.list_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.list_buf, 0, -1, false, lines)
  vim.bo[state.list_buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(state.list_buf, namespace, 0, -1)

  for line_number, entry in pairs(state.line_entries) do
    local highlight = entry and file_highlights[entry.status]

    if highlight then
      vim.api.nvim_buf_set_extmark(state.list_buf, namespace, line_number - 1, 0, {
        end_col = #lines[line_number],
        hl_group = highlight,
      })
    end
  end
end

local function setup_file_list_window()
  vim.cmd("only!")

  state.list_win = vim.api.nvim_get_current_win()
  state.list_buf = vim.api.nvim_create_buf(false, true)

  vim.api.nvim_win_set_buf(state.list_win, state.list_buf)
  vim.api.nvim_win_set_width(state.list_win, 44)

  vim.bo[state.list_buf].bufhidden = "wipe"
  vim.bo[state.list_buf].buftype = "nofile"
  vim.bo[state.list_buf].filetype = "dirdiff"
  vim.bo[state.list_buf].modifiable = false
  vim.bo[state.list_buf].swapfile = false
  vim.wo[state.list_win].winhighlight = "Normal:NetrwNormal,CursorLine:NetrwCursorLine,EndOfBuffer:NetrwEndOfBuffer"
  vim.wo[state.list_win].cursorline = true

  render_file_list()

  if state.first_file_line then
    vim.api.nvim_win_set_cursor(state.list_win, { state.first_file_line, 0 })
  end

  vim.keymap.set("n", "<CR>", open_current_diff, {
    buffer = state.list_buf,
    desc = "Open directory diff file",
    silent = true,
  })

  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = state.list_buf,
    callback = open_current_diff,
  })
end

local function maybe_start_directory_diff()
  if not vim.o.diff or vim.fn.argc() ~= 2 then
    return
  end

  local left_dir = vim.fn.argv(0)
  local right_dir = vim.fn.argv(1)

  if not is_directory(left_dir) or not is_directory(right_dir) then
    return
  end

  state.left_dir = vim.fn.fnamemodify(left_dir, ":p"):gsub("/$", "")
  state.right_dir = vim.fn.fnamemodify(right_dir, ":p"):gsub("/$", "")
  state.files = changed_files(state.left_dir, state.right_dir)

  setup_file_list_window()
  open_current_diff()
end

function M.setup()
  vim.api.nvim_create_autocmd("VimEnter", {
    callback = function()
      vim.schedule(maybe_start_directory_diff)
    end,
  })
end

return M
