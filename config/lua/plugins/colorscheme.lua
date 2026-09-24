-- Reads the palette from config.theme-colors (a symlink theme-set.sh repoints)
-- and applies it through catppuccin's color_overrides.
local function apply_theme()
  -- Drop the cached module so a repointed symlink is re-read.
  package.loaded["config.theme-colors"] = nil
  local ok, theme = pcall(require, "config.theme-colors")
  local flavour = "mocha"
  local overrides = {}

  if ok and theme.palette then
    flavour = theme.mode == "light" and "latte" or "mocha"
    overrides[flavour] = theme.palette
  end

  vim.o.background = flavour == "latte" and "light" or "dark"

  require("catppuccin").setup({
    flavour = flavour,
    color_overrides = overrides,
    integrations = {
      neotree = true,
      which_key = true,
      gitsigns = true,
    },
  })

  vim.cmd.colorscheme("catppuccin")
end

return {
  "catppuccin/nvim",
  name = "catppuccin",
  lazy = false,
  priority = 1000,
  config = function()
    apply_theme()

    -- theme-set.sh sends SIGUSR1 to every nvim after switching themes (same
    -- as kitty), so open editors recolour in place.
    vim.api.nvim_create_autocmd("Signal", {
      pattern = "SIGUSR1",
      callback = function()
        vim.schedule(function()
          apply_theme()
          vim.cmd.redraw({ bang = true })
        end)
      end,
    })
  end,
}
