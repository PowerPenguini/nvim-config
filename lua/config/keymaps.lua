local M = {}

function M.setup(actions)
  vim.keymap.set("n", "<leader>e", function()
    if actions.toggle_diff_tree and actions.toggle_diff_tree() then
      return
    end

    actions.toggle_file_explorer()
  end, {
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

  vim.keymap.set("n", "<leader><leader>", function()
    local _, window = vim.diagnostic.open_float({
      prefix = "  ",
      suffix = "  ",
      header = "  Diagnostics: ",
      max_width = math.max(40, vim.o.columns - 8),
    })
    if window and vim.api.nvim_win_is_valid(window) then
      local buffer = vim.api.nvim_win_get_buf(window)
      vim.bo[buffer].modifiable = true
      vim.api.nvim_buf_set_lines(buffer, 0, 0, false, { "" })
      vim.api.nvim_buf_set_lines(buffer, -1, -1, false, { "" })
      vim.bo[buffer].modifiable = false
      local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
      vim.wo[window].wrap = true
      vim.wo[window].linebreak = true
      vim.wo[window].breakindent = false
      vim.wo[window].showbreak = "  "
      local height = vim.api.nvim_win_text_height(window, {
        start_row = 0,
        end_row = #lines - 1,
      }).all
      local max_height = math.max(1, vim.o.lines - 6)
      vim.api.nvim_win_set_height(window, math.min(height, max_height))
      vim.wo[window].winhighlight =
        "Normal:DiagnosticFloatNormal,NormalFloat:DiagnosticFloatNormal,FloatBorder:DiagnosticFloatBorder"
    end
  end, {
    desc = "Show diagnostic",
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
