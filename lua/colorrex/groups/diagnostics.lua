-- Diagnostics, in every place Neovim shows them.
--
-- Severity is told by shape as well as by color: a curl for an error, dashes for a
-- warning, dots for anything quieter. libghostty draws all of kitty's underline styles
-- in the line's own color, so a severity reads without telling hues apart, and a red
-- curl never looks like failure's color on a word, which has no line at all.
local SHAPE = { Error = "undercurl", Warn = "underdashed", Info = "underdotted", Hint = "underdotted", Ok = "underline" }

return function(define)
  local G = {}

  for name, role in pairs({ Error = "error", Warn = "warn", Info = "info", Hint = "hint", Ok = "ok" }) do
    G["Diagnostic" .. name] = { fg = role }
    G["DiagnosticVirtualText" .. name] = { fg = role }
    G["DiagnosticVirtualLines" .. name] = { fg = role }
    G["DiagnosticSign" .. name] = { fg = role }
    G["DiagnosticFloating" .. name] = { fg = "float_" .. role, bg = "element" }
    G["DiagnosticUnderline" .. name] = { sp = role, [SHAPE[name]] = true }
  end
  G.DiagnosticUnnecessary = { fg = "comment" }
  G.DiagnosticDeprecated = { strikethrough = true }

  return G
end
