vim.g.mapleader = " "

vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.wrap = false
vim.opt.completeopt = { "menuone", "noselect", "popup" }

vim.cmd.colorscheme("nord")

vim.api.nvim_set_hl(0, "GitAddedLine", { fg = "#a3be8c" })
vim.api.nvim_set_hl(0, "GitModifiedLine", { fg = "#bf616a" })
vim.api.nvim_set_hl(0, "GitDeletedLine", { fg = "#bf616a" })
vim.api.nvim_set_hl(0, "FilePickerSelected", { bg = "#3b4252", fg = "#eceff4", bold = true })
vim.api.nvim_set_hl(0, "NetrwGitUnstaged", { fg = "#ebcb8b", bold = true })
vim.api.nvim_set_hl(0, "NetrwGitStaged", { fg = "#a3be8c", bold = true })
vim.fn.sign_define("GitAddedLine", { text = "▌", texthl = "GitAddedLine", numhl = "GitAddedLine" })
vim.fn.sign_define("GitModifiedLine", { text = "▌", texthl = "GitModifiedLine", numhl = "GitModifiedLine" })

local git_sign_group = "git_changed_lines"
local git_deleted_namespace = vim.api.nvim_create_namespace("git_deleted_lines")
local file_picker_namespace = vim.api.nvim_create_namespace("file_picker")
local netrw_git_namespace = vim.api.nvim_create_namespace("netrw_git_status")

local function git_output(cwd, args)
  local command = { "git", "-C", cwd }
  vim.list_extend(command, args)
  local output = vim.fn.systemlist(command)

  if vim.v.shell_error ~= 0 then
    return nil
  end

  return output
end

local function relative_path(root, file_path)
  local prefix = root .. "/"

  if file_path:sub(1, #prefix) == prefix then
    return file_path:sub(#prefix + 1)
  end

  return file_path
end

local function mark_git_changed_lines(buffer)
  local file_path = vim.api.nvim_buf_get_name(buffer)

  vim.fn.sign_unplace(git_sign_group, { buffer = buffer })
  vim.api.nvim_buf_clear_namespace(buffer, git_deleted_namespace, 0, -1)

  if file_path == "" then
    return
  end

  local file_dir = vim.fs.dirname(file_path)
  local root_output = git_output(file_dir, { "rev-parse", "--show-toplevel" })

  if not root_output or not root_output[1] then
    return
  end

  local root = root_output[1]
  local path = relative_path(root, file_path)
  local diff = git_output(root, { "diff", "--unified=0", "--no-ext-diff", "--", path })

  if not diff then
    return
  end

  local sign_id = 1
  local line_count = vim.api.nvim_buf_line_count(buffer)

  for _, line in ipairs(diff) do
    local old_start, old_count, new_start, new_count =
      line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")

    if old_start then
      old_count = tonumber(old_count ~= "" and old_count or "1")
      new_start = tonumber(new_start)
      new_count = tonumber(new_count ~= "" and new_count or "1")

      if new_count == 0 then
        local mark_line = math.max(math.min(new_start, line_count), 0)

        vim.api.nvim_buf_set_extmark(buffer, git_deleted_namespace, mark_line, 0, {
          virt_lines = {
            { { string.rep("─", 32), "GitDeletedLine" } },
          },
          virt_lines_above = true,
        })
      else
        local changed_count = math.min(old_count, new_count)

        for offset = 0, changed_count - 1 do
          vim.fn.sign_place(sign_id, git_sign_group, "GitModifiedLine", buffer, {
            lnum = new_start + offset,
            priority = 10,
          })
          sign_id = sign_id + 1
        end

        for offset = changed_count, new_count - 1 do
          vim.fn.sign_place(sign_id, git_sign_group, "GitAddedLine", buffer, {
            lnum = new_start + offset,
            priority = 10,
          })
          sign_id = sign_id + 1
        end
      end
    end
  end
end

vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "FocusGained" }, {
  callback = function(event)
    mark_git_changed_lines(event.buf)
  end,
})

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

local function normalize_git_path(path)
  path = path:gsub("/$", "")

  if path == "." then
    return ""
  end

  return path
end

local function add_git_status_path(statuses, path, status)
  path = normalize_git_path(path)

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
  local output = git_output(root, { "status", "--porcelain=v1" })
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

  return normalize_git_path(relative_path(root, directory .. "/" .. name))
end

local function mark_netrw_git_status(buffer)
  vim.api.nvim_buf_clear_namespace(buffer, netrw_git_namespace, 0, -1)

  local directory = netrw_current_dir(buffer)
  local root_output = git_output(directory, { "rev-parse", "--show-toplevel" })

  if not root_output or not root_output[1] then
    return
  end

  local root = root_output[1]
  local statuses = git_status_map(root)
  local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)

  for index, line in ipairs(lines) do
    local path = netrw_line_path(root, directory, line)
    local status = path and statuses[path]

    if status then
      vim.api.nvim_buf_set_extmark(buffer, netrw_git_namespace, index - 1, 0, {
        line_hl_group = status == "staged" and "NetrwGitStaged" or "NetrwGitUnstaged",
      })
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

local function open_file_from_netrw_search()
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

        table.insert(display, relative_path(root, matches[index]))
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

local function refresh_netrw_git_status()
  for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buffer) and vim.bo[buffer].filetype == "netrw" then
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buffer) and vim.bo[buffer].filetype == "netrw" then
          mark_netrw_git_status(buffer)
        end
      end)
    end
  end
end

