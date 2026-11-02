-- The theme format: what a terminal or a file can say about colors.
--
-- A theme is { fg, bg, cursor, ansi = { [0..15] } }. Every color is "#rrggbb" in
-- lowercase, or absent: parse() and the terminal protocol both guarantee that, so
-- nothing past them validates a color. Only fill() promises a complete theme, so
-- the compiler never has to handle a gap.
--
-- Themes are read and written as Ghostty theme files. That is the format Rex
-- imports, the corpus the conformance suite runs on, and the cache on disk, which
-- is why the cache is plain text and never executed.
local Color = require("colorrex.color")

local M = {}

-- Deliberately grey. These appear only when a terminal has told us nothing, and a
-- failed query should look failed rather than like a plausible theme.
local NEUTRAL = {
  dark = {
    fg = "#c8c8c8", bg = "#1c1c1c", grey = "#a0a0a0",
    ramp = { [0] = "#3a3a3a", [7] = "#b0b0b0", [8] = "#6c6c6c", [15] = "#e4e4e4" },
  },
  light = {
    fg = "#303030", bg = "#f4f4f4", grey = "#606060",
    ramp = { [0] = "#d0d0d0", [7] = "#585858", [8] = "#8a8a8a", [15] = "#1c1c1c" },
  },
}

-- Ghostty's name for each field, in the order a theme file lists them.
local FIELDS = {
  { key = "bg", name = "background" },
  { key = "fg", name = "foreground" },
  { key = "cursor", name = "cursor-color" },
}

local FIELD_KEYS = {}
for _, field in ipairs(FIELDS) do
  FIELD_KEYS[field.name] = field.key
end

--- How much of a theme is present.
---   "full"    foreground, background and all 16 ANSI colors
---   "partial" some of those
---   "none"    nothing usable
function M.completeness(theme)
  local count = 0
  for slot = 0, 15 do
    if theme.ansi[slot] then
      count = count + 1
    end
  end
  if theme.fg and theme.bg and count == 16 then
    return "full"
  end
  if count == 0 and not theme.fg and not theme.bg then
    return "none"
  end
  return "partial"
end

--- A complete copy of a theme, with neutral colors in every gap, plus the
--- `background` it needs. The cursor stays optional: a theme without its own simply
--- has no accent to offer. `background` ("dark" or "light") picks the neutral set
--- when the theme has no bg to judge by.
function M.fill(theme, background)
  local name = background == "light" and "light" or "dark"
  if theme.bg then
    name = Color.is_dark(theme.bg) and "dark" or "light"
  end
  local neutral = NEUTRAL[name]
  local filled = {
    fg = theme.fg or neutral.fg,
    bg = theme.bg or neutral.bg,
    cursor = theme.cursor,
    background = name,
    ansi = {},
  }
  for slot = 0, 15 do
    filled.ansi[slot] = theme.ansi[slot] or neutral.ramp[slot] or neutral.grey
  end
  return filled
end

--- A stable identity for a filled theme. Different signatures may render the same,
--- but equal signatures always do, so this is what decides a repaint.
function M.signature(filled)
  local parts = { filled.fg, filled.bg, filled.cursor or "-" }
  for slot = 0, 15 do
    parts[#parts + 1] = filled.ansi[slot]
  end
  return table.concat(parts, ",")
end

local function hex(value)
  local digits = value:match("^#?(%x%x%x%x%x%x)$")
  return digits and "#" .. digits:lower() or nil
end

--- Read Ghostty theme text. Never raises: bad lines and unknown keys are skipped,
--- as Ghostty skips them.
function M.parse(text)
  local theme = { ansi = {} }
  for line in (text .. "\n"):gmatch("(.-)\r?\n") do
    local key, value = line:match("^%s*([%w%-]+)%s*=%s*(.-)%s*$")
    if key == "palette" then
      local slot, color = value:match("^(%d+)%s*=%s*(.+)$")
      slot = tonumber(slot)
      if slot and slot <= 15 then
        theme.ansi[slot] = hex(color)
      end
    elseif key and FIELD_KEYS[key] then
      theme[FIELD_KEYS[key]] = hex(value)
    end
  end
  return theme
end

--- Write a theme as Ghostty theme text.
function M.serialize(theme)
  local lines = {}
  for slot = 0, 15 do
    if theme.ansi[slot] then
      lines[#lines + 1] = ("palette = %d=%s"):format(slot, theme.ansi[slot])
    end
  end
  for _, field in ipairs(FIELDS) do
    if theme[field.key] then
      lines[#lines + 1] = ("%s = %s"):format(field.name, theme[field.key])
    end
  end
  return table.concat(lines, "\n") .. "\n"
end

return M
