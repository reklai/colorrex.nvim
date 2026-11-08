-- The terminal's color protocols, as data: bytes in, events out.
--
-- These are the front end of the compiler. There are two routes to a terminal's
-- theme, and both produce the same Theme:
--
--   kitty  One OSC 21 request asks every color, and one reply carries them all. A
--          read is atomic: a theme can never change halfway through one. A color
--          with no value comes back empty, as in `foreground=`, so a missing color
--          is stated rather than implied. Every libghostty terminal answers it,
--          including a herdr pane, which runs libghostty-vt itself.
--          https://sw.kovidgoyal.net/kitty/color-stack/
--          https://ghostty.org/docs/vt/external
--
--   xterm  One OSC 10, 11, 12 and 4 per color, each answered on its own. tmux
--          drops OSC 21 unless allow-passthrough is on, but answers these itself:
--          it forwards OSC 4 to the terminal outside it every time, and keeps fg
--          and bg from what that terminal reported. It never answers OSC 12.
--
-- Inside tmux the kitty request is wrapped in tmux's passthrough DCS, which is the
-- only way an OSC 21 reaches the terminal outside it.
--
-- Neovim strips the terminator before we see a reply.
--
-- parse() never raises, whatever it is given. Anything can arrive on this channel,
-- so malformed input is not an error: it is simply not an event.
local M = {}

local MAX_REPLY = 512 -- a full OSC 21 reply is about 320 bytes

local SPECIAL = { foreground = "fg", background = "bg", cursor = "cursor" }
local XTERM_KEY = { ["10"] = "fg", ["11"] = "bg", ["12"] = "cursor" }

--- The OSC 21 request for every color a theme has that the terminal will report.
M.KITTY = (function()
  local keys = { "foreground=?", "background=?", "cursor=?" }
  for slot = 0, 15 do
    keys[#keys + 1] = slot .. "=?"
  end
  return "\027]21;" .. table.concat(keys, ";") .. "\027\\"
end)()

--- The same request in tmux's passthrough: every ESC inside is doubled.
M.KITTY_TMUX = "\027Ptmux;" .. M.KITTY:gsub("\027", "\027\027") .. "\027\\"

--- One question per color. The cursor goes first: a terminal answers in order, so
--- its reply is in before the palette completes, and tmux never sends one at all.
M.XTERM = (function()
  local parts = { "\027]12;?\027\\", "\027]10;?\027\\", "\027]11;?\027\\" }
  for slot = 0, 15 do
    parts[#parts + 1] = ("\027]4;%d;?\027\\"):format(slot)
  end
  return table.concat(parts)
end)()

--- The bytes for a query by these routes. `tmux` is whether a tmux sits between.
function M.request(routes, tmux)
  local parts = {}
  if routes.kitty then
    parts[#parts + 1] = tmux and M.KITTY_TMUX or M.KITTY
  end
  if routes.xterm then
    parts[#parts + 1] = M.XTERM
  end
  return table.concat(parts)
end

--- A color value as "#rrggbb", or nil. OSC 21 sends two digits per channel; the
--- xterm form allows one to four, which scale to the full range.
local function color(text)
  local r, g, b = text:match("^rgb:(%x+)/(%x+)/(%x+)$")
  if not r or #r > 4 or #r ~= #g or #g ~= #b then
    return nil
  end
  local max = 16 ^ #r - 1
  local function channel(digits)
    return ("%02x"):format(math.floor(tonumber(digits, 16) / max * 255 + 0.5))
  end
  return "#" .. channel(r) .. channel(g) .. channel(b)
end

--- OSC 21 always uses two digits; a reply in any other form is not one of ours.
local function kitty_color(text)
  return text:match("^rgb:%x%x/%x%x/%x%x$") and color(text:lower()) or nil
end

local function parse_theme(body)
  local theme = { ansi = {} }
  for key, value in body:gmatch("([^;=]+)=([^;]*)") do
    local slot = key:match("^%d%d?$") and tonumber(key)
    if SPECIAL[key] then
      theme[SPECIAL[key]] = kitty_color(value)
    elseif slot and slot <= 15 then
      theme.ansi[slot] = kitty_color(value)
    end
  end
  return theme
end

--- Turn one terminal reply into an event, or nil.
---   { kind = "theme", theme = {...} }      an OSC 21 reply: a whole theme at once
---   { kind = "color", key = k, hex = h }   one xterm reply; k is "fg", "bg",
---                                          "cursor" or a slot number 0 to 15
---
--- An OSC 11 reply is also how a plugin learns of a dark/light change: Neovim asks
--- when a terminal sends mode 2031, and consumes that report itself, so its reply
--- is the one trace that reaches us. Telling that apart from an answer to our own
--- question is the state machine's job, because only it knows what it asked.
function M.parse(sequence)
  if type(sequence) ~= "string" or #sequence > MAX_REPLY then
    return nil
  end
  local body = sequence:match("^\027%]21;(.*)$")
  if body then
    return { kind = "theme", theme = parse_theme(body) }
  end
  local number, value = sequence:match("^\027%](1[012]);(.*)$")
  if number then
    return { kind = "color", key = XTERM_KEY[number], hex = color(value:lower()) }
  end
  local slot
  slot, value = sequence:match("^\027%]4;(%d%d?);(.*)$")
  slot = tonumber(slot)
  if slot and slot <= 15 then
    local hex = color(value:lower())
    return hex and { kind = "color", key = slot, hex = hex } or nil
  end
  return nil
end

return M
