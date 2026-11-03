-- The promises, as code.
--
-- A promise that is only stated decays. These checks run in the conformance suite
-- against every theme we can find, and at runtime in `:ColorRex check` against
-- whatever theme you are looking at, so both use the same definition.
--
-- This file judges FAITHFUL and PRACTICAL, which hold for one colorscheme. VOICE is
-- about how themes differ from one another, so test/conformance judges it across
-- every theme at once. Following live theme changes is not a promise; test/e2e
-- covers it.
local Color = require("colorrex.color")
local Roles = require("colorrex.roles")

local M = {}

local HUE_TOLERANCE = 12 -- degrees a lifted color may drift from its source
local ROUNDING = 0.01 -- bisection lands on 8-bit colors, a hair under an exact target

-- Lines, not text. They are meant to recede, and nobody reads them.
local DECORATION, DECORATION_ALT = "Border$", "Separator$"

-- Groups with no background of their own, drawn on a list and on its selection as
-- the selection moves: a picker's matched letters. The surface the list sits on.
local OVER_SELECTION = { TelescopeMatching = "base", BlinkCmpLabelMatch = "element" }

--- Judge one compiled colorscheme. Returns a list of failures; empty means kept.
function M.check(colorscheme, opts)
  local failures = {}
  local function fail(code, message)
    failures[#failures + 1] = { code = code, message = message }
  end

  local theme, roles, styles = colorscheme.filled, colorscheme.roles, colorscheme.styles
  local bg, fg = theme.bg, theme.fg

  -- FAITHFUL: the theme's identity survives. --------------------------------------
  if roles.fg.hex ~= fg or roles.base.hex ~= bg then
    fail("faithful.base", "fg or bg was altered")
  end

  local known = {}
  for _, role in pairs(roles) do
    known[role.hex] = true
  end
  for name, spec in pairs(colorscheme.groups) do
    for _, key in ipairs({ "fg", "bg", "sp" }) do
      if spec[key] and not known[spec[key]] then
        fail("faithful.stray", ("%s.%s %s is not derived from the theme"):format(name, key, spec[key]))
      end
    end
  end

  for _, syntax in ipairs(Roles.SYNTAX) do
    local role = roles[syntax.name]
    local source = role.slot and theme.ansi[role.slot]
    if not source then
      fail("faithful.source", ("%s does not come from an ANSI slot"):format(syntax.name))
    elseif role.from and Color.chroma(role.hex) >= Color.HUE_MIN_CHROMA
      and Color.chroma(source) >= Color.HUE_MIN_CHROMA and Color.hue_gap(role.hex, source) > HUE_TOLERANCE then
      fail("faithful.hue", ("%s drifted in hue from %s to %s"):format(syntax.name, source, role.hex))
    end
  end

  -- A theme's color you cannot read is not being shown faithfully.
  local function readable(name)
    local ratio = Color.contrast(roles[name].hex, bg)
    if ratio < opts.contrast - ROUNDING then
      fail("faithful.contrast", ("%s is %.2f:1 against the background"):format(name, ratio))
    end
  end
  for _, role in ipairs(Roles.SYNTAX) do
    readable(role.name)
  end
  for _, role in ipairs(Roles.SECONDARY) do
    readable(role.name)
  end
  for _, role in ipairs(Roles.PALETTE) do
    readable(role.name)
  end
  readable("accent")
  readable("landmark")
  if roles.property.source ~= "fg" then -- fg is the theme's to choose, however faint
    readable("property")
  end

  local fg_contrast = Color.contrast(fg, bg)
  local comment_contrast = Color.contrast(roles.comment.hex, bg)
  -- "Never louder" and not "strictly quieter": a theme whose fg nearly equals its
  -- bg has no quieter color to offer, and fg is the theme's to choose.
  if comment_contrast > fg_contrast + ROUNDING then
    fail("faithful.comment", ("comment %.1f:1 is louder than text %.1f:1"):format(comment_contrast, fg_contrast))
  end
  if comment_contrast < Roles.comment_floor(fg_contrast) - ROUNDING then
    fail("faithful.comment", ("comment is only %.2f:1"):format(comment_contrast))
  end

  -- A color readable on the background proves nothing about what is painted on top
  -- of something else. So every group is judged against what is behind its own text.
  local text = Roles.surface_text(roles, bg)
  for name, role in pairs(roles) do
    if role.least then
      local faint = Roles.unreadable_on(text, role.hex)
      if faint and Roles.can_ease(bg, role.over, role.mix, role.least) then
        fail("faithful.surface", ("%s is too faint on %s, which could ease off"):format(faint.name, name))
      end
    end
  end

  -- By strength and not by contrast: with fg and bg at equal luminance the two differ
  -- only in hue, and contrast reads that as rounding noise around 1.00:1.
  if roles.visual.mix <= roles.cursorline.mix then
    fail("faithful.surface", "a selection is fainter than the cursor line")
  end

  local function too_faint(text, fill)
    local best = math.max(Color.contrast(fg, fill), Color.contrast(bg, fill))
    return Color.contrast(text, fill) < math.min(opts.contrast, best, fg_contrast) - ROUNDING
  end

  for name, group in pairs(colorscheme.groups) do
    -- A theme's fg is never altered, so one already below the floor is the theme's to
    -- choose. A readable fg is no excuse: it can still be the wrong side of a fill.
    local excused = group.fg == fg and fg_contrast < opts.contrast
    if group.fg and group.bg and not excused and not name:find(DECORATION) and not name:find(DECORATION_ALT) then
      if too_faint(group.fg, group.bg) then
        fail("faithful.surface", ("%s is %.2f:1 on its own fill"):format(name, Color.contrast(group.fg, group.bg)))
      end
    end
  end

  for name, under in pairs(OVER_SELECTION) do
    local group = colorscheme.groups[name]
    for _, surface in ipairs({ under, "visual" }) do
      if group and group.fg and too_faint(group.fg, roles[surface].hex) then
        fail("faithful.surface", ("%s is %.2f:1 on %s"):format(name, Color.contrast(group.fg, roles[surface].hex), surface))
      end
    end
  end

  -- PRACTICAL: every pair of syntax roles can be told apart. ------------------------
  for i = 1, #Roles.SYNTAX do
    for j = i + 1, #Roles.SYNTAX do
      local a, b = Roles.SYNTAX[i].name, Roles.SYNTAX[j].name
      if Color.distance(roles[a].hex, roles[b].hex) < Color.DISTINCT and Roles.same_style(styles[a], styles[b]) then
        fail("practical.collision", ("%s and %s look identical"):format(a, b))
      end
    end
  end

  return failures
end

return M
