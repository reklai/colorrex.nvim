-- The classic syntax groups, which syntax files and many plugins link to.
return function(define)
  local syn, each = define.syn, define.each
  local G = {}

  G.Comment = { fg = "comment", italic = true }
  G.SpecialComment = { fg = "accent" }
  G.Todo = { fg = "on_warn", bg = "warn", bold = true }
  G.Constant = { fg = "constant" }
  each(G, { "Number", "Boolean", "Float" }, syn("number"))
  each(G, { "String", "Character" }, syn("string"))
  G.Identifier = { fg = "fg" }
  G.Function = syn("func")
  G.Statement = syn("keyword")
  each(G, { "Conditional", "Repeat", "Label", "Keyword", "Exception", "StorageClass" }, syn("keyword"))
  each(G, { "PreProc", "Include", "Define", "Macro", "PreCondit" }, { fg = "preproc" })
  each(G, { "Type", "Structure", "Typedef" }, syn("type"))
  G.Operator = { fg = "muted" }
  G.Special = syn("operator")
  G.SpecialChar = syn("operator")
  G.Tag = { fg = "special" }
  G.Delimiter = { fg = "muted" }
  G.Debug = { fg = "warn" }
  G.Underlined = { underline = true }
  G.Ignore = { fg = "border" }
  G.Error = { fg = "error" }

  return G
end
