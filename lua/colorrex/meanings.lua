-- Meanings: what a reader looks for in code, in every language.
--
-- A theme defines colors and a grammar defines kinds of node; neither says what a
-- person needs to see. This is the vocabulary between them, the middle of the
-- compiler:
--
--   terminal theme --> roles --+--> highlights
--   any grammar ---> meanings -+
--
-- Each meaning wears exactly one role, and no two meanings share one, so a color
-- means one thing wherever it appears. A language reaches these meanings in tiers:
--
--   1. Tree-sitter's standard capture names, a vocabulary grammars already share, so
--      any language with a highlights query is covered the day it ships one.
--   2. The lexicon below: words that mean the same thing across languages, within the
--      kind of capture they come in, so `nil`, `null`, `None` and `Nothing` all read
--      as one. It names words and never grammar nodes, so no grammar update can
--      break it.
--
-- Pure: no Neovim, so every rule here runs under plain LuaJIT.
local M = {}

-- In order of salience. When a palette cannot keep every meaning apart, the roles
-- solver gives way from the bottom of this list, never from the top.
M.VOCABULARY = {
  { name = "failure", role = "failure", asks = "can this fail, or be missing?" },
  { name = "call", role = "func", asks = "what runs here?" },
  { name = "type", role = "type", asks = "what kind of thing is this?" },
  { name = "control", role = "keyword", asks = "where does the flow go?" },
  { name = "field", role = "property", asks = "which part is the object?" },
  { name = "text", role = "string", asks = "what does it say?" },
  { name = "value", role = "number", asks = "what literal is this?" },
  { name = "boundary", role = "preproc", asks = "what comes from elsewhere?" },
  { name = "name", role = "fg", asks = "which variable is this?" },
  { name = "quiet", role = "muted", asks = "nothing; it is structure" },
}

M.ROLE = {}
for _, meaning in ipairs(M.VOCABULARY) do
  M.ROLE[meaning.name] = meaning.role
end

-- Tier 1: what each standard capture means. A capture not listed falls back to its
-- parent, as Neovim's own lookup does (@keyword.return to @keyword).
M.CAPTURES = {
  ["@keyword.exception"] = "failure", -- throw, raise, try, catch, rescue, except, panic!
  ["@constant.builtin"] = "value", -- the lexicon lifts nil, null and None out of it
  ["@constant"] = "value",
  ["@boolean"] = "value",
  ["@number"] = "value",
  ["@number.float"] = "value",
  ["@character"] = "text",
  ["@string"] = "text",
  ["@type"] = "type",
  ["@type.builtin"] = "type",
  ["@type.definition"] = "type",
  ["@constructor"] = "type",
  ["@module"] = "type",
  ["@module.builtin"] = "type",
  ["@attribute"] = "type",
  ["@attribute.builtin"] = "type",
  ["@function"] = "call",
  ["@function.call"] = "call",
  ["@function.method"] = "call",
  ["@function.method.call"] = "call",
  ["@function.builtin"] = "call",
  ["@keyword"] = "control",
  ["@label"] = "control",
  ["@variable"] = "name",
  ["@variable.member"] = "field",
  ["@property"] = "field",
  ["@variable.builtin"] = "quiet",
  ["@variable.parameter"] = "quiet",
  ["@variable.parameter.builtin"] = "quiet",
  ["@operator"] = "quiet",
  ["@punctuation.delimiter"] = "quiet",
  ["@punctuation.bracket"] = "quiet",
}

-- Tier 2: the failure lexicon. Each entry is a kind of capture and the words that mean
-- failure when they come in it. A word in another kind of capture is left alone: `error`
-- the Go type is failure, and so is `error` the Lua function, but a string saying
-- "error" is text. `langs` limits an entry to the languages where its spelling is
-- unambiguous.
local ABSENT = {
  "nil", "null", "NULL", "nullptr", "None", "undefined", "Nil", "Nothing", "Err", "Error", "Left", "unreachable",
}
M.LEXICON = {
  { kinds = { "constant", "boolean", "constructor", "variable.builtin" }, words = ABSENT },
  -- BEAM atoms: Erlang's error, undefined and 'EXIT', Elixir's :error.
  { kinds = { "constant", "string.special.symbol" }, words = { "error", "undefined", "'EXIT'", ":error" } },
  { kinds = { "variable", "variable.parameter" }, words = { "err", "errno" }, patterns = { "%lErr$", "_err$" } },
  {
    kinds = { "type", "constructor", "module" },
    words = { "error", "errors", "Err", "Error", "Exception", "Throwable" },
    patterns = { "%wError$", "%wException$", "_Error$" },
  },
  {
    kinds = { "function" },
    words = {
      "panic", "error", "errorf", "Errorf", "abort", "assert", "fatalError", "TODO", "todo", "perror", "raise",
      "throw", "unreachable", "unimplemented", "recover", "pcall", "xpcall", "@panic", "die",
    },
    patterns = { "_error$" }, -- C++ std::runtime_error and its kin, built where they are thrown
  },
  {
    kinds = { "keyword" },
    words = {
      "errdefer", "orelse", "or_return", "or_else", "or_break", "or_continue", "panic", "todo",
      "raise", "reraise", "rescue", "ensure", "throw", "throws", "rethrows", "catch", "try", "error",
    },
  },
  { kinds = { "operator" }, words = { "?" }, langs = { rust = true } }, -- Rust's error propagation
}

-- Index: kind -> { words = set, patterns = list, langs = set|nil } entries.
local BY_KIND = {}
for _, entry in ipairs(M.LEXICON) do
  local words = {}
  for _, word in ipairs(entry.words) do
    words[word] = true
  end
  for _, kind in ipairs(entry.kinds) do
    BY_KIND[kind] = BY_KIND[kind] or {}
    table.insert(BY_KIND[kind], { words = words, patterns = entry.patterns or {}, langs = entry.langs })
  end
end

--- The kinds a capture belongs to, most specific first: @function.method.call is a
--- function.method.call, a function.method and a function.
local function kinds_of(capture)
  local out, name = {}, capture:gsub("^@", "")
  while name and name ~= "" do
    out[#out + 1] = name
    name = name:match("^(.+)%.[^.]+$")
  end
  return out
end

local MAX_WORD = 40 -- no word in the lexicon is longer; nothing longer is looked at

--- The meaning the lexicon gives `text` in this capture, or nil when it has nothing
--- to add to the capture's own. Only failure is ever added: that is the meaning no
--- grammar marks on its own.
function M.refine(capture, text, lang)
  if #text > MAX_WORD then
    return nil
  end
  local word = text:match("^[%w_]+::([%w_]+)$") or text -- C++ std::runtime_error, Rust ParseError::Empty
  for _, kind in ipairs(kinds_of(capture)) do
    for _, entry in ipairs(BY_KIND[kind] or {}) do
      if not entry.langs or entry.langs[lang] then
        if entry.words[word] then
          return "failure"
        end
        for _, pattern in ipairs(entry.patterns) do
          if word:find(pattern) then
            return "failure"
          end
        end
      end
    end
  end
  return nil
end

--- Whether the lexicon could say anything about a capture, so a host can skip the
--- rest without reading their text.
function M.can_refine(capture)
  for _, kind in ipairs(kinds_of(capture)) do
    if BY_KIND[kind] then
      return true
    end
  end
  return false
end

--- The meaning of a capture by tier 1 alone: its own entry, else its parent's.
function M.of_capture(capture)
  local name = capture
  while name do
    if M.CAPTURES[name] then
      return M.CAPTURES[name]
    end
    name = name:match("^(.+)%.[^.]+$")
  end
  return nil
end

return M
