-- The promises, as code.
--
-- A promise that is only stated decays. These checks run in the conformance
-- suite against every theme we can find, and at runtime in `:ColorRex check`
-- against whatever theme you are looking at, so both use the same definition.
--
-- DYNAMIC is the third promise and is about time, not one colorscheme, so it
-- lives in test/e2e. This file judges the other two.
local Color = require("color-rex.color")
local Solver = require("color-rex.compiler.solver")

local M = {}

local SYNTAX = {}
for _, role in ipairs(Solver.SYNTAX) do
  SYNTAX[#SYNTAX + 1] = role.name
end
local STATES = { "error", "warn", "ok", "info", "hint", "special", "preproc", "constant" }

-- Lifting lightness near white or black squeezes chroma, and a pale color's hue
-- is unstable to rounding. Only judge hue where there is hue to judge.
local HUE_TOLERANCE, HUE_MIN_CHROMA = 12, 0.05

--- Judge one compiled colorscheme. Returns a list of failures; empty means kept.
function M.check(colorscheme, opts)
  local failures = {}
  local function fail(promise, code, message)
    failures[#failures + 1] = { promise = promise, code = code, message = message }
  end

  local theme, roles = colorscheme.filled, colorscheme.roles
  local bg, fg = theme.bg, theme.fg
  local floor = opts.contrast - 0.01 -- bisection lands on 8-bit colors

  -- FAITHFUL: the theme's identity survives. ----------------------------------
  if roles.fg.hex ~= fg or roles.base.hex ~= bg then
    fail("faithful", "faithful.base", "fg or bg was altered")
  end

  local known = {}
  for _, role in pairs(roles) do
    if type(role) == "table" and role.hex then
      known[role.hex] = true
    end
  end
  for name, spec in pairs(colorscheme.groups) do
    for _, key in ipairs({ "fg", "bg", "sp" }) do
      if spec[key] and not known[spec[key]] then
        fail("faithful", "faithful.stray", ("%s.%s %s is not derived from the theme"):format(name, key, spec[key]))
      end
    end
  end

  local function origin(role)
    local slot = role.source:match("^ansi (%d+)$")
    return slot and theme.ansi[tonumber(slot)] or nil
  end

  for _, name in ipairs(SYNTAX) do
    local role = roles[name]
    local source = origin(role)
    if not source then
      fail("faithful", "faithful.source", ("%s does not come from an ANSI slot"):format(name))
    elseif role.from and Color.chroma(role.hex) >= HUE_MIN_CHROMA and Color.chroma(source) >= HUE_MIN_CHROMA
      and Color.hue_gap(role.hex, source) > HUE_TOLERANCE then
      fail("faithful", "faithful.hue", ("%s drifted in hue from %s to %s"):format(name, source, role.hex))
    end
  end

  -- READABLE is part of faithful: a theme's color you cannot read is not shown.
  local function floor_for(names)
    for _, name in ipairs(names) do
      local ratio = Color.contrast(roles[name].hex, bg)
      if ratio < floor then
        fail("faithful", "faithful.contrast", ("%s is %.2f:1 against the background"):format(name, ratio))
      end
    end
  end
  floor_for(SYNTAX)
  floor_for(STATES)
  floor_for({ "accent" })

  local fg_contrast = Color.contrast(fg, bg)
  local comment_contrast = Color.contrast(roles.comment.hex, bg)
  -- "Never louder" and not "strictly quieter": a theme whose fg nearly equals
  -- its bg has no quieter color to offer, and fg is the theme's to choose.
  if comment_contrast > fg_contrast + 0.01 then
    fail("faithful", "faithful.comment", ("comment %.1f:1 is louder than text %.1f:1"):format(
      comment_contrast, fg_contrast))
  end
  if comment_contrast < math.min(Solver.COMMENT_FLOOR, fg_contrast * 0.8) - 0.01 then
    fail("faithful", "faithful.comment", ("comment is only %.2f:1"):format(comment_contrast))
  end

  -- UNIQUE: every pair of roles can be told apart. -----------------------------
  for i = 1, #SYNTAX do
    for j = i + 1, #SYNTAX do
      local a, b = SYNTAX[i], SYNTAX[j]
      if Color.distance(roles[a].hex, roles[b].hex) < Solver.DISTINCT
        and Solver.same_style(roles.styles[a], roles.styles[b]) then
        fail("unique", "unique.collision", ("%s and %s look identical"):format(a, b))
      end
    end
  end

  return failures
end

return M
