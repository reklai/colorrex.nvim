-- Decides what each of a theme's colors means in an editor: its roles.
--
-- It keeps two promises that pull against each other: FAITHFUL (use the theme's
-- colors, keep its hues) and UNIQUE (tell tokens apart). The rules, in order:
--
--   1. fg and bg are the theme's and are never altered.
--   2. Every syntax color comes from an ANSI slot. Nothing is invented.
--   3. A color too faint to read moves in lightness only, the minimum needed.
--   4. Two roles that would look the same take another of the theme's colors.
--   5. The theme's casting decides which of these colors plays which role.
--   6. Roles the palette cannot separate differ by weight or slant instead.
--
-- Every step that changes something leaves a note and records where the color came
-- from, so `:ColorRex explain` can show why any color on screen is what it is.
local Casting = require("color-rex.roles.casting")
local Color = require("color-rex.color")

local M = {}

M.fingerprint = Casting.fingerprint

M.MIN_CHROMA = 0.03 -- below this a slot is a grey, however it is named

local COMMENT_FLOOR = 2.5 -- comments may recede further than code, but stay legible

-- Each syntax role's natural slots, preferred first. The bright partner is the
-- one kept in reserve; `number` prefers bright so it separates from `type`.
M.SYNTAX = {
  { name = "keyword", slots = { 5, 13 } },
  { name = "func", slots = { 4, 12 } },
  { name = "string", slots = { 2, 10 } },
  { name = "type", slots = { 3, 11 } },
  { name = "number", slots = { 11, 3 } },
  { name = "operator", slots = { 6, 14 } },
}

-- Rarer in code, so they are cast with SYNTAX but need not stay distinct from it.
M.SECONDARY = {
  { name = "preproc", slots = { 13, 5 } },
  { name = "special", slots = { 9, 1 } },
}

-- Roles that keep their slot whatever the casting. With the two lists above these
-- put all twelve chromatic slots on screen, so a change to any of them shows.
M.PALETTE = {
  { name = "error", slots = { 1, 9 } },
  { name = "warn", slots = { 3, 11 } },
  { name = "ok", slots = { 10, 2 } },
  { name = "info", slots = { 14, 6 } },
  { name = "hint", slots = { 12, 4 } },
  { name = "constant", slots = { 1, 9 } },
}

-- Colors for surfaces: `over` mixed into the background. These are editor chrome,
-- which no terminal theme defines, so they derive from what it does define.
local SURFACES = {
  { name = "cursorline", over = "fg", mix = 0.05 },
  { name = "element", over = "fg", mix = 0.08 },
  { name = "statusline", over = "fg", mix = 0.10 },
  { name = "subtle", over = "fg", mix = 0.14 },
  { name = "visual", over = "fg", mix = 0.18 },
  { name = "border", over = "fg", mix = 0.24 },
  { name = "border_strong", over = "fg", mix = 0.40 },
  { name = "search", over = "warn", mix = 0.28 },
  { name = "diff_add", over = "ok", mix = 0.16 },
  { name = "diff_delete", over = "error", mix = 0.16 },
  { name = "diff_change", over = "warn", mix = 0.14 },
  { name = "diff_text", over = "warn", mix = 0.30 },
  { name = "accent_soft", over = "accent", mix = 0.18 },
}

-- Roles used as a fill, which get an `on_` role for the text on top of them.
local FILLS = { "accent", "error", "warn", "ok", "keyword" }

local POOL = { 1, 2, 3, 4, 5, 6, 9, 10, 11, 12, 13, 14 } -- the chromatic slots

-- One style for each syntax role, so a free one always exists. Keywords start
-- italic, which is why the plain style can still go to whichever role comes next.
local PLAIN, ITALIC = {}, { italic = true }
local STYLES = {
  PLAIN,
  { bold = true },
  ITALIC,
  { bold = true, italic = true },
  { underline = true },
  { bold = true, underline = true },
}

function M.same_style(x, y)
  return not x.bold == not y.bold and not x.italic == not y.italic and not x.underline == not y.underline
end

--- The lowest contrast a comment may have: quieter than the text it annotates.
function M.comment_floor(fg_contrast)
  return math.min(COMMENT_FLOOR, fg_contrast * 0.8)
