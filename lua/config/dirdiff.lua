local M = {}

local git = require("config.git")
local util = require("config.util")

local file_highlights = {
  A = "GitAddedLine",
  D = "GitDeletedLine",
  M = "GitModifiedLine",
}

local staged_file_highlight = "GitStagedFile"
local diff_sign_group = "directory_diff_changed_lines"

local state = {
  collapsed_dirs = {},
  empty_file = nil,
  first_file_line = nil,
  files = {},
  default_guicursor = nil,
  left_dir = nil,
  left_match = nil,
  left_win = nil,
  line_entries = {},
  list_buf = nil,
  list_win = nil,
  right_dir = nil,
  right_match = nil,
  right_win = nil,
  staged_files = {},
}

local namespace = vim.api.nvim_create_namespace("directory-diff")
local cursorline_namespace = vim.api.nvim_create_namespace("directory-diff-cursorline")

local add_entry_to_stage
local current_tree_item
local render_file_list
local set_cursor_to_path

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

local function repo_path_for_entry(entry)
  return vim.fn.getcwd() .. "/" .. entry.path
end

local function filetype_for_entry(entry)
  return vim.filetype.match({ filename = repo_path_for_entry(entry) }) or vim.filetype.match({ filename = entry.path })
end

local function apply_entry_filetype(entry)
  local filetype = filetype_for_entry(entry)

  if not filetype or filetype == "" then
    return
  end

  vim.bo.filetype = filetype
  vim.bo.syntax = filetype
end

local function refresh_staged_files()
  state.staged_files = {}

  local output = util.git_output(vim.fn.getcwd(), { "diff", "--cached", "--name-only", "--diff-filter=ACDMRT" })

  if not output then
    return
  end

  for _, path in ipairs(output) do
    state.staged_files[path] = true
  end
end

add_entry_to_stage = function(entry)
  git.add_file(repo_path_for_entry(entry), {
    allow_missing = true,
    root = vim.fn.getcwd(),
  })

  refresh_staged_files()

  if state.list_buf and vim.api.nvim_buf_is_valid(state.list_buf) then
    render_file_list()
    set_cursor_to_path(entry.path)
  end
end

