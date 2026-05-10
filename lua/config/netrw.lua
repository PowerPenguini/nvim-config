local util = require("config.util")

local M = {}

local file_picker_namespace = vim.api.nvim_create_namespace("file_picker")
local netrw_git_namespace = vim.api.nvim_create_namespace("netrw_git_status")

local function netrw_current_dir(buffer)
  buffer = buffer or 0

  if vim.b[buffer].netrw_curdir and vim.b[buffer].netrw_curdir ~= "" then
    return vim.b[buffer].netrw_curdir
  end

  local buffer_path = vim.api.nvim_buf_get_name(buffer)

  if buffer_path ~= "" and vim.fn.isdirectory(buffer_path) == 1 then
    return buffer_path
  end

  return vim.fn.getcwd()
end

local function add_git_status_path(statuses, path, status)
  path = util.normalize_git_path(path)

  if path == "" then
    return
  end

  if status == "unstaged" or not statuses[path] then
    statuses[path] = status
  end

  local parent = vim.fs.dirname(path)

  while parent and parent ~= "." and parent ~= "" do
    if status == "unstaged" or not statuses[parent] then
      statuses[parent] = status
    end

    parent = vim.fs.dirname(parent)
  end
end

local function git_status_map(root)
  local output = util.git_output(root, { "status", "--porcelain=v1" })
  local statuses = {}

  if not output then
    return statuses
  end

  for _, line in ipairs(output) do
    local index_status = line:sub(1, 1)
    local worktree_status = line:sub(2, 2)
    local path = line:sub(4)

    if path:find(" -> ", 1, true) then
      path = path:match(" %-> (.+)$") or path
    end

    local status = "unstaged"

    if worktree_status ~= " " or index_status == "?" then
      status = "unstaged"
    elseif index_status ~= " " then
      status = "staged"
    end

    add_git_status_path(statuses, path, status)
  end

  return statuses
end

local function netrw_line_path(root, directory, line)
  local name = vim.trim(line)

  if name == "" or name:sub(1, 1) == '"' or name == "../" or name == "./" then
    return nil
  end

  name = name:gsub("[/*@=|]$", "")

  if name == "" then
    return nil
  end

  return util.normalize_git_path(util.relative_path(root, directory .. "/" .. name))
end

local function netrw_tree_line_paths(root, lines)
  local paths = {}
  local stack = {}
  local root_name = vim.fs.basename(root)
  local saw_tree_root = false

  for index, line in ipairs(lines) do
    local text = vim.trim(line)

    if text == "" or text:sub(1, 1) == '"' or text == "../" or text == "./" then
      goto continue
    end

    local depth = 0

    while text:sub(1, 2) == "| " do
      depth = depth + 1
      text = text:sub(3)
    end

    text = vim.trim(text)

    if text == "" then
      goto continue
    end

    local is_directory = text:sub(-1) == "/"
    local name = text:gsub("[/*@=|]$", "")

    if name == "" then
      goto continue
    end

    if depth == 0 and is_directory and name == root_name then
      stack[0] = ""
      saw_tree_root = true
      goto continue
    end

    if not saw_tree_root then
      goto continue
    end

    local parent = stack[depth - 1]

    if not parent then
      goto continue
    end

    local path = parent == "" and name or parent .. "/" .. name
    paths[index] = util.normalize_git_path(path)

    if is_directory then
      stack[depth] = paths[index]
    end

    ::continue::
  end

  return paths
end

local function mark_git_status(buffer)
  vim.api.nvim_buf_clear_namespace(buffer, netrw_git_namespace, 0, -1)

  local directory = netrw_current_dir(buffer)
  local root = util.git_root_for(directory)

  if not root then
    return
  end

  local statuses = git_status_map(root)
  local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  local tree_paths = netrw_tree_line_paths(root, lines)

  for index, line in ipairs(lines) do
    local path = tree_paths[index] or netrw_line_path(root, directory, line)
    local status = path and statuses[path]

    if status then
      vim.api.nvim_buf_set_extmark(buffer, netrw_git_namespace, index - 1, 0, {
        line_hl_group = status == "staged" and "NetrwGitStaged" or "NetrwGitUnstaged",
      })
    end
  end
end

function M.refresh_git_status()
  for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buffer) and vim.bo[buffer].filetype == "netrw" then
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buffer) and vim.bo[buffer].filetype == "netrw" then
          mark_git_status(buffer)
        end
      end)
    end
  end
end

local function list_files(root)
  if vim.fn.executable("rg") == 1 then
    local files = vim.fn.systemlist({ "rg", "--files", "--hidden", "--glob", "!.git", root })

    if vim.v.shell_error == 0 then
      table.sort(files)
      return files
    end
  end

  local files = {}

  local function scan(directory)
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
        local path = directory .. "/" .. name

        if kind == "directory" then
          scan(path)
        elseif kind == "file" then
          table.insert(files, path)
        end
      end
    end
  end

  scan(root)
  table.sort(files)

  return files
end

local function filter_files_by_name(files, query)
  if query == "" then
    return {}
  end

  local matches = {}
  local lower_query = query:lower()

  for _, path in ipairs(files) do
    local name = vim.fs.basename(path)

    if name:lower():find(lower_query, 1, true) then
      table.insert(matches, path)
    end
  end

  return matches
end

