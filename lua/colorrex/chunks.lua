-- Chunks: the shape of code, from the syntax tree alone.
--
-- A reader scanning a file asks where each thing starts, and token colors do not
-- answer that: a call looks like a definition. So the first line of a chunk is a
-- landmark, whatever kind of chunk it is. In tests most chunks start at a call, and in
-- source most do not, so a rule about kinds of token would be wrong in one or the other.
--
-- This knows no languages. A chunk is a node that starts its own line and runs
-- MIN_LINES or more, outermost at that position, and not the body of another node, and
-- only the outer MAX_DEPTH levels count. A landmark has to have a name that fits on its
-- line, and grammars agree on the fields that hold one, so `if` and `for` drop out with
-- no list of keywords. Pure: it takes a node and a way to read a line, so it runs under
-- plain LuaJIT with stand-ins.
local M = {}

M.MIN_LINES = 5
M.MAX_DEPTH = 1

local NAMES = { "name", "key", "function" } -- the fields grammars keep a name in

--- `node`, if it fits on `row`.
local function on_row(node, row)
  local start_row, _, end_row = node:range()
  return start_row == row and end_row == row and node or nil
end

--- What this node names, if it names anything on `row`.
local function name_of(node, row)
  for _, field in ipairs(NAMES) do
    local found = node:field(field)[1]
    if found then
      return on_row(found, row)
    end
  end
  local declarator = node:field("declarator")[1] -- C and C++ nest the name in these
  if declarator then
    return declarator:field("declarator")[1] and name_of(declarator, row) or on_row(declarator, row)
  end
  if node:field("condition")[1] then
    return nil -- control flow is the shape inside a chunk, not a chunk of its own
  end
  local first = node:named_child(0)
  if first and select(1, first:range()) == row then
    return name_of(first, row)
  end
  return nil
end

--- The landmarks on rows `first` through `last`, keyed by row, each a node's range:
--- { start_col, end_row, end_col }. `line(row)` returns the text of a row.
function M.landmarks(root, first, last, line)
  local marks = {}
  local function walk(node, opened_at, depth, body)
    local start_row, start_col, end_row = node:range()
    local here = start_row .. ":" .. start_col
    local indent = #(line(start_row) or ""):match("^%s*")
    local is_chunk = node:named() and node ~= body and end_row - start_row + 1 >= M.MIN_LINES
      and start_col == indent and here ~= opened_at
      and not node:field("definition")[1] -- a decorator wraps a chunk, and is not one
    if is_chunk and start_row >= first and start_row <= last then
      local name = name_of(node, start_row)
      if name then
        local row, col, stop_row, stop_col = name:range()
        marks[row] = marks[row] or { col, stop_row, stop_col }
      end
    end
    if depth + (is_chunk and 1 or 0) > M.MAX_DEPTH then
      return
    end
    local own_body = node:field("body")[1] -- once here: asking per child is quadratic
    for child in node:iter_children() do
      local child_start, _, child_end = child:range()
      if child_end >= first and child_start <= last then
        -- A body starts where its first statement does, and that is not a repeat.
        walk(child, node == body and opened_at or here, depth + (is_chunk and 1 or 0), own_body)
      end
    end
  end
  for child in root:iter_children() do
    local child_start, _, child_end = child:range()
    if child_end >= first and child_start <= last then
      walk(child, "", 0)
    end
  end
  return marks
end

return M
