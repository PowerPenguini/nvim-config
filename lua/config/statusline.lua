local mode_labels = {
  ["!"] = "SHELL",
  ["R"] = "REPLACE",
  ["Rv"] = "V-REPLACE",
  ["V"] = "V-LINE",
  ["\022"] = "V-BLOCK",
  ["c"] = "COMMAND",
  ["i"] = "INSERT",
  ["n"] = "NORMAL",
  ["no"] = "OP-PENDING",
  ["r"] = "PROMPT",
  ["s"] = "SELECT",
  ["t"] = "TERMINAL",
  ["v"] = "VISUAL",
}

function _G.statusline_mode()
  local mode = vim.api.nvim_get_mode().mode
  return mode_labels[mode] or mode:upper()
end

function _G.statusline_filetype()
  if vim.bo.filetype == "" then
    return "no ft"
  end

  return vim.bo.filetype
end

function _G.statusline_file()
  if vim.b.dirdiff_repo_path then
    return vim.b.dirdiff_repo_path
  end

  if vim.bo.filetype == "dirdiff" then
    return "directory diff"
  end

  local file_name = vim.fn.expand("%:~:.")

  if file_name == "" then
    return "[No Name]"
  end

  return file_name
end

vim.opt.statusline = table.concat({
  "%#StatusLineMode# %{v:lua.statusline_mode()} ",
  "%#StatusLineFile# %{v:lua.statusline_file()}%m%r ",
  "%=",
  "%#StatusLineInfo# %{&fileformat} | %{&fileencoding != '' ? &fileencoding : &encoding} | %{v:lua.statusline_filetype()} ",
  "%#StatusLineMuted# %p%% ",
  "%#StatusLineMuted# %l:%c ",
})
