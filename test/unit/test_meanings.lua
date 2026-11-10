-- The lexicon on its own: what it adds to a capture, and what it leaves alone.
local T = require("harness")
local Meanings = require("colorrex.meanings")

local function parent(type)
  return function()
    return type
  end
end

T.test("negation: `not` and `unless` turn a condition around, in any language", function()
  T.eq(Meanings.refine("@keyword.operator", "not", "python"), "negation")
  T.eq(Meanings.refine("@keyword.operator", "not", "lua"), "negation")
  T.eq(Meanings.refine("@operator", "not", "lua"), "negation")
  T.eq(Meanings.refine("@keyword.conditional", "unless", "ruby"), "negation")
  -- Other conditionals are control, as the capture already says.
  T.eq(Meanings.refine("@keyword.conditional", "if", "ruby"), nil)
end)

T.test("negation: `!` only where it is a prefix", function()
  for lang, node in pairs({ go = "unary_expression", rust = "unary_expression", ruby = "unary", php = "unary_op_expression" }) do
    T.eq(Meanings.refine("@operator", "!", lang, parent(node)), "negation", lang)
  end
  -- Rust's `panic!` and `-> !`, and Zig's `!T` (and `!ok`).
  for lang, node in pairs({ rust = "macro_invocation", zig = "error_union_type" }) do
    T.eq(Meanings.refine("@operator", "!", lang, parent(node)), nil, lang)
  end
  -- TypeScript's `foo!` says foo is there, which is failure's question, not negation.
  T.eq(Meanings.refine("@operator", "!", "typescript", parent("non_null_expression")), "failure")
  T.eq(Meanings.refine("@operator", "!", "rust", parent("never_type")), nil)
  -- Without a parent to ask, `!` is not guessed at.
  T.eq(Meanings.refine("@operator", "!", "go"), nil)
  T.eq(Meanings.refine("@operator", "!=", "go", parent("binary_expression")), nil)
end)

T.test("negation: the parent is only asked about words that need it", function()
  local asked = 0
  local function counting()
    asked = asked + 1
    return "unary_expression"
  end
  Meanings.refine("@operator", "+", "go", counting)
  Meanings.refine("@operator", "?", "rust", counting)
  Meanings.refine("@keyword.operator", "not", "python", counting)
  T.eq(asked, 0)
end)

T.test("lexicon: failure is still failure, and is never mistaken for negation", function()
  T.eq(Meanings.refine("@constant.builtin", "nil", "lua"), "failure")
  T.eq(Meanings.refine("@operator", "?", "rust"), "failure")
  T.eq(Meanings.refine("@variable", "parseErr", "go"), "failure")
  T.eq(Meanings.refine("@string", "not", "python"), nil)
end)

T.test("lexicon: what fails if something is missing, and what steps around it, is failure", function()
  -- Asserting a value is there.
  T.eq(Meanings.refine("@function.method.call", "unwrap", "rust"), "failure")
  T.eq(Meanings.refine("@function.call", "expect", "rust"), "failure")
  T.eq(Meanings.refine("@operator", "!!", "kotlin"), "failure")
  for lang, node in pairs({ swift = "postfix_expression", c_sharp = "postfix_unary_expression", tsx = "non_null_expression" }) do
    T.eq(Meanings.refine("@operator", "!", lang, parent(node)), "failure", lang)
  end
  -- Handling one that is not, as `orelse` does.
  T.eq(Meanings.refine("@operator", "??", "typescript"), "failure")
  T.eq(Meanings.refine("@keyword.conditional", "??", "php"), "failure")
  T.eq(Meanings.refine("@punctuation.delimiter", "?.", "javascript"), "failure")
  T.eq(Meanings.refine("@operator", "?.", "kotlin"), "failure")
  T.eq(Meanings.refine("@operator", "?:", "kotlin"), "failure")
  T.eq(Meanings.refine("@function.call", "unwrap_or", "rust"), "failure")
  T.eq(Meanings.refine("@operator", "?", "swift", parent("navigation_expression")), "failure")
  -- Not the `?` of a type, not a test's `expect`, and not every delimiter.
  T.eq(Meanings.refine("@operator", "?", "swift", parent("optional_type")), nil)
  T.eq(Meanings.refine("@operator", "?", "c_sharp", parent("nullable_type")), nil)
  T.eq(Meanings.refine("@function.call", "expect", "javascript"), nil)
  T.eq(Meanings.refine("@punctuation.delimiter", ".", "typescript"), nil)
end)

T.test("lexicon: Go's named errors are failure", function()
  T.eq(Meanings.refine("@variable", "ErrNotFound", "go"), "failure")
  T.eq(Meanings.refine("@variable", "errClosed", "go"), "failure")
  T.eq(Meanings.refine("@property", "ErrNoRows", "go"), "failure")
  T.eq(Meanings.refine("@property", "EOF", "go"), "failure")
  T.eq(Meanings.refine("@variable", "Errand", "go"), nil)
  T.eq(Meanings.refine("@variable", "ErrNotFound", "python"), nil)
  -- The field that holds one, as `e.Err`, and where it is declared.
  T.eq(Meanings.refine("@property", "Err", "go"), "failure")
  T.eq(Meanings.refine("@variable.member", "Err", "go"), "failure")
  -- A function named like one is drawn as the call it is, and read as one.
  T.eq(Meanings.refine("@function.call", "ErrLog", "go"), nil)
  T.eq(Meanings.refine("@function", "ErrLog", "go"), nil)
end)

