local util = require("config.util")

local M = {}

local file_picker_namespace = vim.api.nvim_create_namespace("file_picker")
local netrw_git_namespace = vim.api.nvim_create_namespace("netrw_git_status")
local text_preview_namespace = vim.api.nvim_create_namespace("text_preview")

local netrw_winhighlight = table.concat({
  "Normal:NetrwNormal",
  "NormalNC:NetrwNormal",
  "CursorLine:NetrwCursorLine",
  "EndOfBuffer:NetrwEndOfBuffer",
  "LineNr:NetrwLineNr",
  "NonText:NetrwNonText",
  "SignColumn:NetrwSignColumn",
}, ",")

local file_picker_winhighlight = table.concat({
  "Normal:FilePickerNormal",
  "NormalFloat:FilePickerNormal",
  "FloatBorder:FilePickerBorder",
  "FloatTitle:FilePickerBorder",
  "EndOfBuffer:FilePickerNormal",
  "NonText:FilePickerNormal",
}, ",")

local function apply_window_highlights(buffer)
  for _, window in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(window) == buffer then
      vim.wo[window].winhighlight = netrw_winhighlight
    end
  end
end

local function sync_window_highlights(buffer)
  for _, window in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(window) == buffer then
      if vim.bo[buffer].filetype == "netrw" then
        vim.wo[window].winhighlight = netrw_winhighlight
      elseif vim.wo[window].winhighlight == netrw_winhighlight then
        vim.wo[window].winhighlight = ""
      end
    end
  end
end

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
  vim.wo[prompt_win].winhighlight = file_picker_winhighlight

  result_win = vim.api.nvim_open_win(result_buf, false, {
    relative = "editor",
    row = row + 3,
    col = col,
    width = width,
    height = result_height,
    border = "single",
    style = "minimal",
  })
  vim.wo[result_win].winhighlight = file_picker_winhighlight

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

local function rg_project_command(root, query)
  return {
    "rg",
    "--vimgrep",
    "--hidden",
    "--no-messages",
    "--line-buffered",
    "--color",
    "never",
    "--glob",
    "!.git",
    "--smart-case",
    "--max-columns",
    "240",
    "--",
    query,
    root,
  }
end

local function parse_rg_match(line)
  local path, line_number, column, text = line:match("^(.-):(%d+):(%d+):(.*)$")

  if not path then
    return nil
  end

  return {
    path = path,
    line = tonumber(line_number),
    column = tonumber(column),
    text = text,
  }
end

local function format_text_match(root, match)
  local relative = util.relative_path(root, match.path)
  local location = relative .. ":" .. match.line .. ":" .. match.column
  local text = vim.trim(match.text)

  if text == "" then
    return location
  end

  return location .. "  " .. text
end

