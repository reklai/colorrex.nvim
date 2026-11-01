-- The terminal's color protocol, as data: bytes in, events out.
--
-- A libghostty terminal answers one OSC 21 request with every color in a single
-- reply. That makes a read atomic: a theme can never change halfway through one.
-- A color with no value comes back empty, as in `foreground=`, so a missing color
-- is stated rather than implied.
--
-- OSC 21 is the kitty color protocol. Ghostty lists it as an external protocol
-- and treats any deviation from the spec as a bug, so this is a contract:
-- https://sw.kovidgoyal.net/kitty/color-stack/
-- https://ghostty.org/docs/vt/external
--
-- Neovim strips the terminator before we see a reply.
--
-- parse() never raises, whatever it is given. Anything can arrive on this
-- channel, so malformed input is not an error: it is simply not an event.
local M = {}

local MAX_REPLY = 512 -- a full reply is about 320 bytes

local SPECIAL = { foreground = "fg", background = "bg", cursor = "cursor" }

--- A color value as "#rrggbb", or nil. OSC 21 always sends two digits per channel.
local function color(text)
  local r, g, b = text:match("^rgb:(%x%x)/(%x%x)/(%x%x)$")
  return r and "#" .. (r .. g .. b):lower() or nil
end

local function parse_theme(body)
  local theme = { ansi = {} }
  for key, value in body:gmatch("([^;=]+)=([^;]*)") do
    local slot = tonumber(key)
    if SPECIAL[key] then
      theme[SPECIAL[key]] = color(value)
    elseif slot and slot >= 0 and slot <= 15 then
      theme.ansi[slot] = color(value)
    end
  end
  return theme
end

--- Turn one terminal reply into an event, or nil.
---   { kind = "theme", theme = {...} }  the answer to request()
---   { kind = "changed" }               the terminal says its theme changed
---
--- We never send OSC 11, so an OSC 11 reply can only be Neovim's. It asks when a
--- libghostty terminal sends mode 2031, and it consumes that report itself, so
--- this reply is the one trace of the report that reaches a plugin.
function M.parse(sequence)
  if type(sequence) ~= "string" or #sequence > MAX_REPLY then
    return nil
  end
  local body = sequence:match("^\027%]21;(.*)$")
  if body then
    return { kind = "theme", theme = parse_theme(body) }
  end
  if sequence:match("^\027%]11;") then
    return { kind = "changed" }
  end
  return nil
end

--- The request for every color a theme has that the terminal will report.
function M.request()
  local keys = { "foreground=?", "background=?", "cursor=?" }
  for slot = 0, 15 do
    keys[#keys + 1] = slot .. "=?"
  end
  return "\027]21;" .. table.concat(keys, ";") .. "\027\\"
end

return M
