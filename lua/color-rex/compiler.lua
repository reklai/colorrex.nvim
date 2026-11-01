-- Compiles a theme into a colorscheme:
--
--   theme -> fill the gaps -> solve for roles -> build groups -> resolve to hex
--
-- It is a pure function of (theme, options): no clock, no randomness, no state.
-- The same input always produces identical output, and a compile takes a small
-- fraction of a millisecond, so nothing downstream caches compiled groups.
local Casting = require("color-rex.compiler.casting")
local Groups = require("color-rex.compiler.groups")
local Lualine = require("color-rex.compiler.lualine")
local Promises = require("color-rex.compiler.promises")
local Solver = require("color-rex.compiler.solver")
local Standalone = require("color-rex.compiler.standalone")
local Theme = require("color-rex.theme")

local M = {}

M.check = Promises.check
M.standalone = Standalone.source

local COLOR_KEYS = { "fg", "bg", "sp" }

--- A group spec names roles; the highlight it becomes holds their colors.
local function resolve(spec, roles)
  local out = {}
  for key, value in pairs(spec) do
    out[key] = value
  end
  for _, key in ipairs(COLOR_KEYS) do
    if spec[key] then
      local role = roles[spec[key]]
      assert(role, ("group names unknown role '%s'"):format(tostring(spec[key])))
      out[key] = role.hex
    end
  end
  return out
end

--- Compile a theme. `background` is "dark" or "light", used only when the theme
--- has no bg of its own.
function M.compile(theme, opts, background)
  local filled = Theme.fill(theme, background)
  local signature = Theme.signature(filled)
  local fingerprint = Casting.fingerprint(signature)
  local arrangement, casting = Casting.arrangement(fingerprint)
  if not opts.identity then
    arrangement, casting = Casting.ARRANGEMENTS[1], 1
  end
  local roles = Solver.solve(filled, opts, arrangement)

  local group_specs = Groups.build(opts, roles.styles)
  local groups = {}
  for name, spec in pairs(group_specs) do
    groups[name] = resolve(spec, roles)
  end

  local lualine = {}
  for mode, sections in pairs(Lualine.build()) do
    lualine[mode] = {}
    for section, spec in pairs(sections) do
      lualine[mode][section] = resolve(spec, roles)
    end
  end

  local terminal_colors = {}
  for slot = 0, 15 do
    terminal_colors[slot] = filled.ansi[slot]
  end

  return {
    -- Identifies this result: what it came from, and how it was compiled.
    key = ("%s|%s|%s|%s"):format(tostring(opts.contrast), tostring(opts.transparent), tostring(opts.identity), signature),
    id = ("%06x"):format(fingerprint % 16777216), -- what a person reads; key is what code compares
    casting = casting,
    background = filled.background,
    completeness = Theme.completeness(theme),
    theme = theme or {},
    filled = filled,
    roles = roles,
    group_specs = group_specs,
    groups = groups,
    terminal_colors = terminal_colors,
    lualine = lualine,
    notes = roles.notes,
  }
end

return M
