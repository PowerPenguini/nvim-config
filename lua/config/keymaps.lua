local M = {}

function M.setup(actions)
  vim.keymap.set("n", "<leader>e", actions.toggle_file_explorer, {
    desc = "Toggle file explorer",
    silent = true,
  })

  vim.keymap.set("n", "<leader>ga", actions.git_add_current_file, {
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

  vim.keymap.set("i", "<C-Space>", function()
    vim.lsp.completion.get()
  end, {
    desc = "Trigger LSP completion",
    silent = true,
  })
end

return M
