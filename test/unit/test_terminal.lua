local F = require("fixtures")
local T = require("harness")
local Terminal = require("colorrex.terminal")

local Protocol = require("colorrex.terminal.protocol")

local function harness(tmux)
  local host = F.fake_host()
  local log = { settled = {}, changes = 0 }
  local terminal = Terminal.new({
    send = host.send,
    after = host.after,
    on_settle = function(theme, outcome)
      log.settled[#log.settled + 1] = { theme = theme, outcome = outcome }
    end,
    on_change = function() log.changes = log.changes + 1 end,
    tmux = tmux,
  })
  return terminal, host, log
end

local function feed_all(terminal, sequences)
  for _, sequence in ipairs(sequences) do
    terminal.feed(sequence)
  end
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
  terminal.feed(F.reply(F.theme())) -- the route is known: OSC 21 alone from here
  terminal.query()
  terminal.feed("\027]11;rgb:fa/fa/fa")
  T.eq(log.changes, 1)
  terminal.query() -- what App does on a change
  terminal.feed(F.reply(F.theme()))
  T.eq(#host.sent, 3, "the answer in flight is out of date, so it asks again")
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

-- Routes ---------------------------------------------------------------------------

T.test("terminal: the first query asks by both routes, and then only by the one that answered", function()
  local terminal, host = harness()
  terminal.query()
  T.eq(host.sent[1], Protocol.KITTY .. Protocol.XTERM)
  terminal.feed(F.reply(F.theme()))
  T.eq(terminal.route(), "kitty")
  terminal.query()
  T.eq(host.sent[2], Protocol.KITTY)
end)

T.test("terminal: in tmux with no passthrough, xterm replies make the theme", function()
  local terminal, host, log = harness(true)
  terminal.query()
  T.eq(host.sent[1], Protocol.KITTY_TMUX .. Protocol.XTERM)
  feed_all(terminal, F.xterm_replies(F.theme()))
  T.eq(#log.settled, 1, "complete without a cursor, which tmux never sends")
  T.eq(log.settled[1].outcome, "reply")
  T.eq(log.settled[1].theme.bg, "#1b1f27")
  T.eq(log.settled[1].theme.ansi[15], "#eceff4")
  T.eq(log.settled[1].theme.cursor, nil)
  T.eq(terminal.route(), "xterm")
  terminal.query()
  T.eq(host.sent[2], Protocol.XTERM, "and asks only that way from then on")
end)

T.test("terminal: in tmux with passthrough on, the wrapped reply wins", function()
  local terminal, _, log = harness(true)
  terminal.query()
  terminal.feed(F.reply(F.theme())) -- the terminal answers before the palette is forwarded
  feed_all(terminal, F.xterm_replies(F.theme()))
  T.eq(#log.settled, 1)
  T.eq(log.settled[1].theme.cursor, "#ff4fd8", "OSC 21 carries the cursor")
  T.eq(terminal.route(), "kitty")
end)

T.test("terminal: a background reply on the xterm route is never read as a change", function()
  -- Our own OSC 11 can arrive after a timeout, and an OSC 11 is in every query, so
  -- treating it as a change would query forever on a slow link.
  local terminal, host, log = harness(true)
  terminal.query()
  feed_all(terminal, F.xterm_replies(F.theme()))
  terminal.feed("\027]11;rgb:1b1b/1f1f/2727")
  T.eq(log.changes, 0)
  T.eq(#host.sent, 1)
end)

T.test("terminal: discovery in a direct terminal costs one spare query at most", function()
  -- Ghostty answers both routes; the OSC 11 that comes after the OSC 21 is read as a
  -- change once. The spare query asks OSC 21 alone, so nothing follows it.
  local terminal, host, log = harness()
  terminal.query()
  terminal.feed(F.reply(F.theme()))
  feed_all(terminal, F.xterm_replies(F.theme(), true))
  T.eq(log.changes, 1)
  terminal.query()
  terminal.feed(F.reply(F.theme()))
  T.eq(log.changes, 1)
  T.eq(host.sent[2], Protocol.KITTY)
end)

T.test("terminal: tmux that knows no fg or bg yet settles with the palette at the timeout", function()
  local terminal, host, log = harness(true)
  terminal.query()
  local replies = F.xterm_replies(F.theme())
  feed_all(terminal, { unpack(replies, 3) }) -- the palette, and no fg or bg
  T.eq(#log.settled, 0)
  host.advance(Terminal.TIMEOUT_MS)
  T.eq(log.settled[1].outcome, "timeout")
  T.eq(log.settled[1].theme.ansi[1], "#e06c75")
  T.eq(log.settled[1].theme.bg, nil)
end)

T.test("terminal: a route that goes silent is forgotten, so the next query discovers again", function()
  local terminal, host = harness(true)
  terminal.query()
  feed_all(terminal, F.xterm_replies(F.theme()))
  terminal.query()
  host.advance(Terminal.TIMEOUT_MS) -- detached, or attached somewhere that does not answer
  T.eq(terminal.route(), nil)
  terminal.query()
  T.eq(host.sent[3], Protocol.KITTY_TMUX .. Protocol.XTERM)
end)
