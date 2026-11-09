-- Tree-sitter captures. Neovim falls back from @a.b.lang to @a.b to @a, so only the
-- captures that differ from their parent need a line here.
--
-- Color goes where it tells you something the shape of the text does not. A field, a
-- method and a variable are all just words, so they differ in color. `=` and `self` can
-- be read on sight, and appear on nearly every line, so they stay quiet.
--
-- Code captures take the color of what they mean (see meanings.lua), so the same
-- meaning reads the same in every language. The lines after the loop are captures
-- whose meaning depends on more than their name.
local Meanings = require("colorrex.meanings")

return function(define)
  local link, syn, each, meaning = define.link, define.syn, define.each, define.meaning
  local G = {}

  for capture, name in pairs(Meanings.CAPTURES) do
    G[capture] = meaning(name)
  end
  -- What the lexicon adds, drawn by the host. Negation wears control's color, and
  -- bold, because it is the one character on the line that turns the condition around.
  G.ColorRexFailure = meaning(Meanings.ADDED.failure)
  G.ColorRexNegation = meaning(Meanings.ADDED.negation)
  G.ColorRexNegation.bold = true

  G["@constant.macro"] = { fg = "preproc" }
  G["@string.documentation"] = { fg = "comment" }
  each(G, { "@string.regexp", "@string.escape", "@string.special", "@string.special.symbol" }, syn("operator"))
  G["@string.special.path"] = { fg = "func" }
  G["@string.special.url"] = { fg = "accent", underline = true }
  G["@character.special"] = syn("operator")
  G["@function.macro"] = { fg = "preproc" }
  each(G, {
    "@keyword.coroutine", "@keyword.function", "@keyword.type", "@keyword.modifier",
    "@keyword.repeat", "@keyword.return", "@keyword.debug", "@keyword.conditional",
  }, meaning("control"))
  each(G, { "@keyword.directive", "@keyword.directive.define", "@keyword.import" }, { fg = "preproc" })
  each(G, { "@keyword.operator", "@keyword.conditional.ternary" }, syn("operator"))
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
