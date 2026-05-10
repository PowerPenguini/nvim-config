local M = {}

function M.relative_path(root, file_path)
  local prefix = root .. "/"

  if file_path:sub(1, #prefix) == prefix then
    return file_path:sub(#prefix + 1)
  end

  return file_path
end

function M.normalize_git_path(path)
  path = path:gsub("/$", "")

  if path == "." then
    return ""
  end

  return path
end

function M.git_output(cwd, args)
  local command = { "git", "-C", cwd }
  vim.list_extend(command, args)

  local output = vim.fn.systemlist(command)

  if vim.v.shell_error ~= 0 then
    return nil
  end

  return output
end

function M.git_root_for(path)
  local root_output = M.git_output(path, { "rev-parse", "--show-toplevel" })

  if not root_output or not root_output[1] then
    return nil
  end

  return root_output[1]
end

function M.current_buffer_directory()
  local file_path = vim.api.nvim_buf_get_name(0)

  if file_path ~= "" then
    if vim.fn.isdirectory(file_path) == 1 then
      return file_path
    end

    return vim.fs.dirname(file_path)
  end

  return vim.fn.getcwd()
end

return M
