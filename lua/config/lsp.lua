local util = require("config.util")

local function lstat(path)
  return vim.uv.fs_lstat(path)
end

local function repo_root()
  return util.git_root_for(vim.fn.getcwd()) or vim.fn.getcwd()
end

local function symlink_if_missing(source, target)
  if lstat(target) ~= nil then
    return
  end

  pcall(vim.uv.fs_symlink, source, target)
end

local function mirror_missing_go_files(source_dir, target_dir)
  local handle = vim.uv.fs_scandir(source_dir)

  if not handle then
    return
  end

  while true do
    local name = vim.uv.fs_scandir_next(handle)

    if not name then
      break
    end

    if name ~= ".git" then
      local source = source_dir .. "/" .. name
      local target = target_dir .. "/" .. name
      local source_stat = lstat(source)
      local target_stat = lstat(target)

      if source_stat then
        if target_stat == nil then
          symlink_if_missing(source, target)
        elseif source_stat.type == "directory" and target_stat.type == "directory" then
          mirror_missing_go_files(source, target)
        end
      end
    end
  end
end

local function ensure_git_difftool_go_module_links(path)
  local root, side, module = path:match("^(/tmp/git%-difftool%.[^/]+)/([^/]+)/([^/]+)/")
  if not root or (side ~= "left" and side ~= "right") then
    return
  end

  local source_dir = repo_root() .. "/" .. module
  local target_dir = root .. "/" .. side .. "/" .. module

  if lstat(source_dir) == nil or lstat(target_dir) == nil then
    return
  end

  mirror_missing_go_files(source_dir, target_dir)
end

local function is_left_git_difftool_path(path)
  local _, side = path:match("^(/tmp/git%-difftool%.[^/]+)/([^/]+)/")
  return side == "left"
end

local function set_buffer_diagnostics_enabled(buffer, enabled)
  if vim.diagnostic.enable then
    local ok = pcall(vim.diagnostic.enable, enabled, { bufnr = buffer })

    if ok then
      return
    end
  end

  if enabled and vim.diagnostic.enable then
    pcall(vim.diagnostic.enable, buffer)
  elseif not enabled and vim.diagnostic.disable then
    pcall(vim.diagnostic.disable, buffer)
  end
end

local function update_diff_buffer_diagnostics(buffer, path)
  path = path or vim.api.nvim_buf_get_name(buffer)

  local is_left_diff_buffer = vim.b[buffer].dirdiff_side == "left" or is_left_git_difftool_path(path)

  if is_left_diff_buffer then
    vim.diagnostic.reset(nil, buffer)
    set_buffer_diagnostics_enabled(buffer, false)
    vim.b[buffer].diagnostics_disabled_for_left_diff = true
    return
  end

  if vim.b[buffer].diagnostics_disabled_for_left_diff then
    set_buffer_diagnostics_enabled(buffer, true)
    vim.b[buffer].diagnostics_disabled_for_left_diff = false
  end
end

for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
  local path = vim.api.nvim_buf_get_name(buffer)
  ensure_git_difftool_go_module_links(path)
  update_diff_buffer_diagnostics(buffer, path)
end

vim.api.nvim_create_autocmd({ "BufReadPre", "BufNewFile" }, {
  callback = function(event)
    ensure_git_difftool_go_module_links(event.file)
  end,
})

vim.api.nvim_create_autocmd({ "BufReadPost", "BufEnter" }, {
  callback = function(event)
    update_diff_buffer_diagnostics(event.buf, event.file)
  end,
})

vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(event)
    update_diff_buffer_diagnostics(event.buf)

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
    local format_buffer = function()
      vim.lsp.buf.format({ async = true })
    end
    map("n", "<leader>cf", format_buffer, "Format buffer")
    map("n", "<leader>f", format_buffer, "Format buffer")
    map("n", "[d", vim.diagnostic.goto_prev, "Previous diagnostic")
    map("n", "]d", vim.diagnostic.goto_next, "Next diagnostic")
  end,
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
