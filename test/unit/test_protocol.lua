local F = require("fixtures")
local T = require("harness")
local Protocol = require("color-rex.terminal.protocol")

T.test("protocol: one reply carries a whole theme", function()
  local event = Protocol.parse(F.reply(F.theme()))
  T.eq(event.kind, "theme")
  T.eq(event.theme.fg, "#d8dee9")
  T.eq(event.theme.bg, "#1b1f27")
  T.eq(event.theme.cursor, "#ff4fd8")
  T.eq(event.theme.ansi[0], "#2e3440")
  T.eq(event.theme.ansi[15], "#eceff4")
end)

T.test("protocol: a color the terminal lacks comes back empty, and stays absent", function()
  -- The exact reply of a Rex block that has no theme yet.
  local event = Protocol.parse("\027]21;foreground=;background=;cursor=;0=rgb:1d/1f/21;1=rgb:cc/66/66")
  T.eq(event.theme.fg, nil)
  T.eq(event.theme.bg, nil)
  T.eq(event.theme.ansi[1], "#cc6666")
end)

T.test("protocol: a real full reply fits, at 320 bytes", function()
  T.ok(#F.reply(F.theme()) < 512)
  T.ok(Protocol.parse(F.reply(F.theme())))
end)

T.test("protocol: keys it does not know are skipped", function()
  local event = Protocol.parse("\027]21;selection_background=rgb:11/22/33;16=rgb:11/22/33;0=rgb:ff/00/00")
  T.eq(event.theme.selection_background, nil)
  T.eq(event.theme.ansi[16], nil)
  T.eq(event.theme.ansi[0], "#ff0000")
end)

T.test("protocol: an OSC 11 reply means the terminal reported a change", function()
  T.eq(Protocol.parse("\027]11;rgb:0d0d/1111/1717").kind, "changed")
  T.eq(Protocol.parse("\027]11;rgb:0d/11/17").kind, "changed")
end)

T.test("protocol: we never ask for OSC 11, which is what makes that reply a signal", function()
  T.ok(not Protocol.request():find("]11;", 1, true))
end)

T.test("protocol: color forms OSC 21 never sends are skipped", function()
  local event = Protocol.parse("\027]21;0=#0d1117;1=rgba:0d/11/17/ff;2=rgb:f/0/f;3=rgb:0d0d/1111/1717;4=rgb:AA/bb/CC")
  for slot = 0, 3 do
    T.eq(event.theme.ansi[slot], nil, "slot " .. slot)
  end
  T.eq(event.theme.ansi[4], "#aabbcc")
end)

T.test("protocol: one request asks all 19 colors", function()
  local request = Protocol.request()
  T.eq(select(2, request:gsub("=%?", "")), 19)
  T.ok(request:sub(1, 5) == "\027]21;")
  T.ok(request:sub(-2) == "\027\\", "ST-terminated, as the terminal echoes it")
end)
