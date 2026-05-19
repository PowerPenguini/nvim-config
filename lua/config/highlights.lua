vim.api.nvim_set_hl(0, "StatusLineMode", { fg = "#2e3440", bg = "#a3be8c", bold = true })
vim.api.nvim_set_hl(0, "StatusLineFile", { fg = "#d8dee9", bg = "#4c566a" })
vim.api.nvim_set_hl(0, "StatusLineInfo", { fg = "#d8dee9", bg = "#3b4252" })
vim.api.nvim_set_hl(0, "StatusLineMuted", { fg = "#d8dee9", bg = "#4c566a" })
vim.api.nvim_set_hl(0, "WinSeparator", { fg = "#3b4252", bg = "#2e3440" })
vim.api.nvim_set_hl(0, "VertSplit", { fg = "#3b4252", bg = "#2e3440" })
vim.api.nvim_set_hl(0, "NetrwNormal", { fg = "#d8dee9", bg = "#242933" })
vim.api.nvim_set_hl(0, "NetrwCursorLine", { bg = "#3b4252" })
vim.api.nvim_set_hl(0, "NetrwEndOfBuffer", { fg = "#242933", bg = "#242933" })
vim.api.nvim_set_hl(0, "NetrwLineNr", { fg = "#4c566a", bg = "#242933" })
vim.api.nvim_set_hl(0, "NetrwNonText", { fg = "#4c566a", bg = "#242933" })
vim.api.nvim_set_hl(0, "NetrwSignColumn", { bg = "#242933" })
vim.api.nvim_set_hl(0, "DiagnosticFloatNormal", { fg = "#d8dee9", bg = "#242933" })
vim.api.nvim_set_hl(0, "DiagnosticFloatBorder", { fg = "#4c566a", bg = "#242933" })
vim.api.nvim_set_hl(0, "GitAddedLine", { fg = "#a3be8c" })
vim.api.nvim_set_hl(0, "GitModifiedLine", { fg = "#ebcb8b" })
vim.api.nvim_set_hl(0, "GitDeletedLine", { fg = "#bf616a" })
vim.api.nvim_set_hl(0, "GitUntrackedFile", { fg = "#b48ead", bold = true })
vim.api.nvim_set_hl(0, "GitStagedFile", { fg = "#88c0d0", bold = true })
vim.api.nvim_set_hl(0, "DiffTreePipe", { fg = "#4c566a" })
vim.api.nvim_set_hl(0, "DiffAdd", { bg = "NONE", underline = false, undercurl = false })
vim.api.nvim_set_hl(0, "DiffChange", { bg = "NONE", underline = false, undercurl = false })
vim.api.nvim_set_hl(0, "DiffDelete", { fg = "#bf616a", bg = "NONE", underline = false, undercurl = false })
vim.api.nvim_set_hl(0, "DiffText", {
  fg = "#eceff4",
  bg = "#5e4f2f",
  bold = true,
  underline = false,
  undercurl = false,
  underdashed = false,
  underdotted = false,
  underdouble = false,
})
vim.api.nvim_set_hl(0, "DiffCursorLine", {
  bg = "#3b4252",
  nocombine = true,
  underline = false,
  undercurl = false,
  underdashed = false,
  underdotted = false,
  underdouble = false,
})
vim.api.nvim_set_hl(0, "DiffCursor", { fg = "#eceff4", bg = "#3b4252" })
vim.api.nvim_set_hl(0, "FilePickerNormal", { fg = "#d8dee9", bg = "#242933" })
vim.api.nvim_set_hl(0, "FilePickerBorder", { fg = "#4c566a", bg = "#242933" })
vim.api.nvim_set_hl(0, "FilePickerSelected", { bg = "#3b4252", fg = "#eceff4", bold = true })
vim.api.nvim_set_hl(0, "NetrwGitUnstaged", { fg = "#ebcb8b", bold = true })
vim.api.nvim_set_hl(0, "NetrwGitStaged", { fg = "#a3be8c", bold = true })

vim.fn.sign_define("GitAddedLine", { text = "▌", texthl = "GitAddedLine", numhl = "GitAddedLine" })
vim.fn.sign_define("GitModifiedLine", { text = "▌", texthl = "GitModifiedLine", numhl = "GitModifiedLine" })
vim.fn.sign_define("GitDeletedLine", { text = "▌", texthl = "GitDeletedLine", numhl = "GitDeletedLine" })
