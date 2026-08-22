return {
  "catppuccin/nvim",
  name = "catppuccin",
  lazy = false,
  priority = 1000,
  config = function()
    local ok, theme = pcall(require, "config.theme-colors")
    local flavour = "mocha"
    local overrides = {}

    if ok and theme.palette then
      flavour = theme.mode == "light" and "latte" or "mocha"
      overrides[flavour] = theme.palette
    end

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
  end,
}
