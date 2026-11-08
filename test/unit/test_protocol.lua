local F = require("fixtures")
local T = require("harness")
local Protocol = require("colorrex.terminal.protocol")

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

T.test("protocol: only a plain slot number is a slot", function()
  local event = Protocol.parse("\027]21;1e1=rgb:11/22/33;0x1=rgb:11/22/33;1.5=rgb:11/22/33;-1=rgb:11/22/33")
  T.eq(next(event.theme.ansi), nil)
end)

T.test("protocol: keys it does not know are skipped", function()
  local event = Protocol.parse("\027]21;selection_background=rgb:11/22/33;16=rgb:11/22/33;0=rgb:ff/00/00")
  T.eq(event.theme.selection_background, nil)
  T.eq(event.theme.ansi[16], nil)
  T.eq(event.theme.ansi[0], "#ff0000")
end)

T.test("protocol: color forms OSC 21 never sends are skipped", function()
  local event = Protocol.parse("\027]21;0=#0d1117;1=rgba:0d/11/17/ff;2=rgb:f/0/f;3=rgb:0d0d/1111/1717;4=rgb:AA/bb/CC")
  for slot = 0, 3 do
    T.eq(event.theme.ansi[slot], nil, "slot " .. slot)
  end
  T.eq(event.theme.ansi[4], "#aabbcc")
end)

T.test("protocol: one kitty request asks all 19 colors", function()
  local request = Protocol.KITTY
  T.eq(select(2, request:gsub("=%?", "")), 19)
  T.ok(request:sub(1, 5) == "\027]21;")
  T.ok(request:sub(-2) == "\027\\", "ST-terminated, as the terminal echoes it")
end)

T.test("protocol: the kitty route never asks OSC 11, so there its reply is a signal", function()
  T.ok(not Protocol.KITTY:find("]11;", 1, true))
  T.ok(not Protocol.request({ kitty = true }, true):find("]11;", 1, true))
end)

T.test("protocol: inside tmux the request goes out in tmux's passthrough", function()
  -- The bytes verified against tmux 3.8 with allow-passthrough on, and against Rex
  -- and Ghostty directly, which answer them too.
  T.eq(Protocol.KITTY_TMUX, "\027Ptmux;" .. Protocol.KITTY:gsub("\027", "\027\027") .. "\027\\")
  T.eq(Protocol.request({ kitty = true }, true), Protocol.KITTY_TMUX)
  T.eq(Protocol.request({ kitty = true }, false), Protocol.KITTY)
end)

T.test("protocol: the xterm route asks 19 colors, the cursor first", function()
  local request = Protocol.XTERM
  T.eq(select(2, request:gsub(";%?\027\\", "")), 19)
  T.eq(request:sub(1, 8), "\027]12;?\027\\")
  T.eq(Protocol.request({ kitty = true, xterm = true }, false), Protocol.KITTY .. Protocol.XTERM)
end)

T.test("protocol: xterm replies, in the forms tmux and terminals send", function()
  -- Exact replies seen from tmux 3.8 inside Ghostty and Rex.
  local cases = {
    { "\027]4;1;rgb:f3f3/8b8b/a8a8", 1, "#f38ba8" },
    { "\027]10;rgb:cdcd/d6d6/f4f4", "fg", "#cdd6f4" },
    { "\027]11;rgb:1e1e/1e1e/2e2e", "bg", "#1e1e2e" },
    { "\027]12;rgb:f5f5/e0e0/dcdc", "cursor", "#f5e0dc" },
    { "\027]4;15;rgb:ff/ff/ff", 15, "#ffffff" },
    { "\027]4;2;rgb:f/0/f", 2, "#ff00ff" },
    { "\027]4;3;rgb:FFF/000/888", 3, "#ff0088" },
  }
  for _, case in ipairs(cases) do
    local event = Protocol.parse(case[1])
    T.eq(event.kind, "color", case[1])
    T.eq(event.key, case[2], case[1])
    T.eq(event.hex, case[3], case[1])
  end
end)

T.test("protocol: an OSC 11 reply is a background, whatever its form", function()
  T.eq(Protocol.parse("\027]11;rgb:0d0d/1111/1717").key, "bg")
  T.eq(Protocol.parse("\027]11;rgb:0d/11/17").key, "bg")
  T.eq(Protocol.parse("\027]11;unexpected").key, "bg", "still a trace of mode 2031")
end)

T.test("protocol: xterm replies out of range or malformed are not events", function()
  for _, sequence in ipairs({
    "\027]4;16;rgb:ff/ff/ff", "\027]4;1;rgb:ff/ff", "\027]4;1;rgb:fffff/0/0", "\027]4;1;rgb:ff/f/ff", "\027]4;x;rgb:1/2/3",
  }) do
    T.eq(Protocol.parse(sequence), nil, sequence)
  end
end)