vim.api.nvim_create_autocmd("FileType", {
  pattern = "netrw",
  callback = function(event)
    vim.keymap.set("n", "/", open_file_from_netrw_search, {
      buffer = event.buf,
      desc = "Find file by name",
      silent = true,
    })
    vim.defer_fn(function()
      if vim.api.nvim_buf_is_valid(event.buf) then
        mark_netrw_git_status(event.buf)
      end
    end, 50)
  end,
})

vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "FocusGained" }, {
  callback = refresh_netrw_git_status,
})

local function toggle_file_explorer()
  for _, window in ipairs(vim.api.nvim_list_wins()) do
    local buffer = vim.api.nvim_win_get_buf(window)

    if vim.bo[buffer].filetype == "netrw" then
      if #vim.api.nvim_list_wins() > 1 then
        vim.api.nvim_win_close(window, true)
      else
        vim.api.nvim_buf_delete(buffer, { force = true })
      end

      return
    end
  end

  vim.cmd.Lexplore()
end

vim.keymap.set("n", "<leader>e", toggle_file_explorer, {
  desc = "Toggle file explorer",
  silent = true,
})

local function git_add_current_file()
  local file_path = vim.api.nvim_buf_get_name(0)

  if file_path == "" or vim.fn.filereadable(file_path) ~= 1 then
    vim.notify("Current buffer is not a file", vim.log.levels.WARN)
    return
  end

  local file_dir = vim.fs.dirname(file_path)
  local root_output = git_output(file_dir, { "rev-parse", "--show-toplevel" })

  if not root_output or not root_output[1] then
    vim.notify("Current file is not inside a git repo", vim.log.levels.WARN)
    return
  end

  local root = root_output[1]
  local relative_file = relative_path(root, file_path)
  local output = git_output(root, { "add", "--", relative_file })

  if not output then
    vim.notify("git add failed: " .. relative_file, vim.log.levels.ERROR)
    return
  end

  mark_git_changed_lines(vim.api.nvim_get_current_buf())
  refresh_netrw_git_status()
  vim.notify("git add: " .. relative_file, vim.log.levels.INFO)
end

vim.keymap.set("n", "<leader>ga", git_add_current_file, {
  desc = "Git add current file",
  silent = true,
})

vim.keymap.set("n", "<leader>w", function()
  if vim.fn.tabpagenr("$") > 1 then
    vim.cmd.tabclose()
  else
    vim.cmd.bdelete()
  end
end, {
  desc = "Close tab",
  silent = true,
})

vim.keymap.set("n", "<leader>bn", "<Cmd>bnext<CR>", {
  desc = "Next buffer",
  silent = true,
})

vim.keymap.set("n", "<leader>bp", "<Cmd>bprevious<CR>", {
  desc = "Previous buffer",
  silent = true,
})

vim.keymap.set("n", "<leader>bb", "<Cmd>buffers<CR>", {
  desc = "List buffers",
  silent = true,
})

vim.keymap.set("n", "<leader>bd", "<Cmd>bdelete<CR>", {
  desc = "Delete buffer",
  silent = true,
})

for buffer_number = 1, 9 do
  vim.keymap.set("n", "<leader>b" .. buffer_number, "<Cmd>buffer " .. buffer_number .. "<CR>", {
    desc = "Go to buffer " .. buffer_number,
    silent = true,
  })
end

vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(event)
    local client = vim.lsp.get_client_by_id(event.data.client_id)
    if client and client:supports_method("textDocument/completion") then
      vim.lsp.completion.enable(true, client.id, event.buf, {
        autotrigger = true,
      })
    end

    local map = function(mode, lhs, rhs, desc)
      vim.keymap.set(mode, lhs, rhs, {
        buffer = event.buf,
        desc = desc,
        silent = true,
      })
    end

    map("n", "K", vim.lsp.buf.hover, "LSP hover")
    map("n", "gd", vim.lsp.buf.definition, "Go to definition")
    map("n", "<leader>ca", vim.lsp.buf.code_action, "Code action")
    map("n", "<leader>rn", vim.lsp.buf.rename, "Rename symbol")
    map("n", "<leader>f", function()
      vim.lsp.buf.format({ async = true })
    end, "Format buffer")
    map("n", "[d", vim.diagnostic.goto_prev, "Previous diagnostic")
    map("n", "]d", vim.diagnostic.goto_next, "Next diagnostic")
  end,
})

vim.keymap.set("i", "<C-Space>", function()
  vim.lsp.completion.get()
end, {
  desc = "Trigger LSP completion",
  silent = true,
})

local function enable_lsp(name, config)
  if vim.fn.executable(config.cmd[1]) ~= 1 then
    return
  end

  vim.lsp.config[name] = config
  vim.lsp.enable(name)
end

enable_lsp("ts_ls", {
  cmd = { "typescript-language-server", "--stdio" },
  filetypes = {
    "javascript",
    "javascriptreact",
    "typescript",
    "typescriptreact",
  },
  root_markers = { "package.json", "tsconfig.json", "jsconfig.json", ".git" },
})

enable_lsp("json_ls", {
  cmd = { "vscode-json-language-server", "--stdio" },
  filetypes = { "json", "jsonc" },
  root_markers = { "package.json", ".git" },
})

enable_lsp("gopls", {
  cmd = { "gopls" },
  filetypes = { "go", "gomod", "gowork", "gotmpl" },
  root_markers = { "go.work", "go.mod", ".git" },
})

enable_lsp("clangd", {
  cmd = { "clangd" },
  filetypes = { "c", "cpp", "objc", "objcpp", "cuda" },
  root_markers = { "compile_commands.json", "compile_flags.txt", ".git" },
})
