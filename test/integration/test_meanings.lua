-- Meanings, across languages: the same thing reads the same in every one of them.
--
-- Each snippet in test/support/snippets is ordinary code in one language. Its real
-- grammar and real highlights query run over it, then the lexicon, exactly as the
-- host draws them, and this checks what each word ends up meaning.
--
-- Neovim bundles the Lua and C parsers, so those always run. The others run where a
-- parser and its queries exist: an nvim-treesitter install, or COLORREX_PARSERS and
-- COLORREX_QUERIES pointing at a parser site and a queries runtime. A language with
-- neither is skipped and says so, never passed.
local T = require("harness")

local function add_path(path)
  if path and path ~= "" and vim.uv.fs_stat(vim.fs.normalize(path)) then
    vim.opt.runtimepath:prepend(vim.fs.normalize(path))
  end
end
add_path(vim.env.COLORREX_PARSERS)
add_path(vim.env.COLORREX_QUERIES)
add_path(vim.fn.stdpath("data") .. "/site")
add_path(vim.fn.stdpath("data") .. "/lazy/nvim-treesitter/runtime")

local Captures = require("captures")
local Meanings = require("colorrex.meanings")

local SNIPPETS = T.root .. "/test/support/snippets/"

-- For each language: what must read as failure, and what must not, though it looks
-- close. A word is listed once, by its first spelling in the snippet.
local EXPECT = {
  c = { failure = { "NULL", "errno", "perror", "abort", "assert" }, value = { "3", "EINVAL" } },
  cpp = { failure = { "nullptr", "throw", "try", "catch", "err" }, value = { "true", "3" } },
  c_sharp = { failure = { "ParseException", "Exception", "null", "throw", "try", "catch", "FormatException", "err", "finally" },
    value = { "true" } },
  elixir = { failure = { ":error", "rescue", "err", "ArgumentError", "raise", "ParseError", "nil" },
    value = { ":ok", "true" } },
  erlang = { failure = { "catch", "'EXIT'", "error", "undefined", "throw" }, value = { "ok", "true", "3" } },
  gleam = { failure = { "ParseError", "Error", "Nil", "assert", "panic", "todo" }, value = { "Ok", "3" } },
  go = { failure = { "error", "err", "nil", "Errorf", "panic" }, value = { "true", "3" } },
  haskell = { failure = { "ParseError", "Left", "Nothing", "error", "undefined" }, value = { "3" } },
  java = { failure = { "ParseException", "Exception", "throws", "null", "throw", "try", "catch", "NumberFormatException",
    "err", "finally" }, value = { "true" } },
  javascript = { failure = { "ParseError", "Error", "null", "undefined", "throw", "try", "catch", "err", "finally" },
    value = { "true", "NaN" } },
  kotlin = { failure = { "ParseException", "Exception", "null", "throw", "try", "catch", "err", "NumberFormatException",
    "error", "finally", "TODO" }, value = { "true" } },
  lua = { failure = { "nil", "err", "pcall", "error", "assert" }, value = { "true", "3" } },
  odin = { failure = { "err", "Parse_Error", "or_return", "nil", "panic" }, value = { "3" } },
  php = { failure = { "ParseException", "Exception", "null", "throw", "try", "catch", "ValueError", "err", "finally" },
    value = { "true" } },
  python = { failure = { "ParseError", "Exception", "None", "raise", "try", "except", "ValueError", "err", "finally" },
    value = { "True", "__name__", "3" } },
  ruby = { failure = { "ParseError", "StandardError", "raise", "nil", "rescue", "ArgumentError", "err", "fail", "ensure" },
    value = { "true" } },
  rust = { failure = { "ParseError", "None", "Err", "?", "panic!" }, value = { "Some", "Ok", "true", "3" } },
  swift = { failure = { "ParseError", "Error", "throws", "throw", "try", "catch", "err", "fatalError", "nil" },
    value = { "3" } },
  typescript = { failure = { "ParseError", "Error", "null", "undefined", "throw", "try", "catch", "err", "finally" },
    value = { "true", "NaN" } },
  tsx = { failure = { "ParseError", "Error", "null", "undefined", "throw", "try", "catch", "err", "finally" },
    value = { "true", "NaN" } },
  zig = { failure = { "ParseError", "error", "errdefer", "catch", "err", "null", "try", "orelse", "unreachable" },
    value = { "true", "0", "10" } },
}

