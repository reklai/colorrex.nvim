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

  -- Negation: the one character that turns a condition around. Grammars file `!` and
  -- `not` with `+` and `,`, the quietest text on the line, so `if !ok` read as `if ok`
  -- at a glance. `not` and `unless` only ever negate. `!` negates only as a prefix: a
  -- grammar also uses it for TypeScript's `foo!`, Rust's `panic!` and `-> !`, and
  -- Zig's `!T`, under other nodes. Zig's parser files `!ok` as an error union too, so
  -- Zig's `!` is left alone. Erlang's `not` and Gleam's `!` are never captured by
  -- their queries, so there is nothing to read.
  { kinds = { "operator", "keyword.operator" }, words = { "not" }, meaning = "negation" },
  { kinds = { "function" }, words = { "not" }, langs = { haskell = true }, meaning = "negation" }, -- a Prelude function
  { kinds = { "keyword.conditional", "keyword" }, words = { "unless" }, meaning = "negation" }, -- Elixir's is a keyword
  {
    kinds = { "operator" },
    words = { "!" },
    meaning = "negation",
    parents = {
      "unary_expression", -- C, C++, Go, Rust, JavaScript, TypeScript, Java, Odin, Bash's `[ ! -f ]`
      "unary", -- Ruby
      "unary_operator", -- Elixir
      "prefix_expression", -- Kotlin, Swift
      "prefix_unary_expression", -- C#
      "unary_op_expression", -- PHP
      "negated_command", -- Bash's `! cmd`
    },
  },
}

-- What the lexicon can add, and the meaning each is drawn as. Negation is control,
-- made louder: it decides which way the flow goes, like the `if` it sits in.
M.ADDED = { failure = "failure", negation = "control" }

local function set(list)
  local out = {}
  for _, item in ipairs(list or {}) do
    out[item] = true
  end
  return out
end

-- Index: kind -> { words = set, patterns = list, langs = set|nil, meaning, parents = set|nil } entries.
local BY_KIND = {}
for _, entry in ipairs(M.LEXICON) do
  local words = set(entry.words)
  for _, kind in ipairs(entry.kinds) do
    BY_KIND[kind] = BY_KIND[kind] or {}
    table.insert(BY_KIND[kind], {
      words = words, patterns = entry.patterns or {}, langs = entry.langs,
      meaning = entry.meaning or "failure", parents = entry.parents and set(entry.parents),
    })
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

--- What the lexicon adds to `text` in this capture: "failure" or "negation" (see
--- ADDED), or nil when it has nothing to add to the capture's own. These are the
--- meanings no grammar marks on its own. `parent`, when given, returns the type of
--- the node's parent; it is only called for a word whose meaning depends on it, and a
--- word like that is left alone without it.
function M.refine(capture, text, lang, parent)
  if #text > MAX_WORD then
    return nil
  end
  local word = text:match("^[%w_]+::([%w_]+)$") or text -- C++ std::runtime_error, Rust ParseError::Empty
  for _, kind in ipairs(kinds_of(capture)) do
    for _, entry in ipairs(BY_KIND[kind] or {}) do
      if not entry.langs or entry.langs[lang] then
        if entry.words[word] then
          if not entry.parents or (parent and entry.parents[parent()]) then
            return entry.meaning
          end
        else
          for _, pattern in ipairs(entry.patterns) do
            if word:find(pattern) then
              return entry.meaning
            end
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
