local AGENTS = {
  { name = "claude-code", cmd = "claude" },
  { name = "pi-agent",    cmd = "pi" },
}

local state = {
  win    = nil,
  active = 1,
  bufs   = {},
  cwd    = vim.fn.getcwd(),
}

local M = {}

local function job_alive(buf)
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then return false end
  local job_id = vim.b[buf].terminal_job_id
  if not job_id then return false end
  return vim.fn.jobwait({ job_id }, 0)[1] == -1
end

local function get_or_spawn(idx)
  local buf = state.bufs[idx]
  if job_alive(buf) then return buf end
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
  buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_call(buf, function()
    vim.fn.termopen(AGENTS[idx].cmd, { cwd = state.cwd })
  end)
  vim.bo[buf].buflisted = false
  state.bufs[idx] = buf
  vim.keymap.set("t", "<C-k>", M.switch_tab, { buffer = buf, silent = true })
  vim.keymap.set("t", "<C-S-L>", M.toggle,     { buffer = buf, silent = true })
  return buf
end

local function update_winbar()
  if not (state.win and vim.api.nvim_win_is_valid(state.win)) then return end
  local parts = {}
  for i, agent in ipairs(AGENTS) do
    if i == state.active then
      table.insert(parts, "%#TabLineSel# " .. agent.name .. " ")
    else
      table.insert(parts, "%#TabLine# " .. agent.name .. " ")
    end
  end
  vim.wo[state.win].winbar = table.concat(parts, "")
end

function M.toggle()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, false)
    state.win = nil
    return
  end
  local width  = math.floor(vim.o.columns * 0.9)
  local height = math.floor(vim.o.lines * 0.85)
  local row    = math.floor((vim.o.lines - height) / 2) - 1
  local col    = math.floor((vim.o.columns - width) / 2)
  local buf    = get_or_spawn(state.active)
  state.win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width    = width,
    height   = height,
    row      = row,
    col      = col,
    style    = "minimal",
    border   = "rounded",
  })
  update_winbar()
  vim.cmd("startinsert")
end

function M.switch_tab()
  state.active = (state.active % #AGENTS) + 1
  if not (state.win and vim.api.nvim_win_is_valid(state.win)) then return end
  local buf = get_or_spawn(state.active)
  vim.api.nvim_win_set_buf(state.win, buf)
  update_winbar()
  vim.cmd("startinsert")
end

-- Clean up state.win when the window is closed by any means (e.g. :q, ZZ)
vim.api.nvim_create_autocmd("WinClosed", {
  callback = function(ev)
    if state.win and tonumber(ev.match) == state.win then
      state.win = nil
    end
  end,
})

vim.keymap.set("n", "<C-S-L>", M.toggle, { desc = "Toggle AI agents popup", silent = true })

return M
