# dotfiles-nvim

Neovim config built from scratch with [lazy.nvim](https://github.com/folke/lazy.nvim) — no starter distribution (see [ADR 0002](https://github.com/SaratAngajalaoffl/dotfiles-arch/blob/main/docs/adr/0002-from-scratch-neovim-config.md) in the parent repo).

Part of the [dotfiles-arch](https://github.com/SaratAngajalaoffl/dotfiles-arch) multi-repo dotfiles system.

## Layout

- `config` → `~/.config/nvim` (see `.links`)
- `config/lua/config/` — `options.lua`, `keymaps.lua`, `lazy.lua` (bootstrap)
- `config/lua/plugins/` — one file per plugin spec
- `config/lua/config/theme-colors.lua` is gitignored — it's a symlink to the active theme's palette, required by the `catppuccin/nvim` colorscheme plugin (falls back to a hardcoded flavour if absent); reopen Neovim after a theme switch to pick it up
- `CONTEXT.md` — additional project context/domain notes

## Plugin updates

`:Lazy update` inside Neovim. Lock file: `lazy-lock.json`.

## Setup

Otherwise applied entirely by the parent repo's `install.sh`.
