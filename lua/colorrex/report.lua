-- What the commands say. Pure: data in, text out, so every report can be judged
-- without Neovim. Each function returns a message and, when it is not routine, a
-- notification level.
local M = {}

--- How the colors reach Neovim, in the words a person would use for it.
function M.route(status)
  if status.route == "kitty" then
    return status.tmux and "one OSC 21 request, through tmux's passthrough" or "one OSC 21 request"
  end
  if status.route == "xterm" then
    local cursor = status.borrowed and ("hidden colors from " .. status.borrowed)
      or "no cursor color (allow-passthrough on would carry it)"
    return (status.tmux and "one query per color, answered by tmux; " or "one query per color; ") .. cursor
  end
  return "not known yet"
end

function M.status(status)
  local last = status.last
  local summary = not last.reason and "not yet"
    or not last.outcome and ("%s: waiting for the terminal"):format(last.reason)
    or ("%s: %s (%s)"):format(last.reason, last.completeness, last.outcome)
  return table.concat({
    ("theme     %s, from %s (%s)"):format(status.background, status.source, status.completeness),
    ("id        %s, %s"):format(status.id,
      status.voice and ("%s voice"):format(status.voice) or ("casting %d"):format(status.casting)),
    ("colors    fg %s  bg %s  accent %s"):format(status.fg, status.bg, status.accent),
    ("last sync %s"):format(summary),
    ("route     %s"):format(M.route(status)),
    ("auto      %s"):format(status.auto and "on (focus, dark/light changes, and a watch while unfocused)" or "off (:ColorRex only)"),
    ("adjusted  %d (see :ColorRex check)"):format(status.adjustments),
  }, "\n")
end

--- The group this plugin defines for a name, if any. Neovim reads @comment.lua as
--- @comment when no such group exists, so this does the same.
local function defined(specs, name)
  while name do
    if specs[name] then
      return name
    end
    name = name:match("^(.+)%.[^.]+$")
  end
  return nil
end

