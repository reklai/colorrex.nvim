-- Strays: colors on screen that are not this theme's.
--
-- The compiler answers for the groups it defines. A plugin defines its own, and most
-- follow along by linking to one of ours. The rest carry a color their author picked,
-- the same in every theme, and nothing in the compiler can see them. So this reads the
-- highlights Neovim actually holds, as the host hands them over, and says which colors
-- came from somewhere else. It finds what a person would have to notice by eye, on
-- their own setup, with their own plugins.
--
-- A color is the theme's when a role or an ANSI slot has it, or when it is one of those
-- dimmed or shaded: a plugin that takes a color toward the background, or darkens it, is
-- still following the theme. Pure: tables in, tables out.
local Color = require("colorrex.color")

local M = {}

-- Families whose colors are decoration and nothing else, with names nobody can list
-- ahead of time: a file icon has one group for every kind of file. Each color takes the
-- nearest of the theme's own. `sentinel` is a group the family always defines, so asking
-- whether the family needs a look costs one lookup.
M.ADOPTED = {
  { family = "DevIcon", sentinel = "DevIconDefault" }, -- nvim-web-devicons, and lualine's copies of them
}

local BLEND_TOLERANCE = 2 -- in 8-bit RGB: a blend is rounded once per channel
local MIXED_LEAST = 0.1 -- a shade holds at least this much of the theme's color, or it is only black
local SHADES = { "#000000", "#ffffff" }

-- The roles to suggest for a stray, by where it is used. Text first names what the
-- word is; a fill names a surface code can lie under.
local TEXT_ROLES = {
  "fg", "muted", "comment", "accent", "keyword", "func", "string", "type", "failure", "operator", "property",
  "number", "preproc", "special", "error", "warn", "ok", "info", "hint",
}
local FILL_ROLES = {
  "base", "cursorline", "element", "statusline", "subtle", "visual", "border", "border_strong", "search",
  "accent_soft", "diff_add", "diff_change", "diff_delete", "accent", "error", "warn", "ok",
}

local function channels(hex)
  return tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16)
end

--- How far `hex` is from the straight line between two colors, in RGB, where a plugin
--- blends them, and how far along it sits: 0 at the first, 1 at the second. math.huge
--- when the two are the same color.
local function off_blend(hex, from, to)
  local pr, pg, pb = channels(hex)
  local ar, ag, ab = channels(from)
  local br, bg, bb = channels(to)
  local dr, dg, db = br - ar, bg - ag, bb - ab
  local length = dr * dr + dg * dg + db * db
  if length == 0 then
    return math.huge
  end
  local t = ((pr - ar) * dr + (pg - ag) * dg + (pb - ab) * db) / length
  t = t < 0 and 0 or (t > 1 and 1 or t)
  local xr, xg, xb = ar + t * dr - pr, ag + t * dg - pg, ab + t * db - pb
  return math.sqrt(xr * xr + xg * xg + xb * xb), t
end

local known = setmetatable({}, { __mode = "k" }) -- colorscheme -> what it holds, built once

