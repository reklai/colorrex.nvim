-- Asks the terminal for its colors, as a small state machine.
--
--   idle --query--> querying --reply or timeout--> idle
--
-- Closing it from any state ends it for good.
--
-- The first query does not know what sits between Neovim and the terminal, so it
-- asks by both routes at once (see protocol.lua) and remembers the one that
-- answers. A whole OSC 21 reply settles at once; xterm replies are gathered until
-- the theme is complete. A route that goes silent is forgotten, so the next query
-- discovers again: a tmux session can be detached and attached somewhere else.
--
-- Everything outside the machine is injected (send, after), so the suite can drive
-- every ordering and failure with no terminal and no real clock.
local Protocol = require("colorrex.terminal.protocol")

local M = {}

M.TIMEOUT_MS = 500 -- stop waiting; a reply that comes later still applies

local BOTH = { kitty = true, xterm = true }
local ONLY = { kitty = { kitty = true }, xterm = { xterm = true } }

local function complete(theme)
  if not (theme.fg and theme.bg) then
    return false
  end
  for slot = 0, 15 do
    if not theme.ansi[slot] then
      return false
    end
  end
  return true
end

local function has_any(theme)
  return theme.fg or theme.bg or theme.cursor or next(theme.ansi) ~= nil
end

--- opts: send(text), after(ms, fn) -> cancel, on_settle(theme, outcome),
--- on_change(): the terminal said its theme changed, tmux: a tmux sits between.
function M.new(opts)
  local self = {}
  local phase, cancel, rerun = "idle", nil, false
  local route = nil -- "kitty" or "xterm" once one has answered
  local asked = nil -- the routes the query in flight used
  local gathered = nil -- the xterm replies so far

  local function cancel_timer()
    if cancel then
      cancel()
      cancel = nil
    end
  end

  local function settle(theme, outcome)
    cancel_timer()
    phase = "idle"
    if rerun then
      -- Something asked for fresher colors while this query was in flight, so this
      -- answer is already out of date: replace it, do not publish it.
      rerun = false
      self.query()
      return
    end
    opts.on_settle(theme, outcome)
  end

  --- Ask the terminal for its colors. A call during a query queues one rerun,
  --- however many calls arrive: focus events come in pairs.
  function self.query()
    if phase == "closed" then
      return
    end
    if phase == "querying" then
      rerun = true
      return
    end
    phase = "querying"
    asked = route and ONLY[route] or BOTH
    gathered = { ansi = {} }
    cancel = opts.after(M.TIMEOUT_MS, function()
      cancel = nil
      if has_any(gathered) then
        route = route or "xterm" -- it answered, short of a theme: tmux knows no fg or bg yet
        settle(gathered, "timeout")
      else
        route = nil -- nobody answered by this route, so discover again next time
        settle({ ansi = {} }, "timeout")
      end
    end)
    local ok, err = pcall(opts.send, Protocol.request(asked, opts.tmux))
    if not ok then
      settle({ ansi = {} }, "send failed: " .. tostring(err))
    end
  end

  local function on_theme(theme)
    route = "kitty"
    if phase == "querying" then
      settle(theme, "reply")
    else
      -- Nothing else sends these, so one that arrives after the timeout is still
      -- the terminal's answer. On a slow link it is the only answer there is.
      opts.on_settle(theme, "late reply")
    end
  end

  local function on_color(key, hex)
    local ours = phase == "querying" and asked.xterm
    if not ours then
      -- A background reply nobody here asked for: Neovim asked, after mode 2031.
      -- On the xterm route it may be our own reply arriving late instead, and we
      -- cannot tell the two apart, so it is ignored. A dark/light change still
      -- arrives there, as a change to 'background'.
      if key == "bg" and route ~= "xterm" then
        opts.on_change()
      end
      return
    end
    if type(key) == "number" then
      gathered.ansi[key] = hex
    else
      gathered[key] = hex
    end
    if complete(gathered) then
      route = route or "xterm"
      settle(gathered, "reply")
    end
  end

  --- Feed one terminal reply. Anything unrecognized is ignored.
  function self.feed(sequence)
    local event = Protocol.parse(sequence)
    if not event or phase == "closed" then
      return
    end
    if event.kind == "theme" then
      on_theme(event.theme)
    else
      on_color(event.key, event.hex)
    end
  end

  function self.close()
    cancel_timer()
    phase, rerun = "closed", false
  end

  function self.phase()
    return phase
  end

  --- How colors are reaching us: "kitty", "xterm", or nil while unknown.
  function self.route()
    return route
  end

  return self
end

return M
