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

vim.opt.statusline = table.concat({
  "%#StatusLineMode# %{v:lua.statusline_mode()} ",
  "%#StatusLineFile# %f%m%r ",
  "%=",
  "%#StatusLineInfo# %{&fileformat} | %{&fileencoding != '' ? &fileencoding : &encoding} | %{v:lua.statusline_filetype()} ",
  "%#StatusLineMuted# %p%% ",
  "%#StatusLineMuted# %l:%c ",
})
