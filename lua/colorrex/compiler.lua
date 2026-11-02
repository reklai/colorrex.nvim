-- Compiles a theme into a colorscheme:
--
--   theme -> fill the gaps -> solve for roles -> build groups -> resolve to hex
--
-- It is a pure function of (theme, options): no clock, no randomness, no state.
-- The same input always produces identical output, and a compile takes a small
-- fraction of a millisecond, so nothing downstream caches compiled groups.
local Groups = require("colorrex.groups")
local Lualine = require("colorrex.lualine")
local Promises = require("colorrex.compiler.promises")
local Roles = require("colorrex.roles")
local Standalone = require("colorrex.compiler.standalone")
local Theme = require("colorrex.theme")

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
  local fingerprint = Roles.fingerprint(signature)
  local solved = Roles.solve(filled, opts, fingerprint)

  local group_specs = Groups.build(opts, solved.styles)
  local groups = {}
  for name, spec in pairs(group_specs) do
    groups[name] = resolve(spec, solved.roles)
  end

  local lualine = {}
  for mode, sections in pairs(Lualine.build()) do
    lualine[mode] = {}
    for section, spec in pairs(sections) do
      lualine[mode][section] = resolve(spec, solved.roles)
    end
  end

  return {
    signature = signature,
    -- What a person reads. Short enough to say out loud, so only nearly unique.
    id = ("%06x"):format(fingerprint % 0x1000000),
    casting = solved.casting,
    background = filled.background,
    completeness = Theme.completeness(theme),
    theme = theme,
    filled = filled,
    roles = solved.roles,
    styles = solved.styles,
    notes = solved.notes,
    group_specs = group_specs,
    groups = groups,
    lualine = lualine,
  }
end

return M
