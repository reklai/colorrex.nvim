-- Language servers: references, inlay hints and semantic tokens.
return function(define)
  local link, syn, each = define.link, define.syn, define.each
  local G = {}

  each(G, { "LspReferenceText", "LspReferenceRead", "LspReferenceTarget" }, { bg = "reference" })
  G.LspReferenceWrite = { bg = "reference", underline = true }
  G.LspInlayHint = { fg = "comment" }
  G.LspCodeLens = { fg = "comment" }
  G.LspCodeLensSeparator = { fg = "border" }
  G.LspSignatureActiveParameter = { fg = "accent", bold = true }
  G["@lsp.type.keyword"] = syn("keyword")
  G["@lsp.type.modifier"] = syn("keyword")
  each(G, { "@lsp.type.function", "@lsp.type.method" }, syn("func"))
  G["@lsp.type.macro"] = { fg = "preproc" }
  G["@lsp.type.decorator"] = syn("type")
  each(G, {
    "@lsp.type.type", "@lsp.type.class", "@lsp.type.struct", "@lsp.type.enum",
    "@lsp.type.interface", "@lsp.type.namespace", "@lsp.type.typeParameter",
  }, syn("type"))
  G["@lsp.type.parameter"] = { fg = "muted" }
  G["@lsp.type.property"] = { fg = "property" }
  G["@lsp.type.variable"] = { fg = "fg" }
  G["@lsp.type.enumMember"] = syn("number")
  G["@lsp.type.string"] = syn("string")
  G["@lsp.type.number"] = syn("number")
  G["@lsp.type.operator"] = { fg = "muted" }
  G["@lsp.type.comment"] = link("Comment")
  G["@lsp.mod.deprecated"] = { strikethrough = true }

  return G
end
