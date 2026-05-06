# Neovim config

Personal Neovim configuration.

## Install

```sh
git clone --recurse-submodules https://github.com/PowerPenguini/nvim-config.git ~/.config/nvim
```

If the repository was cloned without submodules:

```sh
git submodule update --init --recursive
```

## Contents

- `init.lua` - core editor options and keymaps
- `after/plugin/set_title.lua` - enables terminal title updates for window matching
- `pack/plugins/start/nord.nvim` - Nord colorscheme as a git submodule