local function path_is_inside(path, directory)
  return path == directory or path:sub(1, #directory + 1) == directory .. "/"
end

local function entries_for_tree_item(item)
  if not item then
    return {}
  end

  if item.kind == "file" and item.entry then
    return { item.entry }
  end

  if item.kind ~= "dir" and item.kind ~= "root" then
    return {}
  end

  local entries = {}

  for _, entry in ipairs(state.files) do
    if item.kind == "root" or path_is_inside(entry.path, item.path) then
      table.insert(entries, entry)
    end
  end

  return entries
end

local function add_tree_item_to_stage()
  local item = current_tree_item()
  local entries = entries_for_tree_item(item)

  if #entries == 0 then
    return
  end

  for _, entry in ipairs(entries) do
    git.add_file(repo_path_for_entry(entry), {
      allow_missing = true,
      root = vim.fn.getcwd(),
    })
  end

  refresh_staged_files()

  if state.list_buf and vim.api.nvim_buf_is_valid(state.list_buf) then
    render_file_list()
    set_cursor_to_path(item.path)
  end
end

current_tree_item = function()
  if not state.list_buf or not vim.api.nvim_buf_is_valid(state.list_buf) then
    return nil
  end

  local line = vim.api.nvim_win_get_cursor(state.list_win)[1]
  return state.line_entries[line]
end

local function item_entry(item)
  if item and item.kind == "file" then
    return item.entry
  end

  return nil
end

local function current_entry()
  if not state.list_buf or not vim.api.nvim_buf_is_valid(state.list_buf) then
    return nil
  end

  local line = vim.api.nvim_win_get_cursor(state.list_win)[1]
  local entry = item_entry(state.line_entries[line])

  if entry then
    return entry
  end

  for index = line + 1, #state.line_entries do
    entry = item_entry(state.line_entries[index])

    if entry then
      return entry
    end
  end

  for index = line - 1, 1, -1 do
    entry = item_entry(state.line_entries[index])

    if entry then
      return entry
    end
  end

  return nil
end

local function map_git_add(buffer, entry)
  vim.keymap.set("n", "<leader>ga", function()
    add_entry_to_stage(entry)
  end, {
    buffer = buffer,
    desc = "Git add directory diff file",
    silent = true,
  })
end

local function edit_window(window, path, entry)
  vim.api.nvim_set_current_win(window)
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  vim.b.dirdiff_repo_path = entry.path
  apply_entry_filetype(entry)
  vim.bo.buflisted = false
  vim.wo.diff = false
  vim.cmd.diffthis()
  vim.wo.cursorcolumn = false
  vim.wo.cursorline = false
  vim.wo.winhighlight = "Cursor:DiffCursor"
  vim.wo.signcolumn = "yes"
  map_git_add(vim.api.nvim_get_current_buf(), entry)

  return vim.api.nvim_get_current_buf()
end

local function is_diff_window(window)
  return window
    and (window == state.left_win or window == state.right_win)
    and vim.api.nvim_win_is_valid(window)
end

local function diff_guicursor()
  local guicursor = state.default_guicursor or vim.o.guicursor

  if guicursor:match("n%-v%-c%-sm:") then
    return guicursor:gsub("n%-v%-c%-sm:[^,]+", "n-v-c-sm:ver25", 1)
  end

  return "n-v-c-sm:ver25," .. guicursor
end

local function update_diff_cursor_shape()
  if is_diff_window(vim.api.nvim_get_current_win()) then
    vim.o.guicursor = diff_guicursor()
  elseif state.default_guicursor then
    vim.o.guicursor = state.default_guicursor
  end
end

local function clear_window_cursorline(window, match_field)
  if not window or not vim.api.nvim_win_is_valid(window) then
    state[match_field] = nil
    return
  end

  local buffer = vim.api.nvim_win_get_buf(window)
  vim.api.nvim_buf_clear_namespace(buffer, cursorline_namespace, 0, -1)

  if state[match_field] then
    local match_id = state[match_field]
    state[match_field] = nil

    vim.api.nvim_win_call(window, function()
      pcall(vim.fn.matchdelete, match_id)
    end)
  end
end

local function clear_diff_cursorlines()
  clear_window_cursorline(state.left_win, "left_match")
  clear_window_cursorline(state.right_win, "right_match")
end

local function update_active_diff_cursorline()
  clear_diff_cursorlines()

  local window = vim.api.nvim_get_current_win()

  if not is_diff_window(window) then
    update_diff_cursor_shape()
    return
  end

  update_diff_cursor_shape()

  local buffer = vim.api.nvim_win_get_buf(window)
  local line_number = vim.api.nvim_win_get_cursor(window)[1]
  local line = vim.api.nvim_buf_get_lines(buffer, line_number - 1, line_number, false)[1] or ""
  local line_width = vim.fn.strdisplaywidth(line)
  local window_width = vim.api.nvim_win_get_width(window)
  local padding_width = math.max(window_width - line_width, 0)
  local match_field = window == state.left_win and "left_match" or "right_match"

  vim.api.nvim_win_call(window, function()
    if #line > 0 then
      state[match_field] = vim.fn.matchaddpos("DiffCursorLine", { { line_number, 1, #line + 1 } }, 20)
    end
  end)

  if padding_width > 0 then
    vim.api.nvim_buf_set_extmark(buffer, cursorline_namespace, line_number - 1, #line, {
      virt_text = { { string.rep(" ", padding_width), "DiffCursorLine" } },
      virt_text_pos = "inline",
      priority = 20,
    })
  end
end

local function place_diff_sign(buffer, sign_id, sign_name, line_number)
  if line_number < 1 or line_number > vim.api.nvim_buf_line_count(buffer) then
    return sign_id
  end

  vim.fn.sign_place(sign_id, diff_sign_group, sign_name, buffer, {
    lnum = line_number,
    priority = 20,
  })

  return sign_id + 1
end

local function place_range_signs(buffer, sign_id, sign_name, start_line, count)
  for offset = 0, count - 1 do
    sign_id = place_diff_sign(buffer, sign_id, sign_name, start_line + offset)
  end

  return sign_id
end

local function mark_diff_lines(left_buffer, right_buffer, left_path, right_path)
  vim.fn.sign_unplace(diff_sign_group, { buffer = left_buffer })
  vim.fn.sign_unplace(diff_sign_group, { buffer = right_buffer })

  local diff = vim.fn.systemlist({ "diff", "-U0", "--", left_path, right_path })
  local left_sign_id = 1
  local right_sign_id = 1

  for _, line in ipairs(diff) do
    local old_start, old_count, new_start, new_count =
      line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")

    if old_start then
      old_start = tonumber(old_start)
      old_count = tonumber(old_count ~= "" and old_count or "1")
      new_start = tonumber(new_start)
      new_count = tonumber(new_count ~= "" and new_count or "1")

      if old_count == 0 then
        right_sign_id = place_range_signs(right_buffer, right_sign_id, "GitAddedLine", new_start, new_count)
      elseif new_count == 0 then
        left_sign_id = place_range_signs(left_buffer, left_sign_id, "GitDeletedLine", old_start, old_count)
      else
        left_sign_id = place_range_signs(left_buffer, left_sign_id, "GitModifiedLine", old_start, old_count)
        right_sign_id = place_range_signs(right_buffer, right_sign_id, "GitModifiedLine", new_start, new_count)
      end
    end
  end
end

local function align_diff_folds()
  if not state.left_win or not state.right_win then
    return
  end

  if not vim.api.nvim_win_is_valid(state.left_win) or not vim.api.nvim_win_is_valid(state.right_win) then
    return
  end

  for _, window in ipairs({ state.left_win, state.right_win }) do
    vim.wo[window].foldmethod = "diff"
    vim.wo[window].foldenable = true
    vim.wo[window].foldlevel = 0
  end

  vim.cmd("diffupdate")

  for _, window in ipairs({ state.left_win, state.right_win }) do
    vim.api.nvim_win_call(window, function()
      vim.cmd("normal! zM")
    end)
  end
end

local function ensure_diff_filler()
  vim.opt.diffopt:append("filler")
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

local function enable_diff_sync()
  if not state.left_win or not state.right_win then
    return
  end

  if not vim.api.nvim_win_is_valid(state.left_win) or not vim.api.nvim_win_is_valid(state.right_win) then
    return
  end

  for _, window in ipairs({ state.left_win, state.right_win }) do
    vim.wo[window].scrollbind = true
    vim.wo[window].cursorbind = true
  end

  local view = {
    topline = 1,
    lnum = 1,
    col = 0,
    leftcol = 0,
  }

  vim.api.nvim_win_call(state.left_win, function()
    vim.fn.winrestview(view)
  end)

  vim.api.nvim_win_call(state.right_win, function()
    vim.fn.winrestview(view)
  end)

  vim.api.nvim_win_call(state.left_win, function()
    vim.cmd("syncbind")
  end)

  update_active_diff_cursorline()
end

local function open_current_diff(focus_right)
  local entry = current_entry()

  if not entry then
    return
  end

  ensure_diff_windows()
  ensure_diff_filler()
  vim.cmd("diffoff!")
  local left_path = path_for_side("left", entry)
  local right_path = path_for_side("right", entry)
  local left_buffer = edit_window(state.left_win, left_path, entry)
  local right_buffer = edit_window(state.right_win, right_path, entry)
  mark_diff_lines(left_buffer, right_buffer, left_path, right_path)
  align_diff_folds()
  enable_diff_sync()

  if focus_right then
    vim.api.nvim_set_current_win(state.right_win)
    update_active_diff_cursorline()
  else
    vim.api.nvim_set_current_win(state.list_win)
  end
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

local function tree_node_all_staged(node)
  local has_files = false

  for _, file in ipairs(node.files) do
    has_files = true

    if not state.staged_files[file.entry.path] then
      return false
    end
  end

  for _, dirname in ipairs(sorted_keys(node.dirs)) do
    has_files = true

    if not tree_node_all_staged(node.dirs[dirname]) then
      return false
    end
  end

  return has_files
end

local function render_tree_node(node, depth, path, lines)
  local prefix = string.rep("| ", depth)

  for _, dirname in ipairs(sorted_keys(node.dirs)) do
    local dir_path = path == "" and dirname or path .. "/" .. dirname
    local dir_node = node.dirs[dirname]
    local collapsed = state.collapsed_dirs[dir_path]
    local marker = collapsed and "▸ " or "▾ "

    table.insert(lines, prefix .. marker .. dirname .. "/")
    state.line_entries[#lines] = {
      color_start = #prefix,
      highlight = tree_node_all_staged(dir_node) and staged_file_highlight or nil,
      kind = "dir",
      path = dir_path,
    }

    if not collapsed then
      render_tree_node(dir_node, depth + 1, dir_path, lines)
    end
  end

  table.sort(node.files, function(a, b)
    return a.name < b.name
  end)

  for _, file in ipairs(node.files) do
    local line = prefix .. file.entry.status .. " " .. file.name

    table.insert(lines, line)
    state.line_entries[#lines] = {
      color_start = #prefix,
      entry = file.entry,
      kind = "file",
      path = file.entry.path,
    }
    state.first_file_line = state.first_file_line or #lines
  end
end

set_cursor_to_path = function(path)
  if not path or not state.list_win or not vim.api.nvim_win_is_valid(state.list_win) then
    return
  end

  for line_number, item in pairs(state.line_entries) do
    if item and item.path == path then
      vim.api.nvim_win_set_cursor(state.list_win, { line_number, 0 })
      return
    end
  end
end

render_file_list = function()
  local lines = {}
  state.first_file_line = nil
  state.line_entries = {}
  refresh_staged_files()

  if #state.files > 0 then
    table.insert(lines, "../")
    state.line_entries[#lines] = {
      kind = "meta",
      path = "..",
    }

    table.insert(lines, "./")
    state.line_entries[#lines] = {
      kind = "meta",
      path = ".",
    }

    table.insert(lines, root_label() .. "/")
    state.line_entries[#lines] = {
      kind = "root",
      path = "",
    }

    render_tree_node(build_file_tree(), 1, "", lines)
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
    if entry.color_start and entry.color_start > 0 then
      vim.api.nvim_buf_set_extmark(state.list_buf, namespace, line_number - 1, 0, {
        end_col = entry.color_start,
        hl_group = "DiffTreePipe",
      })
    end

    local file_entry = item_entry(entry)
    local highlight = file_entry and state.staged_files[file_entry.path] and staged_file_highlight
      or file_entry and file_highlights[file_entry.status]
      or entry.highlight

    if highlight then
      vim.api.nvim_buf_set_extmark(state.list_buf, namespace, line_number - 1, entry.color_start, {
        end_col = #lines[line_number],
        hl_group = highlight,
      })
    end
  end
end

local function rerender_tree_at(path)
  render_file_list()
  set_cursor_to_path(path)
end

local function toggle_tree_item()
  local item = current_tree_item()

  if not item then
    return
  end

  if item.kind == "dir" then
    state.collapsed_dirs[item.path] = not state.collapsed_dirs[item.path]
    rerender_tree_at(item.path)
    return
  end

  if item.kind == "file" then
    open_current_diff(true)
  end
end

local function collapse_tree_item()
  local item = current_tree_item()

  if item and item.kind == "dir" and not state.collapsed_dirs[item.path] then
    state.collapsed_dirs[item.path] = true
    rerender_tree_at(item.path)
  end
end

local function expand_tree_item()
  local item = current_tree_item()

  if item and item.kind == "dir" and state.collapsed_dirs[item.path] then
    state.collapsed_dirs[item.path] = false
    rerender_tree_at(item.path)
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

  vim.keymap.set("n", "<CR>", toggle_tree_item, {
    buffer = state.list_buf,
    desc = "Open directory diff file or toggle folder",
    silent = true,
  })

  vim.keymap.set("n", "h", collapse_tree_item, {
    buffer = state.list_buf,
    desc = "Collapse directory diff folder",
    silent = true,
  })

  vim.keymap.set("n", "l", expand_tree_item, {
    buffer = state.list_buf,
    desc = "Expand directory diff folder",
    silent = true,
  })

  vim.keymap.set("n", "<leader>ga", function()
    add_tree_item_to_stage()
  end, {
    buffer = state.list_buf,
    desc = "Git add directory diff file",
    silent = true,
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
  state.default_guicursor = vim.o.guicursor

  vim.api.nvim_create_autocmd("VimEnter", {
    callback = function()
      vim.schedule(maybe_start_directory_diff)
    end,
  })

  vim.api.nvim_create_autocmd({ "CursorMoved", "WinEnter", "WinScrolled" }, {
    callback = function()
      update_active_diff_cursorline()
    end,
  })

  vim.api.nvim_create_autocmd({ "WinLeave", "BufLeave" }, {
    callback = function()
      vim.schedule(update_diff_cursor_shape)
    end,
  })
end

return M
