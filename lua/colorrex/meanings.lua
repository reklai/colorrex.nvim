-- Meanings: what a reader looks for in code, in every language.
--
-- A theme defines colors and a grammar defines kinds of node; neither says what a
-- person needs to see. This is the vocabulary between them, the middle of the
-- compiler:
--
--   terminal theme --> roles --+--> highlights
--   any grammar ---> meanings -+
--   any server ----> meanings -+
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
--   3. A language server's token types, where a server knows what a grammar cannot.
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
  { name = "escape", role = "operator", asks = "what in this text is not literal?" },
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
  ["@string.special.path"] = "text",
  -- What a string or pattern holds that is not its own text: `\n`, `${id}`, `\d+`.
  ["@string.escape"] = "escape",
  ["@string.regexp"] = "escape",
  ["@string.special"] = "escape",
  ["@character.special"] = "escape",
  ["@punctuation.special"] = "escape",
  -- A symbol or atom names a constant, as `true` does: `:ok` is a value.
  ["@string.special.symbol"] = "value",
  ["@type"] = "type",
  ["@type.builtin"] = "type",
  ["@type.definition"] = "type",
  ["@constructor"] = "type",
  ["@module"] = "type",
  ["@module.builtin"] = "type",
  ["@attribute"] = "type",
  ["@attribute.builtin"] = "type",
  -- A tag names a kind of element, as a type names a kind of value, and its attributes
  -- are its fields.
  ["@tag"] = "type",
  ["@tag.builtin"] = "type",
  ["@tag.attribute"] = "field",
  ["@tag.delimiter"] = "quiet",
  ["@keyword.import"] = "boundary",
  ["@keyword.directive"] = "boundary",
  ["@keyword.directive.define"] = "boundary",
  ["@function.macro"] = "boundary",
  ["@constant.macro"] = "boundary",
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
  -- A parameter is a name like any other: one you follow through the function. It reads
  -- the same where it is declared and where it is used, with a server or without one.
  ["@variable.parameter"] = "name",
  ["@variable.parameter.builtin"] = "quiet",
  ["@operator"] = "quiet",
  -- A word that works as an operator reads as its symbol does: `and` as `&&`.
  ["@keyword.operator"] = "quiet",
  ["@keyword.conditional.ternary"] = "quiet",
  ["@punctuation.delimiter"] = "quiet",
  ["@punctuation.bracket"] = "quiet",
}

-- Tier 3: what a language server's token adds. A server resolves names, which a
-- grammar cannot: it knows that `fmt.` is a package, that a name holds a function, that
-- `EINVAL` is a macro. Those token types speak. The rest only restate the
-- grammar in coarser words: to a server a constant, `console` and Lua's `io` are all just
-- variables. They have no opinion, and the grammar's meaning stands, so a word reads the
-- same with a server attached or without one.
M.TOKENS = {
  namespace = "type",
  type = "type",
  class = "type",
  struct = "type",
  interface = "type",
  enum = "type",
  typeParameter = "type",
  decorator = "type",
  ["function"] = "call",
  method = "call",
  macro = "boundary",
  enumMember = "value",
  property = "field",
}

-- The standard token types with no opinion. Each is named because Neovim links them
-- all to a capture by default, and that link would paint over the grammar. A parameter
-- is a name, which the grammar says too, and only the grammar sees it called: `cb(x)`.
M.SILENT_TOKENS = {
  "variable", "parameter", "keyword", "modifier", "string", "number", "regexp", "operator", "comment", "event",
}

-- The one token type that speaks in some languages only. clangd sends the code an `#if`
-- turned off as `comment`, which a grammar parses as live code, and sends nothing for a
-- real comment. That code reads as a comment.
M.INACTIVE = { token = "comment", langs = { c = true, cpp = true, objc = true, objcpp = true, cuda = true } }

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
  -- BEAM atoms: Erlang's error, undefined and 'EXIT', Elixir's :error. Only there: a
  -- Ruby symbol named error is a name like any other, and `{ error: 1 }` has a field.
  {
    kinds = { "constant", "string.special.symbol" },
    words = { "error", "undefined", "'EXIT'", ":error" },
    langs = { erlang = true, elixir = true },
  },
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
  -- What a grammar calls an exception stays failure, whatever a server calls it:
  -- rust-analyzer calls `panic!` and `assert_eq!` macros, name and `!` alike.
  { kinds = { "keyword.exception" }, patterns = { "." } },
  -- A macro's `!` reads as its name does, so `todo!` is one word, as `panic!` is.
  { kinds = { "function.macro" }, words = { "!" }, langs = { rust = true }, as_previous = true },

  -- Where something may be missing, as nil may be: what fails if it is, and what steps
  -- around it. `unwrap` and `!!` stop the program, as `panic` does; `??`, `?.` and
  -- `unwrap_or` handle it, as Zig's `orelse` and `catch` do. Only where they are called:
  -- `#[expect(dead_code)]` is an attribute.
  {
    kinds = { "function.call", "function.method" },
    words = { "unwrap", "expect", "unwrap_err", "expect_err", "unwrap_or", "unwrap_or_else", "unwrap_or_default" },
    langs = { rust = true },
  },
  { kinds = { "function" }, words = { "fromJust", "fromMaybe" }, langs = { haskell = true } },
  { kinds = { "operator", "keyword" }, words = { "??", "??=" } }, -- PHP files `??` as a keyword
  { kinds = { "operator" }, words = { "?.", "?->" } },
  -- JavaScript's grammar files `?.` with `.` and `,`, which nothing else here reads.
  { kinds = { "punctuation.delimiter" }, words = { "?." }, langs = { javascript = true, typescript = true, tsx = true } },
  { kinds = { "operator" }, words = { "!!", "?:" }, langs = { kotlin = true } },
  -- A postfix `!` says "this is here": TypeScript's `user!`, Swift's `a!`, C#'s `a!`.
  {
    kinds = { "operator" },
    words = { "!" },
    langs = { typescript = true, tsx = true, swift = true, c_sharp = true },
    parents = { "non_null_expression", "postfix_expression", "postfix_unary_expression" },
  },
  -- Swift's `a?.count` and C#'s `a?.Length`, but not the `?` of a type like `String?`.
  {
    kinds = { "operator" },
    words = { "?" },
    langs = { swift = true, c_sharp = true },
    parents = { "navigation_expression", "conditional_access_expression" },
  },
  -- Go names its errors: `ErrNotFound`, `errClosed`, `io.EOF`, `sql.ErrNoRows`, and the
  -- field that holds one, `e.Err`. A function is not an error: `ErrLog("x")` is a call.
  {
    kinds = { "variable", "property" },
    words = { "EOF", "Err" },
    patterns = { "^Err%u", "^err%u" },
    langs = { go = true },
  },

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

  -- Keys: Ruby's `{ name: 1 }` and Elixir's `[message: "bad"]` name a part of what they
  -- build, as `{ name: 1 }` does in JavaScript, so they read as fields. Their grammars
  -- call them symbols, like the atom `:ok`, which is a value; only an atom starts with a
  -- colon. Ruby's `:sym => 1` is an atom in a pair, and keeps its colon.
  {
    kinds = { "string.special.symbol" },
    patterns = { "^[^:]" },
    langs = { ruby = true, elixir = true },
    parents = { "pair" },
    meaning = "key",
  },
}