local function open_file_from_search()
  local root = netrw_current_dir()
  local files = list_files(root)
  local matches = {}
  local selected = 1
  local scroll_offset = 0
  local last_query = nil
  local max_results = 12
  local columns = vim.o.columns
  local lines = vim.o.lines
  local width = math.min(math.max(48, math.floor(columns * 0.6)), columns - 4)
  local result_height = math.min(max_results, math.max(5, lines - 8))
  local row = math.max(1, math.floor((lines - result_height - 3) / 3))
  local col = math.max(0, math.floor((columns - width) / 2))
  local prompt_buf = vim.api.nvim_create_buf(false, true)
  local result_buf = vim.api.nvim_create_buf(false, true)
  local prompt_win
  local result_win
  local autocmd

  local function close_picker()
    if autocmd then
      pcall(vim.api.nvim_del_autocmd, autocmd)
    end

    if prompt_win and vim.api.nvim_win_is_valid(prompt_win) then
      vim.api.nvim_win_close(prompt_win, true)
    end

    if result_win and vim.api.nvim_win_is_valid(result_win) then
      vim.api.nvim_win_close(result_win, true)
    end

    if vim.api.nvim_buf_is_valid(prompt_buf) then
      vim.api.nvim_buf_delete(prompt_buf, { force = true })
    end

    if vim.api.nvim_buf_is_valid(result_buf) then
      vim.api.nvim_buf_delete(result_buf, { force = true })
    end
  end

  local function render_results()
    local query = vim.api.nvim_get_current_line()

    if query ~= last_query then
      selected = 1
      scroll_offset = 0
      last_query = query
    end

    matches = filter_files_by_name(files, query)
    selected = math.min(selected, math.max(#matches, 1))

    if selected <= scroll_offset then
      scroll_offset = selected - 1
    elseif selected > scroll_offset + result_height then
      scroll_offset = selected - result_height
    end

    scroll_offset = math.max(0, math.min(scroll_offset, math.max(#matches - result_height, 0)))

    local display = {}

    if query == "" then
      display = { "Type to search files in " .. vim.fn.fnamemodify(root, ":~:.") }
    elseif #matches == 0 then
      display = { "No files matching: " .. query }
    else
      for index = scroll_offset + 1, #matches do
        if #display >= result_height then
          break
        end

        table.insert(display, util.relative_path(root, matches[index]))
      end
    end

    vim.bo[result_buf].modifiable = true
    vim.api.nvim_buf_set_lines(result_buf, 0, -1, false, display)
    vim.bo[result_buf].modifiable = false
    vim.api.nvim_buf_clear_namespace(result_buf, file_picker_namespace, 0, -1)

    local selected_row = selected - scroll_offset - 1

    if query ~= "" and #matches > 0 and selected_row >= 0 and selected_row < #display then
      vim.api.nvim_buf_set_extmark(result_buf, file_picker_namespace, selected_row, 0, {
        line_hl_group = "FilePickerSelected",
      })
    end
  end

  local function open_selected(query)
    if query and query ~= "" then
      matches = filter_files_by_name(files, query)

      if query ~= last_query then
        selected = 1
        last_query = query
      end

      selected = math.min(selected, math.max(#matches, 1))
    end

    local path = matches[selected]

    if not path then
      return
    end

    close_picker()
    vim.cmd.edit(vim.fn.fnameescape(path))
  end

  prompt_win = vim.api.nvim_open_win(prompt_buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = 1,
    border = "single",
    title = " Find file ",
    style = "minimal",
  })

  result_win = vim.api.nvim_open_win(result_buf, false, {
    relative = "editor",
    row = row + 3,
    col = col,
    width = width,
    height = result_height,
    border = "single",
    style = "minimal",
  })

  vim.bo[prompt_buf].buftype = "prompt"
  vim.fn.prompt_setprompt(prompt_buf, "")
  vim.fn.prompt_setcallback(prompt_buf, open_selected)
  vim.bo[result_buf].modifiable = false

  autocmd = vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    buffer = prompt_buf,
    callback = render_results,
  })

  vim.keymap.set({ "i", "n" }, "<Esc>", close_picker, { buffer = prompt_buf, silent = true })
  vim.keymap.set("i", "<C-c>", close_picker, { buffer = prompt_buf, silent = true })
  vim.keymap.set("i", "<Down>", function()
    selected = math.min(selected + 1, #matches)
    render_results()
  end, { buffer = prompt_buf, silent = true })
  vim.keymap.set("i", "<Up>", function()
    selected = math.max(selected - 1, 1)
    render_results()
  end, { buffer = prompt_buf, silent = true })

  render_results()
  vim.cmd.startinsert()
end

function M.toggle_file_explorer()
  local current_window = vim.api.nvim_get_current_win()

  for _, window in ipairs(vim.api.nvim_list_wins()) do
    local buffer = vim.api.nvim_win_get_buf(window)

    if vim.bo[buffer].filetype == "netrw" then
      if window ~= current_window then
        vim.api.nvim_set_current_win(window)
        return
      end

      if #vim.api.nvim_list_wins() > 1 then
        vim.api.nvim_win_close(window, true)
      else
        vim.api.nvim_buf_delete(buffer, { force = true })
      end

      return
    end
  end

  vim.cmd.Lexplore(vim.fn.fnameescape(util.current_buffer_directory()))
end

function M.setup()
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "netrw",
    callback = function(event)
      vim.keymap.set("n", "/", open_file_from_search, {
        buffer = event.buf,
        desc = "Find file by name",
        silent = true,
      })

      vim.defer_fn(function()
        if vim.api.nvim_buf_is_valid(event.buf) then
          mark_git_status(event.buf)
        end
      end, 50)
    end,
  })
end

return M