--- Why a group is the color it is. `candidates` are names to try, in order: a
--- cursor can sit on several, and not all of them are ours.
function M.explain(colorscheme, candidates)
  if #candidates == 0 then
    return "nothing under the cursor; try :ColorRex explain Comment", "warn"
  end
  local specs = colorscheme.group_specs
  --- Whether a group, once its links are followed, gives text a color.
  local function colors(group)
    local spec = specs[group]
    for _ = 1, 10 do
      if not (spec and spec.link) then
        break
      end
      spec = specs[spec.link]
    end
    return spec ~= nil and (spec.fg or spec.bg or spec.sp) ~= nil
  end
  -- A group that colors nothing, such as a server's token with no opinion, leaves the
  -- color to the one beneath it. If none colors, the first is still the answer.
  local name, first
  for _, candidate in ipairs(candidates) do
    local found = defined(specs, candidate)
    first = first or found
    if found and not name and colors(found) then
      name = found
    end
  end
  name = name or first
  if not name then
    return ("%s is not a group colorrex defines"):format(candidates[1]), "warn"
  end
  local lines, seen = {}, {}
  while specs[name] and specs[name].link do
    if seen[name] then
      lines[#lines + 1] = ("%s links in a circle"):format(name)
      return table.concat(lines, "\n"), "warn"
    end
    seen[name] = true
    lines[#lines + 1] = ("%s links to %s"):format(name, specs[name].link)
    name = specs[name].link
  end
  if not specs[name] then
    lines[#lines + 1] = ("%s is not a group colorrex defines"):format(name)
    return table.concat(lines, "\n"), "warn"
  end
  local custom = colorscheme.custom and colorscheme.custom[name]
  lines[#lines + 1] = custom and ("%s, from your setup"):format(name) or name
  local described = false
  for _, key in ipairs({ "fg", "bg", "sp" }) do
    local role_name = specs[name][key]
    if role_name then
      described = true
      local role = colorscheme.roles[role_name]
      local origin = role.from and (", moved from %s to stay readable"):format(role.from) or ""
      lines[#lines + 1] = ("  %s %s  role %s, from %s%s"):format(key, role.hex, role_name, role.source, origin)
    end
  end
  if not described then
    lines[#lines + 1] = "  sets no color of its own"
  end
  return table.concat(lines, "\n")
end

local MAX_FAMILIES = 12 -- lines of strays shown; the count above them is always whole
local FAMILY_SIZE = 4 -- this many groups with one first word are shown as one line

--- The first word of a group's name: DevIcon and DevIconLua are both Dev's.
local function first_word(name)
  return name:match("^@?%a%l*") or name
end

local function shared_prefix(a, b)
  local length = 0
  while length < #a and length < #b and a:byte(length + 1) == b:byte(length + 1) do
    length = length + 1
  end
  return a:sub(1, length)
end

--- The colors on screen that are not the theme's, as lines. Groups a plugin names
--- alike are one line, so a plugin with a color for every file type is not a thousand.
local function stray_lines(strays)
  local groups, order = {}, {}
  for _, stray in ipairs(strays) do
    if not groups[stray.group] then
      groups[stray.group] = {}
      order[#order + 1] = stray.group
    end
    table.insert(groups[stray.group], stray)
  end
  local families, by_word = {}, {}
  for _, name in ipairs(order) do
    local word = first_word(name)
    local family = by_word[word]
    if not family then
      family = { names = {}, prefix = name }
      by_word[word] = family
      families[#families + 1] = family
    end
    family.names[#family.names + 1] = name
    family.prefix = shared_prefix(family.prefix, name)
  end

  local lines = { ("%d highlight%s from elsewhere wear%s colors that are not this theme's:"):format(
    #order, #order == 1 and "" or "s", #order == 1 and "s" or "") }
  local function describe(name)
    local parts = {}
    for _, stray in ipairs(groups[name]) do
      parts[#parts + 1] = ("%s %s (nearest role: %s)"):format(stray.key, stray.hex, stray.nearest)
    end
    return ("%s  %s"):format(name, table.concat(parts, ", "))
  end
  local shown = 0
  for _, family in ipairs(families) do
    if shown == MAX_FAMILIES then
      lines[#lines + 1] = "  and more; fix these and run it again"
      break
    end
    shown = shown + 1
    if #family.names >= FAMILY_SIZE then
      lines[#lines + 1] = ("  %s* (%d groups), such as %s"):format(family.prefix, #family.names, describe(family.names[1]))
    else
      for _, name in ipairs(family.names) do
        lines[#lines + 1] = "  " .. describe(name)
      end
    end
  end
  lines[#lines + 1] = "to give one the theme's color, name a role for it in setup:"
  local first = strays[1]
  lines[#lines + 1] = ("  groups = { %s = { %s = %q } }"):format(
    first.group:match("^[%a_][%w_]*$") and first.group or ("[%q]"):format(first.group), first.key, first.nearest)
  if by_word.lualine then -- its own themes are fixed colors, or derived ones; ours is in roles
    lines[#lines + 1] = "lualine follows the theme with: options = { theme = \"colorrex\" }"
  end
  return lines
end

--- The verdict on a colorscheme, with every adjustment that was needed. `strays` are
--- the colors on screen that are not the theme's, when there is a screen to look at.
function M.check(colorscheme, failures, strays)
  local lines = {}
  if #failures == 0 then
    lines[1] = "promises kept for this theme"
  end
  for _, failure in ipairs(failures) do
    lines[#lines + 1] = ("BROKEN %s: %s"):format(failure.code, failure.message)
  end
  if colorscheme.completeness ~= "full" then
    lines[#lines + 1] = "not the terminal's full theme yet; run :ColorRex"
  end
  for _, note in ipairs(colorscheme.notes) do
    lines[#lines + 1] = ("  %s: %s"):format(note.code, note.message)
  end
  if strays and #strays > 0 then
    for _, line in ipairs(stray_lines(strays)) do
      lines[#lines + 1] = line
    end
  elseif strays then
    lines[#lines + 1] = "every highlight on screen wears this theme's colors"
  end
  return table.concat(lines, "\n"), #failures > 0 and "error" or nil
end

return M
