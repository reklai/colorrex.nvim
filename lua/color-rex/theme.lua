-- The theme format: what a terminal or a file can say about colors.
--
-- A theme is { fg, bg, cursor, ansi = { [0..15] } } with any field possibly
-- missing. These are the colors a libghostty terminal can report. Only fill() promises a complete one, so the
-- compiler never has to handle an absent color.
--
-- Themes are read and written as Ghostty theme files. That is the format Rex
-- imports, the corpus the conformance suite runs on, and the cache on disk, which
-- is why the cache is plain text and never executed.
local Color = require("color-rex.color")

local M = {}

-- Deliberately grey. These appear only when a terminal has told us nothing, and
-- a failed query should look failed rather than like a plausible theme.
local NEUTRAL = {
  dark = { fg = "#c8c8c8", bg = "#1c1c1c", ramp = { [0] = "#3a3a3a", [7] = "#b0b0b0", [8] = "#6c6c6c", [15] = "#e4e4e4" } },
  light = { fg = "#303030", bg = "#f4f4f4", ramp = { [0] = "#d0d0d0", [7] = "#585858", [8] = "#8a8a8a", [15] = "#1c1c1c" } },
}
local GREY = { dark = "#a0a0a0", light = "#606060" }

local function valid(hex)
  return type(hex) == "string" and Color.parse(hex) ~= nil
end

--- How much of a theme is present.
---   "full"    foreground, background and all 16 ANSI colors
---   "partial" some of those
---   "none"    nothing usable
function M.completeness(theme)
  if theme == nil then
    return "none"
  end
  local ansi = theme.ansi or {}
  local count = 0
  for slot = 0, 15 do
    if valid(ansi[slot]) then
      count = count + 1
    end
  end
  if valid(theme.fg) and valid(theme.bg) and count == 16 then
    return "full"
  end
  if count == 0 and not valid(theme.fg) and not valid(theme.bg) then
    return "none"
  end
  return "partial"
end

--- A complete copy of a theme, with neutral colors in every gap. `background`
--- ("dark" or "light") picks the neutral set when the theme has no bg to judge by.
function M.fill(theme, background)
  theme = theme or {}
  local bg = valid(theme.bg) and theme.bg:lower() or nil
  local name = background == "light" and "light" or "dark"
  if bg then
    name = Color.is_dark(bg) and "dark" or "light"
  end
  local neutral = NEUTRAL[name]
  local filled = {
    fg = valid(theme.fg) and theme.fg:lower() or neutral.fg,
    bg = bg or neutral.bg,
    cursor = valid(theme.cursor) and theme.cursor:lower() or nil,
    background = name,
    ansi = {},
  }
  local ansi = theme.ansi or {}
  for slot = 0, 15 do
    filled.ansi[slot] = valid(ansi[slot]) and ansi[slot]:lower() or neutral.ramp[slot] or GREY[name]
  end
  return filled
end

--- A stable identity for a filled theme. Two themes render identically exactly
--- when their signatures match, so this is what decides a repaint.
function M.signature(filled)
  local parts = { filled.fg, filled.bg, filled.cursor or "-" }
  for slot = 0, 15 do
    parts[#parts + 1] = filled.ansi[slot]
  end
  return table.concat(parts, ",")
end

local FIELDS = {
  { key = "bg", name = "background" },
  { key = "fg", name = "foreground" },
  { key = "cursor", name = "cursor-color" },
}

local function hex(value)
  local digits = value:match("^#?(%x%x%x%x%x%x)$")
  return digits and "#" .. digits:lower() or nil
end

--- Read Ghostty theme text. Never raises: bad lines and unknown keys are
--- skipped, as Ghostty skips them.
function M.parse(text)
  local keys = {}
  for _, field in ipairs(FIELDS) do
    keys[field.name] = field.key
  end
  local theme = { ansi = {} }
  for line in (text .. "\n"):gmatch("(.-)\r?\n") do
    local key, value = line:match("^%s*([%w%-]+)%s*=%s*(.-)%s*$")
    if key == "palette" then
      local slot, color = value:match("^(%d+)%s*=%s*(.+)$")
      slot = tonumber(slot)
      if slot and slot <= 15 then
        theme.ansi[slot] = hex(color)
      end
    elseif key and keys[key] then
      theme[keys[key]] = hex(value)
    end
  end
  return theme
end

--- Write a theme as Ghostty theme text.
function M.serialize(theme)
  local lines = {}
  for slot = 0, 15 do
    if theme.ansi and theme.ansi[slot] then
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
