-- Tree-sitter captures. Neovim falls back from @a.b.lang to @a.b to @a, so only the
-- captures that differ from their parent need a line here.
return function(define)
  local link, syn, each = define.link, define.syn, define.each
  local G = {}

  G["@variable"] = { fg = "fg" }
  G["@variable.builtin"] = { fg = "special" }
  G["@variable.parameter"] = { fg = "muted" }
  G["@variable.parameter.builtin"] = { fg = "special" }
  G["@variable.member"] = { fg = "fg" }
  G["@constant"] = { fg = "constant" }
  G["@constant.builtin"] = { fg = "special" }
  G["@constant.macro"] = { fg = "preproc" }
  G["@module"] = syn("type")
  G["@module.builtin"] = { fg = "special" }
  G["@label"] = syn("keyword")
  G["@string"] = syn("string")
  G["@string.documentation"] = { fg = "comment" }
  each(G, { "@string.regexp", "@string.escape", "@string.special", "@string.special.symbol" }, syn("operator"))
  G["@string.special.path"] = { fg = "func" }
  G["@string.special.url"] = { fg = "accent", underline = true }
  G["@character"] = syn("string")
  G["@character.special"] = syn("operator")
  each(G, { "@boolean", "@number", "@number.float" }, syn("number"))
  each(G, { "@type", "@type.builtin", "@type.definition", "@attribute" }, syn("type"))
  G["@attribute.builtin"] = { fg = "special" }
  G["@property"] = { fg = "fg" }
  each(G, { "@function", "@function.call", "@function.method", "@function.method.call" }, syn("func"))
  G["@function.builtin"] = { fg = "special" }
  G["@function.macro"] = { fg = "preproc" }
  G["@constructor"] = syn("type")
  G["@operator"] = syn("operator")
  each(G, {
    "@keyword", "@keyword.coroutine", "@keyword.function", "@keyword.type", "@keyword.modifier",
    "@keyword.repeat", "@keyword.return", "@keyword.debug", "@keyword.exception",
    "@keyword.conditional",
  }, syn("keyword"))
  each(G, { "@keyword.directive", "@keyword.directive.define", "@keyword.import" }, { fg = "preproc" })
  each(G, { "@keyword.operator", "@keyword.conditional.ternary" }, syn("operator"))
  each(G, { "@punctuation.delimiter", "@punctuation.bracket" }, { fg = "muted" })
  G["@punctuation.special"] = syn("operator")
  G["@comment"] = link("Comment")
  G["@comment.documentation"] = link("Comment")
  G["@comment.error"] = { fg = "error", bold = true }
  G["@comment.warning"] = { fg = "warn", bold = true }
  G["@comment.todo"] = link("Todo")
  G["@comment.note"] = { fg = "info", bold = true }
  G["@tag"] = { fg = "special" }
  G["@tag.builtin"] = { fg = "special" }
  G["@tag.attribute"] = syn("type")
  G["@tag.delimiter"] = { fg = "muted" }
  G["@diff.plus"] = link("Added")
  G["@diff.minus"] = link("Removed")
  G["@diff.delta"] = link("Changed")
  G["@markup.strong"] = { bold = true }
  G["@markup.italic"] = { italic = true }
  G["@markup.strikethrough"] = { strikethrough = true }
  G["@markup.underline"] = { underline = true }
  G["@markup.heading"] = { fg = "accent", bold = true }
  for level = 1, 6 do
    G["@markup.heading." .. level] = link("@markup.heading")
  end
  G["@markup.quote"] = { fg = "muted", italic = true }
  G["@markup.math"] = syn("operator")
  G["@markup.link"] = { fg = "accent" }
  G["@markup.link.label"] = { fg = "accent" }
  G["@markup.link.url"] = { fg = "accent", underline = true }
  G["@markup.raw"] = syn("string")
  G["@markup.raw.block"] = syn("string")
  G["@markup.list"] = syn("operator")
  G["@markup.list.checked"] = { fg = "ok" }
  G["@markup.list.unchecked"] = { fg = "muted" }

  return G
end
