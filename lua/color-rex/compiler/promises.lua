-- The promises, as code.
--
-- A promise that is only stated decays. These checks run in the conformance suite
-- against every theme we can find, and at runtime in `:ColorRex check` against
-- whatever theme you are looking at, so both use the same definition.
--
-- DYNAMIC is the third promise and is about time, not one colorscheme, so it lives
-- in test/e2e. This file judges the other two.
local Color = require("color-rex.color")
local Roles = require("color-rex.roles")

local M = {}

local HUE_TOLERANCE = 12 -- degrees a lifted color may drift from its source
local ROUNDING = 0.01 -- bisection lands on 8-bit colors, a hair under an exact target

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

  -- UNIQUE: every pair of syntax roles can be told apart. ---------------------------
  for i = 1, #Roles.SYNTAX do
    for j = i + 1, #Roles.SYNTAX do
      local a, b = Roles.SYNTAX[i].name, Roles.SYNTAX[j].name
      if Color.distance(roles[a].hex, roles[b].hex) < Color.DISTINCT and Roles.same_style(styles[a], styles[b]) then
        fail("unique.collision", ("%s and %s look identical"):format(a, b))
      end
    end
  end

  return failures
end

return M
