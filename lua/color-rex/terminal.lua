-- Asks the terminal for its colors, as a small state machine.
--
--   idle --query--> querying --reply or timeout--> idle
--
-- Everything outside the machine is injected (send, after), so the suite can
-- drive every ordering and failure with no terminal and no real clock.
local Protocol = require("color-rex.terminal.protocol")

local M = {}

M.TIMEOUT_MS = 500 -- stop waiting; a reply that comes later still applies

--- opts: send(text), after(ms, fn) -> cancel, on_settle(theme, outcome),
--- on_change(): the terminal said its theme changed.
function M.new(opts)
  local self = {}
  local phase, cancel, rerun = "idle", nil, false

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
      -- Something asked for fresher colors while this query was in flight, so
      -- this answer is already out of date: replace it, do not publish it.
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
      return false
    end
    if phase == "querying" then
      rerun = true
      return false
    end
    phase, rerun = "querying", false
    cancel = opts.after(M.TIMEOUT_MS, function()
      cancel = nil
      if phase == "querying" then
        settle({ ansi = {} }, "timeout")
      end
    end)
    local ok, err = pcall(opts.send, Protocol.request())
    if not ok then
      settle({ ansi = {} }, "send failed: " .. tostring(err))
      return false
    end
    return true
  end

  --- Feed one terminal reply. Anything unrecognized is ignored.
  function self.feed(sequence)
    local event = Protocol.parse(sequence)
    if not event or phase == "closed" then
      return
    end
    if event.kind == "theme" then
      -- Nothing else sends these, so one that arrives after the timeout is still
      -- the terminal's answer. On a slow link it is the only answer there is.
      if phase == "querying" then
        settle(event.theme, "reply")
      else
        opts.on_settle(event.theme, "late reply")
      end
    else
      opts.on_change() -- cannot loop: a query never causes one of these
    end
  end

  function self.close()
    cancel_timer()
    phase, rerun = "closed", false
  end

  function self.phase()
    return phase
  end

  return self
end

return M