-- What the lexicon can add, and the meaning each is drawn as. Negation is control,
-- made louder: it decides which way the flow goes, like the `if` it sits in. A key is
-- a field.
M.ADDED = { failure = "failure", negation = "control", key = "field" }

-- The group each is drawn in, named after it: ColorRexFailure, ColorRexNegation.
M.GROUP = {}
for added in pairs(M.ADDED) do
  M.GROUP[added] = "ColorRex" .. added:sub(1, 1):upper() .. added:sub(2)
end

local function set(list)
  local out = {}
  for _, item in ipairs(list or {}) do
    out[item] = true
  end
  return out
end

-- Index: kind -> { words = set, patterns = list, langs = set|nil, meaning, parents = set|nil,
-- as_previous } entries.
local BY_KIND = {}
for _, entry in ipairs(M.LEXICON) do
  local words = set(entry.words)
  for _, kind in ipairs(entry.kinds) do
    BY_KIND[kind] = BY_KIND[kind] or {}
    table.insert(BY_KIND[kind], {
      words = words, patterns = entry.patterns or {}, langs = entry.langs,
      meaning = entry.meaning or "failure", parents = entry.parents and set(entry.parents),
      as_previous = entry.as_previous,
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

--- What the lexicon adds to `text` in this capture: "failure", "negation" or "key"
--- (see ADDED), or nil when it has nothing to add to the capture's own. These are the
--- meanings no grammar marks on its own. `capture` is the one the highlighter draws on
--- the word, since that is what the word reads as. `parent`, when given, returns the
--- type of the node's parent, and `previous` the text of the node just before it; each
--- is only called for a word whose meaning depends on it, and a word like that is left
--- alone without it.
function M.refine(capture, text, lang, parent, previous)
  if #text > MAX_WORD then
    return nil
  end
  -- C++ std::runtime_error, Rust ParseError::Empty, PHP's $err
  local word = text:match("^[%w_]+::([%w_]+)$") or text:match("^%$([%w_]+)$") or text
  local function placed(entry)
    return not entry.parents or (parent ~= nil and entry.parents[parent()] == true)
  end
  --- The entry's meaning here, or nil: an entry that reads as the word before it has
  --- none when that word has none.
  local function meaning_of(entry)
    if not entry.as_previous then
      return entry.meaning
    end
    local before = previous and previous()
    return before and M.refine(capture, before, lang)
  end
  for _, kind in ipairs(kinds_of(capture)) do
    for _, entry in ipairs(BY_KIND[kind] or {}) do
      if not entry.langs or entry.langs[lang] then
        local found
        if entry.words[word] then
          found = placed(entry) and meaning_of(entry)
        else
          for _, pattern in ipairs(entry.patterns) do
            if not found and word:find(pattern) and placed(entry) then
              found = meaning_of(entry)
            end
          end
        end
        if found then
          return found
        end
      end
    end
  end
  return nil
end

local readable = {} -- lang -> capture -> boolean, as can_refine answers

--- Whether the lexicon could say anything about a capture in a language, so a host can
--- skip the rest without reading their text. It is asked for every capture on screen.
function M.can_refine(capture, lang)
  local known = readable[lang or ""]
  if not known then
    known = {}
    readable[lang or ""] = known
  end
  local answer = known[capture]
  if answer == nil then
    answer = false
    for _, kind in ipairs(kinds_of(capture)) do
      for _, entry in ipairs(BY_KIND[kind] or {}) do
        answer = answer or not entry.langs or entry.langs[lang] == true
      end
    end
    known[capture] = answer
  end
  return answer
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
