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
  G.Operator = { fg = "muted" }
  G.Special = syn("operator")
  G.SpecialChar = syn("operator")
  G.Tag = { fg = "special" }
  G.Delimiter = { fg = "muted" }
  G.Debug = { fg = "warn" }
  G.Underlined = { underline = true }
  G.Ignore = { fg = "border" }
  G.Error = { fg = "error" }

  -- Word operators such as `new`, `and` and `sizeof`. The bundled syntax files put
  -- them in Operator next to `+` and `,`, while Treesitter calls them
  -- @keyword.operator. So a file read without a parser, as a large one often is, would
  -- show the same word in a different color. Only groups that hold nothing but words
  -- are here: in Rust, Java and Odin one group mixes in symbols, which stay quiet.
  each(G, {
    "typescriptOperator", "typescriptKeywordOp", "javaScriptOperator", "pythonOperator",
    "luaOperator", "cOperator", "cppOperator",
  }, syn("operator"))
  G.luaSymbolOperator = link("Operator") -- its syntax file links it to luaOperator

  return G
end
