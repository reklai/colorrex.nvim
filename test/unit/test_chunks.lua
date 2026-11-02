-- Chunks, against stand-ins for Treesitter nodes, so this runs with no Neovim. The
-- integration suite runs the same code on real parsers.
local T = require("harness")
local Chunks = require("colorrex.chunks")

--- A node: { type, start_row, start_col, end_row, end_col, fields?, children?, anon? }
local function node(spec)
  local self = {}
  local children = spec.children or {}
  local named = {}
  for _, child in ipairs(children) do
    if child:named() then
      named[#named + 1] = child
    end
  end
  function self:range() return spec[1], spec[2], spec[3], spec[4] end
  function self:named() return not spec.anon end
  function self:field(name) return { (spec.fields or {})[name] } end
  function self:named_child(index) return named[index + 1] end
  function self:iter_children()
    local index = 0
    return function()
      index = index + 1
      return children[index]
    end
  end
  return self
end

local function root(...)
  return node({ 0, 0, 100, 0, children = { ... } })
end

local function lines(indents)
  return function(row)
    return (" "):rep(indents[row] or 0) .. "x"
  end
end

local function name_at(row, col)
  return node({ row, col, row, col + 3 })
end

--- `function foo()` on `row`, running to `stop`.
local function definition(row, stop, indent, children)
  return node({ row, indent or 0, stop, 3, fields = { name = name_at(row, 9) }, children = children })
end

local function marks(tree, first, last, indents)
  return Chunks.landmarks(tree, first or 0, last or 100, lines(indents or {}))
end

T.test("chunks: a definition of five lines is a landmark, at its name", function()
  local found = marks(root(definition(2, 6)))
  T.eq(found[2][1], 9)
  T.eq(found[2][2], 2)
  T.eq(found[2][3], 12)
end)

T.test("chunks: four lines are not enough", function()
  T.eq(next(marks(root(definition(2, 5)))), nil)
end)

T.test("chunks: a call with a body is a landmark, at what it calls", function()
  local callee = name_at(0, 0)
  local call = node({ 0, 0, 9, 2, fields = { ["function"] = callee } })
  local statement = node({ 0, 0, 9, 2, children = { call } })
  T.ok(marks(root(statement))[0], "tests open at describe(...), not at a definition")
end)

T.test("chunks: control flow is not a landmark", function()
  local condition = node({ 3, 3, 3, 8, fields = { name = name_at(3, 3) } })
  local branch = node({ 3, 0, 9, 3, fields = { condition = condition }, children = { condition } })
  T.eq(next(marks(root(branch))), nil)
end)

T.test("chunks: a keyword with nothing to name is not a landmark", function()
  local body = node({ 3, 0, 9, 1, children = { node({ 3, 0, 3, 1, anon = true }) } })
  T.eq(next(marks(root(body))), nil)
end)

T.test("chunks: a name on another line does not count", function()
  local misplaced = node({ 2, 0, 9, 0, fields = { name = name_at(4, 2) } })
  T.eq(next(marks(root(misplaced))), nil)
end)

T.test("chunks: a decorator is not a chunk, so what it decorates keeps its level", function()
  local method = definition(5, 10, 2)
  local class = definition(3, 12, 0, { method })
  local decorated = node({ 2, 0, 12, 0, fields = { definition = class }, children = { class } })
  local found = marks(root(decorated), 0, 100, { [5] = 2 })
  T.ok(found[3], "the class")
  T.eq(found[2], nil)
  T.ok(found[5], "a decorated class still shows its methods")
end)

T.test("chunks: the outer two levels count, and the third does not", function()
  local third = definition(4, 9, 8)
  local second = definition(2, 10, 4, { third })
  local first = definition(0, 12, 0, { second })
  local found = marks(root(first), 0, 100, { [2] = 4, [4] = 8 })
  T.ok(found[0], "outermost")
  T.ok(found[2], "one in")
  T.eq(found[4], nil)
end)

T.test("chunks: wrappers at the same position are one chunk, not two levels", function()
  local third = definition(3, 9, 4)
  local inner = definition(0, 10, 0, { third })
  local wrapper = node({ 0, 0, 10, 0, fields = { declaration = inner }, children = { inner } })
  T.ok(marks(root(wrapper), 0, 100, { [3] = 4 })[3], "the export did not use up a level")
end)

T.test("chunks: something that starts partway along a line is not a chunk", function()
  T.eq(next(marks(root(definition(2, 9, 6)), 0, 100, { [2] = 0 })), nil)
end)

T.test("chunks: a body is not a chunk, so its first statement is not a name", function()
  -- In Lua and Python a function's body starts its own line, and runs as long as the
  -- function does. It is the inside of a chunk, not another one.
  local statement = node({ 3, 2, 3, 12, fields = { name = name_at(3, 8) } })
  local body = node({ 3, 2, 8, 5, children = { statement } })
  local fn = node({ 2, 0, 9, 3, fields = { name = name_at(2, 9), body = body }, children = { body } })
  local found = marks(root(fn), 0, 100, { [3] = 2 })
  T.ok(found[2], "the function")
  T.eq(found[3], nil)
end)

T.test("chunks: a body does not use up a level", function()
  local inner = definition(4, 8, 2)
  local body = node({ 3, 2, 8, 5, children = { inner } })
  local fn = node({ 2, 0, 9, 3, fields = { name = name_at(2, 9), body = body }, children = { body } })
  T.ok(marks(root(fn), 0, 100, { [3] = 2, [4] = 2 })[4], "a function inside a function is one level in")
end)

T.test("chunks: a name that runs over several lines is not a name", function()
  -- `const { a, b, c } = helpers()` written out one per line. Marking it would light up
  -- every line.
  local pattern = node({ 2, 6, 9, 1 })
  local declaration = node({ 2, 0, 9, 10, fields = { name = pattern } })
  T.eq(next(marks(root(declaration))), nil)
end)

T.test("chunks: only the rows asked for are looked at", function()
  local tree = root(definition(2, 8), definition(20, 26), definition(40, 46))
  local found = marks(tree, 18, 30)
  T.eq(found[2], nil)
  T.ok(found[20])
  T.eq(found[40], nil)
end)

T.test("chunks: a chunk opening above the screen still counts toward depth", function()
  local third = definition(14, 19, 8)
  local second = definition(12, 22, 4, { third })
  local first = definition(0, 40, 0, { second })
  local found = marks(root(first), 13, 18, { [12] = 4, [14] = 8 })
  T.eq(found[14], nil)
  T.eq(found[0], nil)
  T.eq(found[12], nil)
end)
