-- AI agents popup: tabs of claude / pi sessions, each in its own git worktree.
--
-- A session is (agent kind, directory). The directory is normally a worktree
-- made by `agent-worktree new` (~/.worktrees/<repo>/<task>, branch
-- agent/<task>); leaving the task name empty gives a read-only session on the
-- main checkout instead (agent-guard blocks edits there).
--
-- Every session runs in a detached tmux session tagged with @agent_* options,
-- so agents outlive nvim: reopening nvim in the same repo restores the tabs.
-- A session ends when its agent exits or when it is closed with <C-S-X>.
--
-- Keys (inside the popup)          Keys (normal mode)
--   <C-S-L>  hide popup              <C-S-L>     toggle popup
--   <C-k>    next tab                <leader>aa  pick session / worktree
--   <C-S-K>  previous tab            <leader>an  new session
--   <C-S-N>  new session
--   <C-S-X>  close session (stop / review / merge / discard)
--   <C-S-P>  pick session / worktree

local AGENTS = {
  { kind = "claude", cmd = "claude" },
  { kind = "pi",     cmd = "pi" },
}
local AGENT_CMD = {}
for _, a in ipairs(AGENTS) do AGENT_CMD[a.kind] = a.cmd end

local WORKTREES = vim.env.AGENT_WORKTREE_ROOT or (vim.env.HOME .. "/.worktrees")

local state = {
  win      = nil,
  prev_win = nil,
  sessions = {}, -- { kind, name, path, slug, tmux, buf }
  active   = 0,
  restored = false,
}

local M = {}

-- helpers --------------------------------------------------------------------

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "agents" })
end

-- Run tmux outside any enclosing tmux session (nvim may itself be in tmux).
local function tmux(args)
  local r = vim.system(vim.list_extend({ "env", "-u", "TMUX", "tmux" }, args), { text = true }):wait()
  return r.code == 0, vim.trim(r.stdout or ""), vim.trim(r.stderr or "")
end

local function tmux_alive(name)
  return (tmux({ "has-session", "-t", "=" .. name }))
end

-- Same as agent-worktree's slug: ~/dotfiles/nvim -> dotfiles-nvim
local function slug(path)
  local p = path:gsub("^" .. vim.pesc(vim.env.HOME) .. "/", ""):gsub("^/", "")
  return (p:gsub("/", "-"))
end

local function git_toplevel(dir)
  local r = vim.system({ "git", "-C", dir, "rev-parse", "--show-toplevel" }, { text = true }):wait()
  if r.code ~= 0 then return nil end
  return vim.trim(r.stdout)
end

-- The repo this nvim is "about": cwd's toplevel, or cwd itself.
local function nvim_root()
  local cwd = vim.fn.getcwd()
  return git_toplevel(cwd) or cwd
end

local function belongs_here(s)
  local root = slug(nvim_root())
  return s == root or vim.startswith(s, root .. "-")
end

local function is_worktree(s) return vim.startswith(s.path, WORKTREES .. "/") end

local function label(s)
  return s.kind .. ":" .. (is_worktree(s) and s.name or "main")
end

local function job_alive(buf)
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then return false end
  local job_id = vim.b[buf].terminal_job_id
  return job_id ~= nil and vim.fn.jobwait({ job_id }, 0)[1] == -1
end

local function popup_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

-- tmux sessions --------------------------------------------------------------

