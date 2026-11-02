-- Highlight groups, written in terms of roles.
--
-- A group can only name a role, so no group can drift away from the theme, and a
-- test fails if a color literal appears here or in groups/. Colors in these files are
-- role names; the compiler resolves them.
--
-- Each file in groups/ is one area of the editor, and returns a function from the
-- helpers below to its groups. Add a plugin to groups/plugins.lua.
local AREAS = {
  require("colorrex.groups.editor"),
  require("colorrex.groups.syntax"),
  require("colorrex.groups.treesitter"),
  require("colorrex.groups.lsp"),
  require("colorrex.groups.diagnostics"),
  require("colorrex.groups.plugins"),
}

local M = {}

--- Every group spec for these options and syntax styles. A group defined in two
--- areas is refused: one would silently overwrite the other, in an order nobody chose.
function M.build(opts, styles)
  local define = {
    base = (not opts.transparent) and "base" or nil, -- nil leaves it to the terminal
    link = function(to)
      return { link = to }
    end,
    --- A syntax role, in the weight and slant it was given.
    syn = function(role)
      local style = styles[role]
      return { fg = role, bold = style.bold, italic = style.italic, underline = style.underline }
    end,
    each = function(groups, names, spec)
      for _, name in ipairs(names) do
        groups[name] = spec
      end
    end,
  }

  local specs = {}
  for _, area in ipairs(AREAS) do
    for name, spec in pairs(area(define)) do
      assert(specs[name] == nil, ("group %s is defined in two areas"):format(name))
      specs[name] = spec
    end
  end
  return specs
end

return M
