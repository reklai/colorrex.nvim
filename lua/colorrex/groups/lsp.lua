-- Language servers: references, inlay hints and semantic tokens.
--
-- A server's tokens read through the same meanings as Tree-sitter's captures (see
-- meanings.lua, tier 3). A token type with no opinion gets an empty group, not none:
-- Neovim links every standard type to a capture by default, and that link would paint
-- over what the grammar said.
local Meanings = require("colorrex.meanings")

return function(define)
  local each, link, meaning = define.each, define.link, define.meaning
  local G = {}

  each(G, { "LspReferenceText", "LspReferenceRead", "LspReferenceTarget" }, { bg = "reference" })
  G.LspReferenceWrite = { bg = "reference", underline = true }
  G.LspInlayHint = { fg = "comment" }
  G.LspCodeLens = { fg = "comment" }
  G.LspCodeLensSeparator = { fg = "border" }
  G.LspSignatureActiveParameter = { fg = "accent", bold = true }

  for token, name in pairs(Meanings.TOKENS) do
    G["@lsp.type." .. token] = meaning(name)
  end
  for _, token in ipairs(Meanings.SILENT_TOKENS) do
    G["@lsp.type." .. token] = {}
  end
  -- Neovim looks for @lsp.type.comment.c before @lsp.type.comment.
  for lang in pairs(Meanings.INACTIVE.langs) do
    G["@lsp.type." .. Meanings.INACTIVE.token .. "." .. lang] = link("Comment")
  end
  -- What a server knows about a word, beyond what it is, is drawn as style and never as
  -- color, so the word still reads as what it is.
  G["@lsp.mod.deprecated"] = { strikethrough = true }
  -- Manual-invariant operations (e.g. Rust unsafe): a quiet warning dot line, distinct
  -- from diagnostic curls and warning dashes.
  G["@lsp.mod.unsafe"] = { sp = "warn", underdotted = true }
  -- Mutable bindings carry a quiet underline; operators and calls stay unmarked.
  each(G, {
    "@lsp.typemod.variable.mutable",
    "@lsp.typemod.parameter.mutable",
    "@lsp.typemod.static.mutable",
  }, { sp = "muted", underline = true })
  -- Grammars such as Rust, C and TypeScript tag type declarations as plain @type;
  -- when a server names them as declarations, they take the same weight as @type.definition.
  -- Always defined (empty when bold is spent separating colors), so every theme defines
  -- the same set of groups.
  each(G, {
    "@lsp.typemod.type.declaration", "@lsp.typemod.type.definition",
    "@lsp.typemod.class.declaration", "@lsp.typemod.class.definition",
    "@lsp.typemod.struct.declaration", "@lsp.typemod.struct.definition",
    "@lsp.typemod.interface.declaration", "@lsp.typemod.interface.definition",
    "@lsp.typemod.enum.declaration", "@lsp.typemod.enum.definition",
  }, define.bold_def("type") and { bold = true } or {})

  return G
end