T.test("lexicon: an exception stays failure, whatever a server calls it", function()
  -- rust-analyzer calls these macros, which would read as imports.
  T.eq(Meanings.refine("@keyword.exception", "assert_eq", "rust"), "failure")
  T.eq(Meanings.refine("@keyword.exception", "debug_assert_ne", "rust"), "failure")
  T.eq(Meanings.refine("@keyword.exception", "!", "rust"), "failure")
  T.eq(Meanings.refine("@keyword.exception", "finally", "python"), "failure")
end)

T.test("lexicon: a macro's `!` reads as its name does", function()
  local function before(text)
    return function()
      return text
    end
  end
  T.eq(Meanings.refine("@function.macro", "!", "rust", nil, before("todo")), "failure")
  T.eq(Meanings.refine("@function.macro", "!", "rust", nil, before("unreachable")), "failure")
  T.eq(Meanings.refine("@function.macro", "!", "rust", nil, before("std::unimplemented")), "failure")
  T.eq(Meanings.refine("@function.macro", "!", "rust", nil, before("println")), nil)
  T.eq(Meanings.refine("@function.macro", "!", "rust"), nil, "with nothing before it, nothing is guessed")
  T.eq(Meanings.refine("@function.macro", "!", "c", nil, before("todo")), nil)
end)

T.test("lexicon: unwrap and expect are failure where called, not as an attribute", function()
  T.eq(Meanings.refine("@function.call", "expect", "rust"), "failure")
  T.eq(Meanings.refine("@function.method.call", "unwrap", "rust"), "failure")
  T.eq(Meanings.refine("@function.macro", "expect", "rust"), nil) -- #[expect(dead_code)]
end)

T.test("lexicon: PHP's variables are read without their `$`", function()
  T.eq(Meanings.refine("@variable", "$err", "php"), "failure")
  T.eq(Meanings.refine("@variable", "$errors", "php"), nil)
end)

T.test("lexicon: the host reads only captures the lexicon could refine in that language", function()
  T.ok(Meanings.can_refine("@property", "go"), "Go's errors are fields too")
  T.ok(not Meanings.can_refine("@property", "lua"), "no other language's fields")
  T.ok(Meanings.can_refine("@punctuation.delimiter", "typescript"), "TypeScript files `?.` there")
  T.ok(not Meanings.can_refine("@punctuation.delimiter", "rust"), "no other language's `.` and `,`")
  T.ok(Meanings.can_refine("@operator", "python"))
  T.ok(Meanings.can_refine("@function.method.call", "rust"))
  T.ok(not Meanings.can_refine("@string", "go"))
  T.ok(Meanings.can_refine("@operator"), "a language it does not know is read in full")
end)

T.test("lexicon: a key in a pair is a field, and an atom is a value", function()
  T.eq(Meanings.refine("@string.special.symbol", "name", "ruby", parent("pair")), "key")
  T.eq(Meanings.refine("@string.special.symbol", "message: ", "elixir", parent("pair")), "key")
  T.eq(Meanings.refine("@string.special.symbol", ":sym", "ruby", parent("pair")), nil)
  T.eq(Meanings.refine("@string.special.symbol", ":ok", "elixir", parent("pair")), nil)
  T.eq(Meanings.refine("@string.special.symbol", "quoted", "ruby", parent("delimited_symbol")), nil)
  T.eq(Meanings.refine("@string.special.symbol", ":error", "elixir", parent("pair")), "failure")
  T.eq(Meanings.of_capture("@string.special.symbol"), "value")
  -- A key named error is a field in Ruby too; only BEAM's atoms are failure.
  T.eq(Meanings.refine("@string.special.symbol", "error", "ruby", parent("pair")), "key")
  T.eq(Meanings.refine("@string.special.symbol", "error: ", "elixir", parent("pair")), "key")
  T.eq(Meanings.refine("@string.special.symbol", ":error", "ruby"), nil)
  T.eq(Meanings.refine("@constant", "error", "erlang"), "failure")
end)

T.test("vocabulary: every color code is drawn in belongs to a meaning", function()
  -- A color with no meaning can carry anything, so nothing can say it carries the
  -- wrong thing. Comments, markup, diffs and links are not code.
  local Compiler, Config = require("colorrex.compiler"), require("colorrex.config")
  local specs = Compiler.compile(require("fixtures").theme(), Config.resolve()).group_specs
  local meant = { comment = true }
  for _, meaning in ipairs(Meanings.VOCABULARY) do
    meant[meaning.role] = true
  end
  local loose = {}
  for name, spec in pairs(specs) do
    local code = name:match("^@") and not name:match("^@markup") and not name:match("^@diff")
      and not name:match("^@comment") and name ~= "@string.special.url"
    for _ = 1, 10 do
      spec = spec.link and specs[spec.link] or spec
    end
    if code and spec.fg and not meant[spec.fg] then
      loose[#loose + 1] = ("%s (%s)"):format(name, spec.fg)
    end
  end
  table.sort(loose)
  T.eq(#loose, 0, table.concat(loose, ", "))
end)

T.test("lexicon: each added meaning is drawn as one the vocabulary has, in a group of its own", function()
  local Compiler, Config = require("colorrex.compiler"), require("colorrex.config")
  local compiled = Compiler.compile(require("fixtures").theme(), Config.resolve())
  local groups = {}
  for added, meaning in pairs(Meanings.ADDED) do
    T.ok(Meanings.ROLE[meaning], added .. " is drawn as " .. tostring(meaning))
    local group = Meanings.GROUP[added]
    T.eq(compiled.group_specs[group].fg, Meanings.ROLE[meaning], group)
    T.ok(not groups[group], group .. " is drawn for one meaning")
    groups[group] = true
  end
  T.eq(Meanings.GROUP.failure, "ColorRexFailure")
end)
