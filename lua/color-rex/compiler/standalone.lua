-- A compiled colorscheme as a Lua file that needs no plugin. Deterministic to the
-- byte: keys are sorted, so the same theme always produces the same file.
local M = {}

local function compare(a, b)
  if type(a) == type(b) then
    return a < b
  end
  return type(a) == "number" -- numeric keys sort first
end

local function sorted_keys(t)
  local keys = {}
  for key in pairs(t) do
    keys[#keys + 1] = key
  end
  table.sort(keys, compare)
  return keys
end

local function key_text(key)
  if type(key) == "string" and key:match("^[%a_][%w_]*$") then
    return key
  end
  return ("[%s]"):format(type(key) == "string" and ("%q"):format(key) or tostring(key))
end

local function value_text(value, indent)
  local kind = type(value)
  if kind == "string" then
    return ("%q"):format(value)
  end
  if kind == "number" or kind == "boolean" then
    return tostring(value)
  end
  assert(kind == "table", "cannot emit a " .. kind)
  local keys = sorted_keys(value)
  if #keys == 0 then
    return "{}"
  end
  local parts, inner = {}, indent .. "  "
  for _, key in ipairs(keys) do
    parts[#parts + 1] = ("%s%s = %s,"):format(inner, key_text(key), value_text(value[key], inner))
  end
  return "{\n" .. table.concat(parts, "\n") .. "\n" .. indent .. "}"
end

--- A complete, standalone colorscheme that needs nothing else installed.
function M.source(colorscheme, name)
  return table.concat({
    "-- Compiled by color-rex.lua. Standalone: it needs no plugin to load.",
    "local groups = " .. value_text(colorscheme.groups, ""),
    "local terminal_colors = " .. value_text(colorscheme.terminal_colors, ""),
    "",
    'vim.cmd.highlight("clear")',
    ("vim.g.colors_name = %q"):format(name),
    ("vim.o.background = %q"):format(colorscheme.background),
    "vim.o.termguicolors = true",
    "for group, spec in pairs(groups) do",
    "  vim.api.nvim_set_hl(0, group, spec)",
    "end",
    "for slot = 0, 15 do",
    '  vim.g["terminal_color_" .. slot] = terminal_colors[slot]',
    "end",
    "",
  }, "\n")
end

return M
