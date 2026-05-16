vim.g.mapleader = " "

require("config.options")
require("config.highlights")
require("config.statusline")

local git = require("config.git")
local netrw = require("config.netrw")
local dirdiff = require("config.dirdiff")

netrw.setup()
git.setup(netrw.refresh_git_status)
dirdiff.setup()

require("config.keymaps").setup({
  git_add_current_file = git.add_current_file,
  toggle_diff_tree = dirdiff.toggle_tree,
  toggle_file_explorer = netrw.toggle_file_explorer,
})

require("config.lsp")
