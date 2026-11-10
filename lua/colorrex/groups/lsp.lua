-- Language servers: references, inlay hints and semantic tokens.
--
-- A server's tokens read through the same meanings as Tree-sitter's captures (see
-- meanings.lua, tier 3). A token type with no opinion gets an empty group, not none:
-- Neovim links every standard type to a capture by default, and that link would paint
-- over what the grammar said.
local Meanings = require("colorrex.meanings")

return function(define)
  local each, meaning = define.each, define.meaning
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
  -- What a server knows about a word, beyond what it is, is drawn as style and never as
  -- color, so the word still reads as what it is.
  G["@lsp.mod.deprecated"] = { strikethrough = true }

  return G
end