local function tmux_name(kind, path)
  local rel = is_worktree({ path = path })
      and path:sub(#WORKTREES + 2):gsub("/", "--")
      or (slug(path) .. "--main")
  return ("agent-" .. kind .. "-" .. rel):gsub("[^%w_-]", "-")
end

local function ensure_tmux(s)
  if tmux_alive(s.tmux) then return true end
  local ok, _, err = tmux({
    "new-session", "-d", "-s", s.tmux, "-c", s.path,
    "-e", "AGENT_WORKTREE=" .. (is_worktree(s) and s.path or ""),
    "-e", "AGENT_KIND=" .. s.kind,
    AGENT_CMD[s.kind],
  })
  if not ok then
    notify("tmux: " .. err, vim.log.levels.ERROR)
    return false
  end
  for k, v in pairs({ kind = s.kind, name = s.name, path = s.path, repo = s.slug }) do
    tmux({ "set-option", "-t", s.tmux, "@agent_" .. k, v })
  end
  -- the popup's winbar already shows the tabs
  tmux({ "set-option", "-t", s.tmux, "status", "off" })
  return true
end

-- rendering ------------------------------------------------------------------

local function update_winbar()
  if not popup_open() then return end
  local parts = {}
  for i, s in ipairs(state.sessions) do
    local hl = i == state.active and "%#TabLineSel#" or "%#TabLine#"
    table.insert(parts, hl .. " " .. i .. " " .. label(s) .. " ")
  end
  table.insert(parts, "%#TabLineFill#%=%#TabLine# C-S-N new · C-S-X close · C-S-P pick ")
  vim.wo[state.win].winbar = table.concat(parts, "")
end

local function index_of(s)
  for i, x in ipairs(state.sessions) do
    if x == s then return i end
  end
end

local remove_session -- forward decl

local function get_buf(s)
  if job_alive(s.buf) then return s.buf end
  if s.buf and vim.api.nvim_buf_is_valid(s.buf) then
    vim.api.nvim_buf_delete(s.buf, { force = true })
  end
  if not ensure_tmux(s) then return nil end
  local buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_call(buf, function()
    vim.fn.jobstart({ "env", "-u", "TMUX", "tmux", "attach-session", "-t", "=" .. s.tmux }, {
      term = true,
      cwd = s.path,
      on_exit = function()
        vim.schedule(function()
          -- Detached (tmux still running): keep the tab, reattach next time.
          -- Agent exited: the tab goes away; the worktree stays.
          if index_of(s) and not tmux_alive(s.tmux) then
            if not s.closing then
              notify(label(s) .. " exited" .. (is_worktree(s) and " (worktree kept)" or ""))
            end
            remove_session(s)
          end
        end)
      end,
    })
  end)
  vim.bo[buf].buflisted = false
  local function map(lhs, fn) vim.keymap.set("t", lhs, fn, { buffer = buf, silent = true }) end
  map("<C-S-L>", M.toggle)
  map("<C-k>", function() M.cycle(1) end)
  map("<C-S-K>", function() M.cycle(-1) end)
  map("<C-S-N>", M.new_session)
  map("<C-S-X>", M.close_session)
  map("<C-S-P>", M.pick)
  s.buf = buf
  return buf
end

local function open_window(buf)
  local width  = math.floor(vim.o.columns * 0.9)
  local height = math.floor(vim.o.lines * 0.85)
  state.prev_win = vim.api.nvim_get_current_win()
  state.win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width    = width,
    height   = height,
    row      = math.floor((vim.o.lines - height) / 2) - 1,
    col      = math.floor((vim.o.columns - width) / 2),
    style    = "minimal",
    border   = "rounded",
  })
end

local function show(i)
  local s = state.sessions[i]
  if not s then return end
  state.active = i
  local buf = get_buf(s)
  if not buf then return end
  if popup_open() then
    vim.api.nvim_win_set_buf(state.win, buf)
    vim.api.nvim_set_current_win(state.win)
  else
    open_window(buf)
  end
  update_winbar()
  vim.cmd("startinsert")
end

local function add_session(kind, name, path, repo_slug)
  local s = { kind = kind, name = name, path = path, slug = repo_slug }
  s.tmux = tmux_name(kind, path)
  for i, x in ipairs(state.sessions) do
    if x.tmux == s.tmux then return i end
  end
  table.insert(state.sessions, s)
  return #state.sessions
end