--- The theme's colors: `set` of every hex a role or slot has, and `list` of them with a
--- role's name each, in a fixed order.
local function colors_of(colorscheme)
  local found = known[colorscheme]
  if found then
    return found
  end
  local set, list, names = {}, {}, {}
  local slotted, has_slot = {}, {} -- the colors code is written in: a role on an ANSI slot
  for name in pairs(colorscheme.roles) do
    names[#names + 1] = name
  end
  table.sort(names)
  for _, name in ipairs(names) do
    local role = colorscheme.roles[name]
    local hex = role.hex:lower()
    if not set[hex] then
      set[hex] = true
      list[#list + 1] = { hex = hex, name = name }
    end
    if role.slot and not has_slot[hex] then
      has_slot[hex] = true
      slotted[#slotted + 1] = hex
    end
  end
  local theme = colorscheme.filled
  for slot = 0, 15 do
    local hex = theme.ansi[slot]:lower()
    if not set[hex] then
      set[hex] = true
      list[#list + 1] = { hex = hex, name = "ansi " .. slot }
    end
  end
  for _, key in ipairs({ "fg", "bg", "cursor" }) do
    if theme[key] then
      set[theme[key]:lower()] = true
    end
  end
  found = { set = set, list = list, slotted = slotted, fg = theme.fg:lower(), bg = theme.bg:lower() }
  known[colorscheme] = found
  return found
end

--- Whether a color is the theme's: one it holds, or one it holds taken toward its
--- foreground or background, or toward black or white, which is how a plugin dims a color
--- or shades a surface. Black and white themselves are a mix of nothing.
function M.belongs(colorscheme, hex)
  local colors = colors_of(colorscheme)
  hex = hex:lower()
  if colors.set[hex] then
    return true
  end
  for _, color in ipairs(colors.list) do
    if off_blend(hex, colors.bg, color.hex) <= BLEND_TOLERANCE or off_blend(hex, colors.fg, color.hex) <= BLEND_TOLERANCE then
      return true
    end
    for _, shade in ipairs(SHADES) do
      local off, along = off_blend(hex, shade, color.hex)
      if off <= BLEND_TOLERANCE and along >= MIXED_LEAST then
        return true
      end
    end
  end
  return false
end

--- The role nearest a color, from the ones that suit where it is used.
local function nearest_role(colorscheme, hex, key)
  local best, nearest = nil, math.huge
  for _, name in ipairs(key == "bg" and FILL_ROLES or TEXT_ROLES) do
    local distance = Color.distance(hex, colorscheme.roles[name].hex)
    if distance < nearest then
      best, nearest = name, distance
    end
  end
  return best
end

--- A backdrop: what a plugin lays over the whole editor, blended, to darken it behind a
--- window. Its black is a shade of whatever is under it and not a color anyone chose, so
--- it is left as it shipped. Mason, lazy, snacks and fzf-lua each name theirs this way.
local function backdrop(name, group)
  return name:find("Backdrop$") ~= nil and group.fg == nil and group.bg ~= nil and group.bg:lower() == SHADES[1]
end

--- Every color in `live` that is not the theme's, sorted by group and then by key.
--- `live` is what Neovim holds: name -> { fg, bg, sp, link }, colors as "#rrggbb". A
--- group that links is judged where it leads. Each stray says where it is and the role
--- nearest it.
function M.find(colorscheme, live)
  local names = {}
  for name in pairs(live) do
    names[#names + 1] = name
  end
  table.sort(names)
  local out = {}
  for _, name in ipairs(names) do
    local group = live[name]
    if not group.link and not backdrop(name, group) then
      for _, key in ipairs({ "fg", "bg", "sp" }) do
        local hex = group[key]
        if hex and not M.belongs(colorscheme, hex) then
          out[#out + 1] = { group = name, key = key, hex = hex:lower(), nearest = nearest_role(colorscheme, hex, key) }
        end
      end
    end
  end
  return out
end

--- The theme's own color for a fixed one: the nearest in hue of the colors its code is
--- written in, so a blue icon stays blue in every theme. A grey takes the quiet text
--- color, and so does everything when the palette has no color at all.
function M.nearest_hue(colorscheme, hex)
  local roles = colorscheme.roles
  if Color.chroma(hex) < Color.HUE_MIN_CHROMA then
    return roles.muted.hex
  end
  local best, gap, distance = nil, math.huge, math.huge
  for _, own in ipairs(colors_of(colorscheme).slotted) do
    if Color.chroma(own) >= Color.HUE_MIN_CHROMA then
      local this_gap, this_distance = Color.hue_gap(hex, own), Color.distance(hex, own)
      if this_gap < gap - 1e-9 or (math.abs(this_gap - gap) <= 1e-9 and this_distance < distance) then
        best, gap, distance = own, this_gap, this_distance
      end
    end
  end
  return best or roles.muted.hex
end

--- Whether a group belongs to a family this adopts.
local function adopted(name)
  for _, entry in ipairs(M.ADOPTED) do
    if name:find(entry.family, 1, true) then
      return true
    end
  end
  return false
end

--- The text colors to change so the adopted families wear the theme: name -> hex. Only
--- a color that is not the theme's already moves, so running it twice changes nothing.
function M.adopt(colorscheme, live)
  local changes = {}
  for name, group in pairs(live) do
    if group.fg and not group.link and adopted(name) and not colors_of(colorscheme).set[group.fg:lower()] then
      changes[name] = M.nearest_hue(colorscheme, group.fg)
    end
  end
  return changes
end

--- Whether a family's sentinel says the family needs adopting: it wears a color, and
--- the theme does not have it.
function M.unadopted(colorscheme, hex)
  return hex ~= nil and not colors_of(colorscheme).set[hex:lower()]
end

return M
