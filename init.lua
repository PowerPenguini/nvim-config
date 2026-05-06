vim.g.mapleader = " "

vim.opt.number = true
vim.opt.relativenumber = true

vim.cmd.colorscheme("nord")

vim.keymap.set("n", "<leader>e", "<Cmd>Lexplore<CR>", {
  desc = "Toggle file explorer",
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