end

local function chromatic(theme, slot)
  return Color.chroma(theme.ansi[slot]) >= M.MIN_CHROMA
end

--- A slot's color, made readable. `from` records the original if it had to move.
local function from_slot(theme, slot, floor)
  local source = theme.ansi[slot]
  local hex = Color.lift(source, theme.bg, floor)
  return {
    hex = hex,
    slot = slot,
    source = "ansi " .. slot,
    from = hex ~= source and source or nil,
  }
end

--- A role's first slot, unless that is a grey and its partner is not. Solarized
--- fills its bright slots with greys.
local function natural_slot(theme, slots)
  if not chromatic(theme, slots[1]) and chromatic(theme, slots[2]) then
    return slots[2]
  end
  return slots[1]
end

local function note_lift(notes, name, role, bg)
  if role.from then
    notes[#notes + 1] = {
      code = "faithful.lifted",
      message = ("%s lifted from %s (%.1f:1) to %s (%.1f:1)"):format(
        name, role.from, Color.contrast(role.from, bg), role.hex, Color.contrast(role.hex, bg)),
    }
  end
end

--- The closest pair of syntax roles, and how close they are.
local function closest(picks)
  local gap, first, second = math.huge, nil, nil
  for i = 1, #M.SYNTAX do
    for j = i + 1, #M.SYNTAX do
      local a, b = M.SYNTAX[i].name, M.SYNTAX[j].name
      local distance = Color.distance(picks[a].hex, picks[b].hex)
      if distance < gap then
        gap, first, second = distance, a, b
      end
    end
  end
  return gap, first, second
end

--- How close `hex` would sit to every syntax role except `name`.
local function nearest_other(picks, name, hex)
  local gap = math.huge
  for _, role in ipairs(M.SYNTAX) do
    if role.name ~= name then
      gap = math.min(gap, Color.distance(hex, picks[role.name].hex))
    end
  end
  return gap
end