local function read_preview_lines(root, match, height)
  local ok, file_lines = pcall(vim.fn.readfile, match.path, "", math.max(match.line + height, height))

  if not ok then
    return { "Could not read preview." }, nil
  end

  local relative = util.relative_path(root, match.path)
  local context = math.max(2, math.floor((height - 3) / 2))
  local start_line = math.max(1, match.line - context)
  local end_line = math.min(#file_lines, start_line + height - 3)
  start_line = math.max(1, math.min(start_line, end_line - height + 4))

  local display = {
    relative .. ":" .. match.line .. ":" .. match.column,
    "",
  }

  local number_width = #tostring(end_line)

  for line_number = start_line, end_line do
    table.insert(display, string.format("%" .. number_width .. "d  %s", line_number, file_lines[line_number] or ""))
  end

  return display, match.line - start_line + 2
end

local function open_text_from_search()
  local directory = netrw_current_dir()
  local root = util.git_root_for(directory) or directory
  local matches = {}
  local selected = 1
  local scroll_offset = 0
  local last_query = nil
  local error_message = nil
  local searching = false
  local search_generation = 0
  local search_timer = vim.uv.new_timer()
  local running_job = nil
  local max_results = 12
  local min_query_length = 2
  local columns = vim.o.columns
  local lines = vim.o.lines
  local width = math.min(math.max(72, math.floor(columns * 0.88)), columns - 4)
  local preview_width = width >= 92 and math.max(34, math.floor(width * 0.48)) or 0
  local gutter_width = preview_width > 0 and 2 or 0
  local result_width = width - preview_width - gutter_width
  local result_height = math.min(max_results, math.max(5, lines - 8))
  local preview_height = preview_width > 0 and result_height + 3 or 0
  local row = math.max(1, math.floor((lines - result_height - 3) / 3))
  local col = math.max(0, math.floor((columns - width) / 2))
  local prompt_buf = vim.api.nvim_create_buf(false, true)
  local result_buf = vim.api.nvim_create_buf(false, true)
  local preview_buf = preview_width > 0 and vim.api.nvim_create_buf(false, true) or nil
  local prompt_win
  local result_win
  local preview_win
  local autocmd
  local closed = false

  local function set_matches(next_matches, next_error)
    matches = next_matches or {}
    error_message = next_error
    searching = false
    selected = 1
    scroll_offset = 0
  end

  local function close_picker()
    closed = true
    search_generation = search_generation + 1

    if search_timer then
      search_timer:stop()
      search_timer:close()
      search_timer = nil
    end

    if running_job then
      vim.fn.jobstop(running_job)
      running_job = nil
    end

    if autocmd then
      pcall(vim.api.nvim_del_autocmd, autocmd)
    end

    if prompt_win and vim.api.nvim_win_is_valid(prompt_win) then
      vim.api.nvim_win_close(prompt_win, true)
    end

    if result_win and vim.api.nvim_win_is_valid(result_win) then
      vim.api.nvim_win_close(result_win, true)
    end

    if preview_win and vim.api.nvim_win_is_valid(preview_win) then
      vim.api.nvim_win_close(preview_win, true)
    end

    if vim.api.nvim_buf_is_valid(prompt_buf) then
      vim.api.nvim_buf_delete(prompt_buf, { force = true })
    end

    if vim.api.nvim_buf_is_valid(result_buf) then
      vim.api.nvim_buf_delete(result_buf, { force = true })
    end

    if preview_buf and vim.api.nvim_buf_is_valid(preview_buf) then
      vim.api.nvim_buf_delete(preview_buf, { force = true })
    end
  end

  local function draw_preview()
    if not preview_buf or closed or not vim.api.nvim_buf_is_valid(preview_buf) then
      return
    end

    vim.bo[preview_buf].modifiable = true

    local match = matches[selected]

    if not match then
      vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, { "No preview." })
      vim.api.nvim_buf_clear_namespace(preview_buf, text_preview_namespace, 0, -1)
      vim.bo[preview_buf].modifiable = false
      return
    end

    local display, highlighted_row = read_preview_lines(root, match, preview_height)

    vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, display)
    vim.api.nvim_buf_clear_namespace(preview_buf, text_preview_namespace, 0, -1)

    if highlighted_row then
      vim.api.nvim_buf_set_extmark(preview_buf, text_preview_namespace, highlighted_row, 0, {
        line_hl_group = "FilePickerSelected",
      })
    end

    vim.bo[preview_buf].modifiable = false
  end

  local function draw_results()
    if closed or not vim.api.nvim_buf_is_valid(result_buf) or not vim.api.nvim_buf_is_valid(prompt_buf) then
      return
    end

    local query = vim.api.nvim_buf_get_lines(prompt_buf, 0, 1, false)[1] or ""

    selected = math.min(selected, math.max(#matches, 1))

    if selected <= scroll_offset then
      scroll_offset = selected - 1
    elseif selected > scroll_offset + result_height then
      scroll_offset = selected - result_height
    end

    scroll_offset = math.max(0, math.min(scroll_offset, math.max(#matches - result_height, 0)))

    local display = {}

    if query == "" then
      display = { "Type to grep text in " .. vim.fn.fnamemodify(root, ":~:.") }
    elseif #query < min_query_length then
      display = { "Type at least " .. min_query_length .. " characters" }
    elseif searching and #matches == 0 then
      display = { "Searching with rg..." }
    elseif error_message then
      display = { error_message }
    elseif #matches == 0 then
      display = { "No text matching: " .. query }
    else
      for index = scroll_offset + 1, #matches do
        if #display >= result_height then
          break
        end

        table.insert(display, format_text_match(root, matches[index]))
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

    draw_preview()
  end

  local function start_search(query, generation)
    if running_job then
      vim.fn.jobstop(running_job)
      running_job = nil
    end

    if closed then
      return
    end

    if vim.fn.executable("rg") ~= 1 then
      set_matches(nil, "Install rg to search project text.")
      draw_results()
      return
    end

    if query == "" or #query < min_query_length then
      set_matches({}, nil)
      draw_results()
      return
    end

    searching = true
    matches = {}
    error_message = nil
    draw_results()

    local stdout_tail = ""
    local stopped_after_limit = false
    local result_limit = 200

    local function consume_stdout(data, flush_tail)
      if not data or #data == 0 then
        return
      end

      if #data == 1 and data[1] == "" and not flush_tail then
        return
      end

      if stdout_tail ~= "" then
        data[1] = stdout_tail .. data[1]
        stdout_tail = ""
      end

      local complete_until = #data

      if data[#data] ~= "" then
        if flush_tail then
          complete_until = #data
        else
          stdout_tail = data[#data]
          complete_until = #data - 1
        end
      elseif flush_tail and stdout_tail ~= "" then
        data[#data] = stdout_tail
        stdout_tail = ""
      end

      for index = 1, complete_until do
        local match = parse_rg_match(data[index])

        if match then
          table.insert(matches, match)
        end

        if #matches >= result_limit then
          break
        end
      end
    end

    running_job = vim.fn.jobstart(rg_project_command(root, query), {
      stderr_buffered = true,
      on_stdout = function(_, data)
        vim.schedule(function()
          if closed or generation ~= search_generation then
            return
          end

          consume_stdout(data, false)

          if #matches >= result_limit and running_job then
            stopped_after_limit = true
            vim.fn.jobstop(running_job)
          end

          draw_results()
        end)
      end,
      on_stderr = function(_, data)
        local message

        for _, line in ipairs(data or {}) do
          if line ~= "" then
            message = line
            break
          end
        end

        if message then
          vim.schedule(function()
            if not closed and generation == search_generation then
              error_message = message
            end
          end)
        end
      end,
      on_exit = function(_, code)
        vim.schedule(function()
          if closed or generation ~= search_generation then
            return
          end

          consume_stdout({ "" }, true)
          running_job = nil
          searching = false

          if code > 1 and not stopped_after_limit and not error_message then
            error_message = "Search failed."
          end

          draw_results()
        end)
      end,
    })

    if running_job <= 0 then
      running_job = nil
      set_matches(nil, "Could not start rg.")
      draw_results()
    end
  end

  local function schedule_search()
    if closed then
      return
    end

    local query = vim.api.nvim_buf_get_lines(prompt_buf, 0, 1, false)[1] or ""

    if query == last_query then
      draw_results()
      return
    end

    last_query = query
    search_generation = search_generation + 1

    if running_job then
      vim.fn.jobstop(running_job)
      running_job = nil
    end

    if query == "" or #query < min_query_length then
      set_matches({}, nil)
      draw_results()
      return
    end

    searching = true
    matches = {}
    error_message = nil
    draw_results()

    if search_timer then
      search_timer:stop()
      search_timer:start(150, 0, vim.schedule_wrap(function()
        start_search(query, search_generation)
      end))
    end
  end

  local function render_results()
    schedule_search()
  end

  local function open_selected(query)
    if query and query ~= "" and query ~= last_query then
      schedule_search()
    end

    local match = matches[selected]

    if not match then
      return
    end

    close_picker()
    vim.cmd.edit(vim.fn.fnameescape(match.path))
    vim.api.nvim_win_set_cursor(0, { match.line, math.max(match.column - 1, 0) })
    vim.cmd.normal({ "zvzz", bang = true })
  end

  prompt_win = vim.api.nvim_open_win(prompt_buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = result_width,
    height = 1,
    border = "single",
    title = " Grep text ",
    style = "minimal",
  })
  vim.wo[prompt_win].winhighlight = file_picker_winhighlight

  result_win = vim.api.nvim_open_win(result_buf, false, {
    relative = "editor",
    row = row + 3,
    col = col,
    width = result_width,
    height = result_height,
    border = "single",
    style = "minimal",
  })
  vim.wo[result_win].winhighlight = file_picker_winhighlight

  if preview_buf then
    preview_win = vim.api.nvim_open_win(preview_buf, false, {
      relative = "editor",
      row = row,
      col = col + result_width + gutter_width,
      width = preview_width,
      height = preview_height,
      border = "single",
      title = " Preview ",
      style = "minimal",
    })
    vim.wo[preview_win].winhighlight = file_picker_winhighlight
  end

  vim.bo[prompt_buf].buftype = "prompt"
  vim.fn.prompt_setprompt(prompt_buf, "")
  vim.fn.prompt_setcallback(prompt_buf, open_selected)
  vim.bo[result_buf].modifiable = false
  if preview_buf then
    vim.bo[preview_buf].modifiable = false
    vim.bo[preview_buf].buftype = "nofile"
    vim.bo[preview_buf].bufhidden = "wipe"
  end

  autocmd = vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    buffer = prompt_buf,
    callback = render_results,
  })

  vim.keymap.set({ "i", "n" }, "<Esc>", close_picker, { buffer = prompt_buf, silent = true })
  vim.keymap.set("i", "<C-c>", close_picker, { buffer = prompt_buf, silent = true })
  vim.keymap.set("i", "<Down>", function()
    selected = math.min(selected + 1, #matches)
    draw_results()
  end, { buffer = prompt_buf, silent = true })
  vim.keymap.set("i", "<Up>", function()
    selected = math.max(selected - 1, 1)
    draw_results()
  end, { buffer = prompt_buf, silent = true })

  draw_results()
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
      apply_window_highlights(event.buf)

      vim.keymap.set("n", "/", open_file_from_search, {
        buffer = event.buf,
        desc = "Find file by name",
        silent = true,
      })

      vim.keymap.set("n", "<leader>/", open_text_from_search, {
        buffer = event.buf,
        desc = "Grep project text",
        silent = true,
      })

      vim.defer_fn(function()
        if vim.api.nvim_buf_is_valid(event.buf) then
          mark_git_status(event.buf)
        end
      end, 50)
    end,
  })

  vim.api.nvim_create_autocmd("BufWinEnter", {
    callback = function(event)
      sync_window_highlights(event.buf)
    end,
  })
end

return M
