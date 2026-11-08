-- :checkhealth colorrex
local Config = require("colorrex.config")

local M = {}

function M.check()
  local health = vim.health
  health.start(Config.NAME)

  if vim.fn.has("nvim-0.12") == 1 then
    health.ok(("Neovim %s (tested floor: 0.12)"):format(tostring(vim.version())))
  else
    health.error("Neovim 0.12 or newer is required (nvim_ui_send)")
    return
  end

  if vim.g.colors_name == Config.NAME then
    health.ok(("colorscheme %s is active"):format(Config.NAME))
  else
    health.warn(("the active colorscheme is %s"):format(tostring(vim.g.colors_name)),
      ("Run :colorscheme %s"):format(Config.NAME))
  end

  -- An answer to OSC 21 is the proof. TERM_PROGRAM only supports the diagnosis:
  -- over SSH it is forwarded only if the server's AcceptEnv allows it, so its
  -- absence says nothing about a terminal that has already answered.
  local status = require("colorrex").status()
  if status.tmux then
    -- tmux answers palette queries itself and forwards them, so it works with no
    -- setup. These settings only make it whole and quick.
    if status.route == "xterm" and not status.borrowed then
      health.info("tmux hides the cursor color, so a theme's cursor cannot lead its keywords here. "
        .. "To carry it, add to tmux.conf: set -g allow-passthrough on")
    end
    health.info("inside tmux, a theme change shows when you pause typing or switch focus. "
      .. "For focus changes to reach Neovim, add to tmux.conf: set -g focus-events on")
  end
  if status.source == "terminal" and status.completeness == "full" then
    health.ok(("the terminal answered with a complete theme, by %s"):format(status.route_text))
  elseif status.source == "cache" then
    health.warn("showing the last known theme, not a live one", "Run :ColorRex")
  else
    health.warn(("theme is %s from %s"):format(status.completeness, status.source), "Run :ColorRex")
    local terminal = vim.env.TERM_PROGRAM
    if status.tmux then
      health.info("tmux sits between Neovim and the terminal; run Neovim outside tmux to see if tmux is the cause")
    elseif terminal ~= "rex" and terminal ~= "ghostty" then
      health.info(("TERM_PROGRAM is %s; colorrex supports libghostty terminals, such as Ghostty and Rex"):format(
        tostring(terminal)))
    end
  end
end

return M
