return {
  "nvim-neo-tree/neo-tree.nvim",
  branch = "v3.x",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-tree/nvim-web-devicons",
    "MunifTanjim/nui.nvim",
  },
  cmd = "Neotree",
  keys = {
    { "<leader>ee", "<cmd>Neotree toggle<cr>", desc = "Toggle explorer" },
    { "<leader>ef", "<cmd>Neotree reveal<cr>", desc = "Reveal current file" },
    { "<leader>eg", "<cmd>Neotree git_status<cr>", desc = "Git status" },
  },
  opts = {
    filesystem = {
      follow_current_file = { enabled = true },
      hijack_netrw_behavior = "open_current",
    },
  },
}
