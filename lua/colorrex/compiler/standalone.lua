-- A compiled colorscheme as a Lua file that needs no plugin. Deterministic to the
-- byte: keys are sorted, so the same theme always produces the same file.
local M = {}

local function sorted_keys(t)
  local keys = {}
  for key in pairs(t) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  return keys
end

local function key_text(key)
  if type(key) == "number" then
    return ("[%d]"):format(key)
  end
  return key:match("^[%a_][%w_]*$") and key or ("[%q]"):format(key)
end

--- Lua source for what a compiled colorscheme holds: strings, booleans and tables.
local function value_text(value, indent)
  if type(value) == "string" then
    return ("%q"):format(value)
  end
  if type(value) == "boolean" then
    return tostring(value)
  end
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

--- A complete colorscheme, needing nothing else installed.
function M.source(colorscheme, name)
  return table.concat({
    "-- Compiled by colorrex.nvim. Standalone: it needs no plugin to load.",
    "local groups = " .. value_text(colorscheme.groups, ""),
    "local ansi = " .. value_text(colorscheme.filled.ansi, ""),
    "",
    'vim.cmd.highlight("clear")',
    ("vim.g.colors_name = %q"):format(name),
    ("vim.o.background = %q"):format(colorscheme.background),
    "vim.o.termguicolors = true",
    "for group, spec in pairs(groups) do",
    "  vim.api.nvim_set_hl(0, group, spec)",
    "end",
    "for slot = 0, 15 do",
    '  vim.g["terminal_color_" .. slot] = ansi[slot]',
    "end",
    "",
  }, "\n")
end

return M