local EXTENSION = {
  c = "c", cpp = "cpp", c_sharp = "cs", elixir = "ex", erlang = "erl", gleam = "gleam", go = "go", haskell = "hs",
  java = "java", javascript = "js", kotlin = "kt", lua = "lua", odin = "odin", php = "php", python = "py", ruby = "rb",
  rust = "rs", swift = "swift", typescript = "ts", tsx = "tsx", zig = "zig",
}

--- Each word's meaning, as the host draws it: the lexicon first, else the capture's.
local function meanings(lang)
  local text = table.concat(vim.fn.readfile(SNIPPETS .. lang .. "." .. EXTENSION[lang]), "\n")
  local words = Captures.words(text, lang)
  if not words then
    return nil
  end
  local out = {}
  for _, word in ipairs(words) do
    if out[word.text] == nil and word.capture then
      local capture = "@" .. word.capture
      local bare = word.text:gsub("^:+(%a)", "%1"):gsub(":$", "")
      local refined = Meanings.refine(capture, word.text, lang) or Meanings.refine(capture, bare, lang)
      out[word.text] = refined or Meanings.of_capture(capture) or false
    end
  end
  return out
end

local languages = {}
for lang in pairs(EXPECT) do
  languages[#languages + 1] = lang
end
table.sort(languages)

for _, lang in ipairs(languages) do
  T.test("meanings: " .. lang .. " reads failure as failure, and only failure", function()
    local found = meanings(lang)
    if not found then
      T.skip("no " .. lang .. " parser and highlights query here")
    end
    for _, word in ipairs(EXPECT[lang].failure) do
      T.eq(found[word], "failure", lang .. " " .. word)
    end
    for _, word in ipairs(EXPECT[lang].value) do
      T.ok(found[word] ~= nil, lang .. " snippet has no " .. word)
      T.ok(found[word] ~= "failure", lang .. " " .. word .. " is not failure")
    end
  end)
end

T.test("meanings: every language here reads failure in one color", function()
  -- The point of all of it: one role, whatever the language.
  local compiled = require("colorrex.compiler").compile(require("fixtures").theme(), require("colorrex.config").resolve())
  local failure = compiled.roles.failure.hex
  T.eq(compiled.groups.ColorRexFailure.fg, failure)
  T.eq(compiled.groups["@keyword.exception"].fg, failure)
  T.eq(compiled.groups.Exception.fg, failure)
end)

-- Negation, on real grammars: the word list names `!`'s parent node, so a grammar
-- that renames it would quietly lose it. Each case is code, and what each `!` or
-- `not` in it should come out as, in order.
local NEGATION = {
  go = { "package m\nfunc f() { if !ok && x != 1 { } }", { "negation" } },
  c = { "int f(void) { if (!ok) return !x; return a != b; }", { "negation", "negation" } },
  javascript = { "if (!ok) { x = !y; }", { "negation", "negation" } },
  typescript = { "if (!ok) { const z = foo!.bar; }", { "negation", false } },
  rust = { "fn f() -> ! { if !items.is_empty() { panic!(\"x\"); } }", { false, "negation", false } },
  zig = { "fn f() !void { if (!ok) return; }", { false, false } },
  lua = { "if not ok then return end", { "negation" } },
  python = { "if not ready and x is not None:\n  pass", { "negation", "negation" } },
}

for lang, case in pairs(NEGATION) do
  T.test("meanings: " .. lang .. " reads `!` and `not` as negation only where they negate", function()
    local ok, query = pcall(vim.treesitter.query.get, lang, "highlights")
    if not ok or not query or not pcall(vim.treesitter.language.add, lang) then
      T.skip("no " .. lang .. " parser and highlights query here")
    end
    local text, want = case[1], case[2]
    local tree = vim.treesitter.get_string_parser(text, lang):parse()[1]
    -- One verdict per token, as the host draws it: any capture of it that refines wins.
    local found, order = {}, {}
    for id, node in query:iter_captures(tree:root(), text, 0, -1) do
      local word = vim.treesitter.get_node_text(node, text)
      if word == "!" or word == "not" then
        local key = table.concat({ node:range() }, ":")
        if found[key] == nil then
          order[#order + 1] = { key = key, at = select(2, node:start()) + select(1, node:start()) * 1000 }
          found[key] = false
        end
        local meaning = Meanings.refine("@" .. query.captures[id], word, lang, function()
          return node:parent() and node:parent():type()
        end)
        found[key] = found[key] or meaning or false
      end
    end
    table.sort(order, function(a, b) return a.at < b.at end)
    local got = {}
    for index, item in ipairs(order) do
      got[index] = found[item.key]
    end
    T.eq(vim.inspect(got), vim.inspect(want))
  end)
end
