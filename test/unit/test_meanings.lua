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
  -- TypeScript's `foo!`, Rust's `panic!` and `-> !`, and Zig's `!T` (and `!ok`).
  for lang, node in pairs({ typescript = "non_null_expression", rust = "macro_invocation", zig = "error_union_type" }) do
    T.eq(Meanings.refine("@operator", "!", lang, parent(node)), nil, lang)
  end
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

T.test("lexicon: each added meaning is drawn as one the vocabulary has", function()
  for added, meaning in pairs(Meanings.ADDED) do
    T.ok(Meanings.ROLE[meaning], added .. " is drawn as " .. tostring(meaning))
  end
end)
