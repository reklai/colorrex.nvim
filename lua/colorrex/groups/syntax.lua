-- The classic syntax groups, which syntax files and many plugins link to.
return function(define)
  local link, syn, each = define.link, define.syn, define.each
  local G = {}

  G.Comment = { fg = "comment", italic = true }
  G.SpecialComment = { fg = "accent" }
  G.Todo = { fg = "on_warn", bg = "warn", bold = true }
  each(G, { "Constant", "Number", "Boolean", "Float" }, define.meaning("value"))
  each(G, { "String", "Character" }, syn("string"))
  G.Identifier = { fg = "fg" }
  G.Function = syn("func")
  G.Statement = syn("keyword")
  each(G, { "Conditional", "Repeat", "Label", "Keyword", "StorageClass" }, syn("keyword"))
  G.Exception = define.meaning("failure")
  each(G, { "PreProc", "Include", "Define", "Macro", "PreCondit" }, { fg = "preproc" })
  each(G, { "Type", "Structure", "Typedef" }, syn("type"))
  -- Word operators such as `new`, `and` and `sizeof` are here too: the bundled syntax
  -- files link them to Operator, and they read as their symbols do.
  G.Operator = { fg = "muted" }
  each(G, { "Special", "SpecialChar" }, define.meaning("escape"))
  G.Tag = { fg = "special" } -- a help file's link to jump to, not code
  G.Delimiter = { fg = "muted" }
  G.Debug = { fg = "warn" }
  G.Underlined = { underline = true }
  G.Ignore = { fg = "border" }
  G.Error = { fg = "error" }

  return G
end