remove_session = function(s)
  local i = index_of(s)
  if not i then return end
  table.remove(state.sessions, i)
  if tmux_alive(s.tmux) then tmux({ "kill-session", "-t", "=" .. s.tmux }) end
  local buf = s.buf
  if #state.sessions == 0 then
    state.active = 0
    if popup_open() then vim.api.nvim_win_close(state.win, true) end
  else
    if state.active > i then state.active = state.active - 1 end
    state.active = math.min(math.max(state.active, 1), #state.sessions)
    if popup_open() and vim.api.nvim_win_get_buf(state.win) == buf then
      show(math.min(i, #state.sessions))
    else
      update_winbar()
    end
  end
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
end

-- Rebuild tabs from tmux sessions started by an earlier nvim in this repo.
local function restore()
  if state.restored then return end
  state.restored = true
  local ok, out = tmux({
    "list-sessions", "-F",
    "#{@agent_kind}\t#{@agent_name}\t#{@agent_path}\t#{@agent_repo}",
  })
  if not ok then return end
  for line in out:gmatch("[^\n]+") do
    local kind, name, path, repo = line:match("^(.-)\t(.-)\t(.-)\t(.*)$")
    if kind and AGENT_CMD[kind] and belongs_here(repo) then
      add_session(kind, name, path, repo)
    end
  end
  if #state.sessions > 0 and state.active == 0 then state.active = 1 end
end

-- Worktrees under ~/.worktrees for this repo and its submodules.
local function worktrees_here()
  local list = {}
  for _, repo_dir in ipairs(vim.fn.glob(WORKTREES .. "/*", false, true)) do
    local repo = vim.fn.fnamemodify(repo_dir, ":t")
    if belongs_here(repo) then
      for _, wt in ipairs(vim.fn.glob(repo_dir .. "/*", false, true)) do
        if vim.uv.fs_stat(wt .. "/.git") then
          table.insert(list, { path = wt, name = vim.fn.fnamemodify(wt, ":t"), repo = repo })
        end
      end
    end
  end
  return list
end

-- actions --------------------------------------------------------------------

function M.toggle()
  if popup_open() then
    vim.api.nvim_win_close(state.win, false)
    state.win = nil
    return
  end
  restore()
  if #state.sessions == 0 then return M.new_session() end
  show(math.max(state.active, 1))
end

function M.cycle(step)
  if #state.sessions == 0 then return end
  show((state.active - 1 + step) % #state.sessions + 1)
end

-- Directory the new session is "for": the file you were editing (so a
-- submodule file offers that submodule's repo), else nvim's cwd.
local function origin_dir()
  local win = popup_open() and state.prev_win or vim.api.nvim_get_current_win()
  if not (win and vim.api.nvim_win_is_valid(win)) then return vim.fn.getcwd() end
  local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
  if name ~= "" and vim.uv.fs_stat(name) then return vim.fn.fnamemodify(name, ":p:h") end
  return vim.fn.getcwd()
end

local function start(kind, name, path, repo)
  show(add_session(kind, name, path, repo))
end

function M.new_session()
  restore()
  if popup_open() then vim.cmd("stopinsert") end
  local root = nvim_root()
  local here = git_toplevel(origin_dir()) or root
  local repos = { here }
  if here ~= root then table.insert(repos, root) end

  vim.ui.select(AGENTS, {
    prompt = "Agent",
    format_item = function(a) return a.kind end,
  }, function(agent)
    if not agent then return end
    local function with_repo(repo_dir)
      vim.ui.input({
        prompt = agent.kind .. " in " .. slug(repo_dir) .. " — task name (empty: read-only on main): ",
      }, function(name)
        if name == nil then return end
        name = vim.trim(name)
        if name == "" then
          return start(agent.kind, "main", repo_dir, slug(repo_dir))
        end
        notify("creating worktree " .. name .. "…")
        vim.system({ "agent-worktree", "new", name, "--from", repo_dir }, { text = true }, function(r)
          vim.schedule(function()
            if r.code ~= 0 then
              return notify(vim.trim(r.stderr), vim.log.levels.ERROR)
            end
            local path = vim.trim(r.stdout):match("[^\n]*$")
            start(agent.kind, vim.fn.fnamemodify(path, ":t"), path, slug(repo_dir))
          end)
        end)
      end)
    end
    if #repos == 1 then return with_repo(repos[1]) end
    vim.ui.select(repos, {
      prompt = "Repo",
      format_item = function(r) return slug(r) .. (r == here and "  (current file)" or "") end,
    }, function(r) if r then with_repo(r) end end)
  end)
end

local function run_worktree_cmd(args, s, on_ok)
  notify(table.concat(args, " ") .. "…")
  vim.system(vim.list_extend({ "agent-worktree" }, args), { text = true }, function(r)
    vim.schedule(function()
      local msg = vim.trim((r.stderr or "") .. "\n" .. (r.stdout or ""))
      if r.code ~= 0 then
        if s then s.closing = nil end
        notify(msg, vim.log.levels.ERROR)
        if s then show(index_of(s) or 1) end
        return
      end
      notify(msg)
      if on_ok then on_ok() end
    end)
  end)
end

function M.close_session()
  local s = state.sessions[state.active]
  if not s then return end
  vim.cmd("stopinsert")
  local actions = { { id = "stop", text = "Stop agent" .. (is_worktree(s) and " (keep worktree)" or "") } }
  if is_worktree(s) then
    vim.list_extend(actions, {
      { id = "review",  text = "Review in lazygit" },
      { id = "merge",   text = "Merge into base branch & remove worktree" },
      { id = "discard", text = "Discard worktree and branch" },
    })
  end
  vim.ui.select(actions, {
    prompt = "Close " .. label(s),
    format_item = function(a) return a.text end,
  }, function(a)
    if not a then
      if popup_open() then vim.cmd("startinsert") end
      return
    end
    if a.id == "stop" then
      remove_session(s)
    elseif a.id == "review" then
      if popup_open() then vim.api.nvim_win_close(state.win, false) end
      Snacks.lazygit({ cwd = s.path })
    elseif a.id == "merge" then
      s.closing = true
      run_worktree_cmd({ "merge", s.path }, s, function() remove_session(s) end)
    elseif a.id == "discard" then
      vim.ui.select({ "No", "Yes, delete " .. s.path }, { prompt = "Discard uncommitted work too?" }, function(c)
        if c and c ~= "No" then
          s.closing = true
          remove_session(s)
          run_worktree_cmd({ "rm", "--force", s.path })
        end
      end)
    end
  end)
end

function M.pick()
  restore()
  if popup_open() then vim.cmd("stopinsert") end
  local items, open_paths = {}, {}
  for i, s in ipairs(state.sessions) do
    open_paths[s.path] = true
    table.insert(items, { text = string.format("● %-28s %s", label(s), s.path), session = i, file = s.path })
  end
  for _, wt in ipairs(worktrees_here()) do
    if not open_paths[wt.path] then
      table.insert(items, { text = string.format("○ %-28s %s", wt.repo .. "/" .. wt.name, wt.path), worktree = wt, file = wt.path })
    end
  end
  table.insert(items, { text = "+ new session", new = true })
  Snacks.picker.pick({
    title = "Agent sessions  (● running  ○ worktree without agent)",
    items = items,
    format = "text",
    layout = { preview = false },
    confirm = function(picker, item)
      picker:close()
      if not item then return end
      if item.new then return M.new_session() end
      if item.session then return show(item.session) end
      vim.ui.select(AGENTS, {
        prompt = "Start which agent in " .. item.worktree.name,
        format_item = function(a) return a.kind end,
      }, function(agent)
        if agent then start(agent.kind, item.worktree.name, item.worktree.path, item.worktree.repo) end
      end)
    end,
  })
end

-- wiring ---------------------------------------------------------------------

vim.api.nvim_create_autocmd("WinClosed", {
  callback = function(ev)
    if state.win and tonumber(ev.match) == state.win then state.win = nil end
  end,
})

vim.keymap.set("n", "<C-S-L>", M.toggle, { desc = "Toggle AI agents popup", silent = true })
vim.keymap.set("n", "<leader>aa", M.pick, { desc = "Agent sessions" })
vim.keymap.set("n", "<leader>an", M.new_session, { desc = "New agent session" })

return M