--- The theme's color for each syntax role, on its natural slot unless that makes
--- two roles look the same.
local function pick_syntax(theme, floor, notes)
  local picks = {}
  for _, role in ipairs(M.SYNTAX) do
    picks[role.name] = from_slot(theme, natural_slot(theme, role.slots), floor)
  end

  local pool = {}
  for _, slot in ipairs(POOL) do
    if chromatic(theme, slot) then
      pool[#pool + 1] = from_slot(theme, slot, floor)
    end
  end

  -- Repair the closest pair until nothing collides or nothing helps. A repair can
  -- only happen while one role can move further from the rest, and this is bounded
  -- regardless: a palette that keeps offering small gains is not worth more passes.
  for _ = 1, 12 do
    local gap, first, second = closest(picks)
    if gap >= Color.DISTINCT then
      break
    end
    local best, best_name, best_gap = nil, nil, gap
    for _, name in ipairs({ second, first }) do
      for _, option in ipairs(pool) do
        local reach = nearest_other(picks, name, option.hex)
        if reach > best_gap + 1e-6 then
          best, best_name, best_gap = option, name, reach
        end
      end
    end
    if not best then
      break
    end
    notes[#notes + 1] = {
      code = "unique.reassigned",
      message = ("ansi %d read like another color, so ansi %d took its place"):format(picks[best_name].slot, best.slot),
    }
    picks[best_name] = best
  end
  return picks
end

--- Give syntax roles the palette could not separate a different weight or slant.
local function assign_styles(picks, notes)
  local styles = { keyword = ITALIC }
  local function taken(style, name, upto)
    for index = 1, upto do
      local other = M.SYNTAX[index].name
      if M.same_style(styles[other], style) and Color.distance(picks[other].hex, picks[name].hex) < Color.DISTINCT then
        return true
      end
    end
    return false
  end
  for index = 2, #M.SYNTAX do
    local name = M.SYNTAX[index].name
    for _, style in ipairs(STYLES) do
      if not taken(style, name, index - 1) then
        styles[name] = style
        break
      end
    end
    if styles[name] ~= PLAIN then
      notes[#notes + 1] = {
        code = "unique.style",
        message = ("%s shares its color with another role; separated by style"):format(name),
      }
    end
  end
  return styles
end

--- The comment color: the theme's bright black when it behaves like one.
local function comment_role(theme, notes)
  local fg_contrast = Color.contrast(theme.fg, theme.bg)
  local floor = M.comment_floor(fg_contrast)
  local source = theme.ansi[8]
  local contrast = Color.contrast(source, theme.bg)
  if contrast >= floor and contrast < fg_contrast then
    return { hex = source, source = "ansi 8" }
  end
  -- Too faint, or (as in Solarized) louder than the code it annotates.
  local hex = Color.lift(Color.mix(theme.bg, theme.fg, 0.55), theme.bg, floor)
  -- With fg and bg at equal luminance but different hues, a blend of the two can
  -- out-contrast the foreground itself. Then fg is as quiet as this theme gets.
  if Color.contrast(hex, theme.bg) > fg_contrast then
    hex = theme.fg
  end
  notes[#notes + 1] = {
    code = "faithful.comment",
    message = ("ansi 8 %s is %.1f:1 against normal text at %.1f:1; comment derived from fg"):format(
      source, contrast, fg_contrast),
  }
  return { hex = hex, source = "fg over bg" }
end

--- The accent: the one color a theme chose that is not in its ANSI table. When the
--- cursor is not a color of its own (half of all themes), a palette color stands in.
local function accent_role(theme, roles, floor, notes)
  local cursor = theme.cursor
  if cursor and Color.chroma(cursor) >= M.MIN_CHROMA and Color.distance(cursor, theme.fg) >= Color.DISTINCT then
    local hex = Color.lift(cursor, theme.bg, floor)
    return { hex = hex, source = "cursor", from = hex ~= cursor and cursor or nil }
  end
  notes[#notes + 1] = {
    code = "unique.accent",
    message = "the theme's cursor is not a color of its own; accent comes from the palette",
  }
  return chromatic(theme, 13) and from_slot(theme, 13, floor) or roles.func
end

--- Solve a filled theme. `fingerprint` is what casts it.
---   roles[name] = { hex, source, from? }; styles[syntax role] = { bold?, ... }
function M.solve(theme, opts, fingerprint)
  local floor, notes = opts.contrast, {}
  local bg, fg = theme.bg, theme.fg

  local roles = pick_syntax(theme, floor, notes)
  for _, role in ipairs(M.SECONDARY) do
    roles[role.name] = from_slot(theme, natural_slot(theme, role.slots), floor)
  end
  local casting = Casting.cast(roles, roles.string.hex, opts.identity and fingerprint or nil)
  local styles = assign_styles(roles, notes)
  for _, name in ipairs(Casting.ROLES) do
    note_lift(notes, name, roles[name], bg)
  end
  note_lift(notes, "string", roles.string, bg)

  roles.base = { hex = bg, source = "bg" }
  roles.fg = { hex = fg, source = "fg" }
  roles.comment = comment_role(theme, notes)
  roles.accent = accent_role(theme, roles, floor, notes)
  note_lift(notes, "accent", roles.accent, bg)

  for _, role in ipairs(M.PALETTE) do
    roles[role.name] = from_slot(theme, natural_slot(theme, role.slots), floor)
    note_lift(notes, role.name, roles[role.name], bg)
  end

  for _, surface in ipairs(SURFACES) do
    roles[surface.name] = {
      hex = Color.mix(bg, roles[surface.over].hex, surface.mix),
      source = ("%s over bg at %d%%"):format(surface.over, math.floor(surface.mix * 100 + 0.5)),
    }
  end

  roles.muted = {
    hex = Color.lift(Color.mix(bg, fg, 0.72), bg, math.min(floor, Color.contrast(fg, bg))),
    source = "fg over bg at 72%",
  }

  for _, name in ipairs(FILLS) do
    local fill = roles[name].hex
    local on_bg = Color.contrast(bg, fill) >= Color.contrast(fg, fill)
    roles["on_" .. name] = { hex = on_bg and bg or fg, source = on_bg and "bg" or "fg" }
  end

  return { roles = roles, styles = styles, notes = notes, casting = casting }
end

return M
