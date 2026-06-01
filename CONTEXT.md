# Neovim Config Context

## Glossary

**AI Agent Popup** — a floating terminal overlay toggled by `<C-S-L>` (Cmd+Shift+L in Ghostty) that hosts persistent AI agent sessions. Behaves like the lazygit popup: same key opens and closes, the underlying processes keep running when the popup is hidden.

**Agent tab** — one of the named slots in the AI Agent Popup, each corresponding to a specific CLI agent (`claude` for claude-code, `pi` for pi-agent). Displayed as a tabline header inside the popup. Active tab is switched with `<C-k>` while inside the popup.

**Persistent terminal buffer** — a Neovim terminal buffer that outlives the popup window. The agent process is not killed when the popup closes; it resumes on next open. If the process has exited (crash or intentional `exit`), the buffer auto-restarts the agent the next time its tab is focused.

**Lazy agent init** — each agent process is started the first time its tab is focused in a session, not at Neovim startup. This avoids unnecessary process spawning in sessions where the popup is never used.
