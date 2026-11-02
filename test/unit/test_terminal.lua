local F = require("fixtures")
local T = require("harness")
local Terminal = require("colorrex.terminal")

local function harness()
  local host = F.fake_host()
  local log = { settled = {}, changes = 0 }
  local terminal = Terminal.new({
    send = host.send,
    after = host.after,
    on_settle = function(theme, outcome)
      log.settled[#log.settled + 1] = { theme = theme, outcome = outcome }
    end,
    on_change = function() log.changes = log.changes + 1 end,
  })
  return terminal, host, log
end

T.test("terminal: a reply settles at once, with no timer left running", function()
  local terminal, host, log = harness()
  terminal.query()
  terminal.feed(F.reply(F.theme()))
  T.eq(#log.settled, 1)
  T.eq(log.settled[1].outcome, "reply")
  T.eq(terminal.phase(), "idle")
  host.advance(Terminal.TIMEOUT_MS)
  T.eq(#log.settled, 1)
end)

T.test("terminal: an unthemed Rex block settles with what it has", function()
  local terminal, _, log = harness()
  terminal.query()
  terminal.feed(F.reply(F.theme({ fg = false, bg = false, cursor = false })))
  T.eq(log.settled[1].theme.fg, nil)
  T.eq(log.settled[1].theme.ansi[1], "#e06c75")
end)

T.test("terminal: a silent terminal settles at the timeout, with nothing", function()
  local terminal, host, log = harness()
  terminal.query()
  host.advance(Terminal.TIMEOUT_MS)
  T.eq(log.settled[1].outcome, "timeout")
end)

T.test("terminal: a reply after the timeout still counts", function()
  local terminal, host, log = harness()
  terminal.query()
  host.advance(Terminal.TIMEOUT_MS)
  terminal.feed(F.reply(F.theme()))
  T.eq(#log.settled, 2)
  T.eq(log.settled[2].outcome, "late reply")
end)

T.test("terminal: focus events in a pair run one rerun, not a pile", function()
  local terminal, host, log = harness()
  terminal.query()
  terminal.query()
  terminal.query()
  T.eq(#host.sent, 1)
  terminal.feed(F.reply(F.theme()))
  T.eq(#log.settled, 0, "the stale answer is dropped")
  T.eq(#host.sent, 2)
  terminal.feed(F.reply(F.theme()))
  T.eq(#log.settled, 1)
end)

T.test("terminal: an OSC 11 reply reports a change, even with the same background", function()
  -- Ghostty sends mode 2031 on every config reload. A new palette on the same
  -- background must still get through, so nothing here compares values.
  local terminal, _, log = harness()
  terminal.query()
  terminal.feed(F.reply(F.theme()))
  terminal.feed("\027]11;rgb:1b/1f/27")
  T.eq(log.changes, 1)
end)

T.test("terminal: a change reported during a query is not lost", function()
  local terminal, host, log = harness()
  terminal.query()
  terminal.feed("\027]11;rgb:fa/fa/fa")
  T.eq(log.changes, 1)
  terminal.query() -- what App does on a change
  terminal.feed(F.reply(F.theme()))
  T.eq(#host.sent, 2, "the answer in flight is out of date, so it asks again")
end)

T.test("terminal: answering a query reports no change, so it cannot loop", function()
  local terminal, host, log = harness()
  for _ = 1, 5 do
    terminal.query()
    terminal.feed(F.reply(F.theme()))
  end
  T.eq(log.changes, 0)
  T.eq(#host.sent, 5)
end)

T.test("terminal: nothing happens after close", function()
  local terminal, host, log = harness()
  terminal.query()
  terminal.close()
  host.advance(Terminal.TIMEOUT_MS)
  terminal.feed(F.reply(F.theme()))
  terminal.query()
  T.eq(#log.settled, 0)
  T.eq(#host.sent, 1)
end)

T.test("terminal: a failing send settles instead of wedging the machine", function()
  local log = {}
  local host = F.fake_host()
  local terminal = Terminal.new({
    send = function() error("no tty") end,
    after = host.after,
    on_settle = function(_, reason) log[#log + 1] = reason end,
    on_change = function() end,
  })
  terminal.query()
  T.ok(log[1]:match("send failed"))
  T.eq(terminal.phase(), "idle")
end)
