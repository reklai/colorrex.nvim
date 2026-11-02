-- Diagnostics, in every place Neovim shows them.
return function(define)
  local G = {}

  for name, role in pairs({ Error = "error", Warn = "warn", Info = "info", Hint = "hint", Ok = "ok" }) do
    G["Diagnostic" .. name] = { fg = role }
    G["DiagnosticVirtualText" .. name] = { fg = role }
    G["DiagnosticVirtualLines" .. name] = { fg = role }
    G["DiagnosticSign" .. name] = { fg = role }
    G["DiagnosticFloating" .. name] = { fg = "float_" .. role, bg = "element" }
    G["DiagnosticUnderline" .. name] = { sp = role, undercurl = true }
  end
  G.DiagnosticUnnecessary = { fg = "comment" }
  G.DiagnosticDeprecated = { strikethrough = true }

  return G
end
