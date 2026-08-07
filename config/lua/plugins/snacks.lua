local function git_repos(root)
  local repos = { root }
  local gitmodules = root .. "/.gitmodules"
  if vim.fn.filereadable(gitmodules) == 1 then
    local lines = vim.fn.systemlist(
      "git config --file " .. gitmodules .. " --get-regexp 'submodule\\..*\\.path'"
    )
    for _, line in ipairs(lines) do
      local subpath = line:match("%S+%s+(%S+)")
      if subpath then table.insert(repos, root .. "/" .. subpath) end
    end
  end
  return repos
end

-- Neovim spawns `lazygit` via execvp (no shell, no zsh alias), so the `lg`
-- wrapper that normally prunes recentrepos never runs. Do the same prune
-- here before opening lazygit, since every lazygit binary reads the same
-- state.yml regardless of how it was launched.
local function prune_lazygit_recents()
  local root = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null"):gsub("\n$", "")
  if root == "" then return end

  local repos = git_repos(root)
  local repos_json = vim.json.encode(repos)

  local state_file = vim.fn.expand("$HOME/.local/state/lazygit/state.yml")
  vim.fn.system({
    "yq", "-iy", ".recentrepos = " .. repos_json, state_file,
  })
end

return {
  "folke/snacks.nvim",
  priority = 1000,
  lazy = false,
  opts = {
    bigfile = { enabled = true },
    indent = { enabled = true },
    lazygit = { enabled = true },
    notifier = { enabled = true },
    picker = { enabled = true },
    statuscolumn = { enabled = true },
    terminal = { enabled = true },
  },
  keys = {
    -- Find
    { "<leader>ff", function() Snacks.picker.files() end, desc = "Find files" },
    { "<leader>fg", function() Snacks.picker.grep() end, desc = "Live grep" },
    { "<leader>fb", function() Snacks.picker.buffers() end, desc = "Buffers" },
    { "<leader>fr", function() Snacks.picker.recent() end, desc = "Recent files" },
    { "<leader>fh", function() Snacks.picker.help() end, desc = "Help pages" },
    { "<leader>/",  function() Snacks.picker.grep_buffers() end, desc = "Search open buffers" },
    -- Terminal
    { "<C-b>",  function() Snacks.terminal() end, desc = "Open terminal" },
    -- Git
    {
      "<leader>gg",
      function()
        prune_lazygit_recents()
        Snacks.lazygit()
      end,
      desc = "Lazygit",
    },
    { "<leader>gf", function() Snacks.lazygit.log_file() end, desc = "Git log (file)" },
    { "<leader>gl", function() Snacks.lazygit.log() end, desc = "Git log" },
    { "<leader>gc", function() Snacks.picker.git_log() end, desc = "Git commits" },
    {
      "<leader>gs",
      function()
        local root = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null"):gsub("\n$", "")
        if root == "" then
          Snacks.notify.warn("Not in a git repository")
          return
        end

        local repos = git_repos(root)

        local items = {}
        for _, repo in ipairs(repos) do
          local name = repo:match("([^/]+)$") or repo

          local status_lines = vim.fn.systemlist(
            "git -C " .. vim.fn.shellescape(repo) .. " status --porcelain 2>/dev/null"
          )
          local staged, dirty = false, false
          for _, line in ipairs(status_lines) do
            if line:sub(1, 1) ~= " " and line:sub(1, 1) ~= "?" then staged = true end
            if line:sub(2, 2) ~= " " then dirty = true end
          end

          local sync = vim.fn.system(
            "git -C " .. vim.fn.shellescape(repo) .. " rev-list --count --left-right @{upstream}...HEAD 2>/dev/null"
          ):gsub("\n$", "")
          local behind, ahead = sync:match("(%d+)%s+(%d+)")

          local ind = ""
          if staged then ind = ind .. "+" end
          if dirty then ind = ind .. "*" end
          if ahead and tonumber(ahead) > 0 then ind = ind .. "^" end
          if behind and tonumber(behind) > 0 then ind = ind .. "v" end

          local branch = vim.fn.system(
            "git -C " .. vim.fn.shellescape(repo) .. " branch --show-current 2>/dev/null"
          ):gsub("\n$", "")
          if branch == "" then branch = "(detached)" end

          table.insert(items, {
            text = string.format("%-20s %-6s %-20s %s", name, ind, branch, repo),
            repo = repo,
          })
        end

        Snacks.picker.pick({
          title = "Git Submodules",
          items = items,
          format = "text",
          preview = false,
          confirm = function(picker, item)
            picker:close()
            Snacks.lazygit({ cwd = item.repo })
          end,
        })
      end,
      desc = "Git submodules",
    },
  },
}
