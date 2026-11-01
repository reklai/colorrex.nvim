-- Decides what each of a theme's colors means in an editor: its roles.
--
-- It keeps two promises that pull against each
-- other: FAITHFUL (use the theme's colors, keep its hues) and UNIQUE (tell
-- tokens apart). The rules, in order:
--
--   1. fg and bg are the theme's and are never altered.
--   2. Every syntax color comes from an ANSI slot. Nothing is invented.
--   3. A color too faint to read moves in lightness only, the minimum needed.
--   4. Two roles that would look the same take another of the theme's colors.
--   5. Roles the palette cannot separate differ by weight or slant instead.
--   6. The theme's casting then decides which of these colors plays which role.
--
-- Every step that changes something leaves a note and records where the color
-- came from, so `:ColorRex explain` can show why any color on screen is what it is.
local Casting = require("color-rex.compiler.casting")
local Color = require("color-rex.color")

local M = {}

M.DISTINCT = 0.04 -- below this OKLab distance two tokens read as one color
M.COMMENT_FLOOR = 2.5 -- comments may recede further than code, but stay legible
M.MIN_CHROMA = 0.03 -- below this a slot is a grey, however it is named

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

local POOL = { 1, 2, 3, 4, 5, 6, 9, 10, 11, 12, 13, 14 }

-- Tried in order for roles that collide; a role keeps its first free rung.
local LADDER = {
  { bold = true },
  { italic = true },
  { bold = true, italic = true },
  { underline = true },
  { bold = true, underline = true },
}

function M.same_style(x, y)
  return not x.bold == not y.bold and not x.italic == not y.italic and not x.underline == not y.underline
end

--- A slot's color, made readable, with its note if it had to move.
local function candidate(theme, slot, floor)
  local source = theme.ansi[slot]
  local hex = Color.lift(source, theme.bg, floor)
  return {
    hex = hex,
    slot = slot,
    source = "ansi " .. slot,
    from = hex ~= source and source or nil,
  }
end

local function note_lift(notes, name, pick, bg)
  if pick.from then
    notes[#notes + 1] = {
      code = "faithful.lifted",
      role = name,
      message = ("%s lifted from %s (%.1f:1) to %s (%.1f:1)"):format(
        name, pick.from, Color.contrast(pick.from, bg), pick.hex, Color.contrast(pick.hex, bg)),
    }
  end
end

--- The closest pair among current picks, and how close it is.
local function closest(picks, names)
  local gap, first, second = math.huge, nil, nil
  for i = 1, #names do
    for j = i + 1, #names do
      local d = Color.distance(picks[names[i]].hex, picks[names[j]].hex)
      if d < gap then
        gap, first, second = d, names[i], names[j]
      end
    end
  end
  return gap, first, second
end

--- How close `hex` would sit to everything except `role`.
local function nearest_other(picks, names, role, hex)
  local gap = math.huge
  for _, name in ipairs(names) do
    if name ~= role then
      gap = math.min(gap, Color.distance(hex, picks[name].hex))
    end
  end
  return gap
end

local function assign_syntax(theme, floor, notes)
  local names, picks, pool = {}, {}, {}
  for _, slot in ipairs(POOL) do
    if Color.chroma(theme.ansi[slot]) >= M.MIN_CHROMA then
      pool[#pool + 1] = candidate(theme, slot, floor)
    end
  end

  -- Start every role on its natural slot; a role whose first slot is a grey
  -- (Solarized fills the bright slots with greys) starts on its partner.
  for _, role in ipairs(M.SYNTAX) do
    names[#names + 1] = role.name
    local first = role.slots[1]
    local slot = first
    if Color.chroma(theme.ansi[first]) < M.MIN_CHROMA
      and Color.chroma(theme.ansi[role.slots[2]]) >= M.MIN_CHROMA then
      slot = role.slots[2]
    end
    picks[role.name] = candidate(theme, slot, floor)
  end

  -- Repair the closest pair until nothing collides or nothing helps. Each pass
  -- strictly widens the closest gap, so this terminates, and six roles bound it.
  for _ = 1, 12 do
    local gap, first, second = closest(picks, names)
    if gap >= M.DISTINCT then
      break
    end
    local best, best_role, best_gap = nil, nil, gap
    for _, role in ipairs({ second, first }) do
      for _, option in ipairs(pool) do
        local reach = nearest_other(picks, names, role, option.hex)
        if reach > best_gap + 1e-6 then
          best, best_role, best_gap = option, role, reach
        end
      end
    end
    if not best then
      break
    end
    notes[#notes + 1] = {
      code = "unique.reassigned",
      role = best_role,
      message = ("%s moved from ansi %d to ansi %d to stay distinct"):format(
        best_role, picks[best_role].slot, best.slot),
    }
    picks[best_role] = best
  end

  for _, name in ipairs(names) do
    note_lift(notes, name, picks[name], theme.bg)
  end
  return names, picks
end

--- Move the chosen colors between roles. Nothing about a color changes, so every
--- rule above still holds: this only decides who plays what.
local function cast(picks, arrangement)
  local chosen = {}
  for index, role in ipairs(Casting.ROLES) do
    chosen[index] = picks[role]
  end
  for index, role in ipairs(Casting.ROLES) do
    picks[role] = chosen[arrangement[index]]
  end
end

--- Give roles the palette could not separate different weight or slant.
local function assign_styles(names, picks, notes)
  local styles = { keyword = { italic = true } }
  for _, name in ipairs(names) do
    styles[name] = styles[name] or {}
  end
  for i = 1, #names do
    for j = i + 1, #names do
      local a, b = names[i], names[j]
      if Color.distance(picks[a].hex, picks[b].hex) < M.DISTINCT
        and M.same_style(styles[a], styles[b]) then
        for _, rung in ipairs(LADDER) do
          local free = true
          for _, other in ipairs(names) do
            if other ~= b and M.same_style(styles[other], rung)
              and Color.distance(picks[other].hex, picks[b].hex) < M.DISTINCT then
              free = false
            end
          end
          if free then
            styles[b] = rung
            notes[#notes + 1] = {
              code = "unique.style",
              role = b,
              message = ("%s shares a color with %s; separated by style"):format(b, a),
            }
            break
          end
        end
      end
    end
  end
  return styles
end

--- The comment color: the theme's bright black when it behaves like one.
local function assign_comment(theme, notes)
  local fg_contrast = Color.contrast(theme.fg, theme.bg)
  local floor = math.min(M.COMMENT_FLOOR, fg_contrast * 0.8)
  local source = theme.ansi[8]
  local contrast = Color.contrast(source, theme.bg)
  if contrast >= floor and contrast < fg_contrast then
    return { hex = source, source = "ansi 8" }
  end
  -- Too faint, or (as in Solarized) louder than the code it annotates.
  local mixed = Color.mix(theme.bg, theme.fg, 0.55)
  local hex = Color.lift(mixed, theme.bg, floor)
  -- With fg and bg at equal luminance but different hues, a blend of the two can
  -- out-contrast the foreground itself. Then fg is as quiet as this theme gets.
  if Color.contrast(hex, theme.bg) > fg_contrast then
    hex = theme.fg
  end
  notes[#notes + 1] = {
    code = "faithful.comment",
    role = "comment",
    message = ("ansi 8 %s is %.1f:1 against normal text at %.1f:1; comment derived from fg"):format(
      source, contrast, fg_contrast),
  }
  return { hex = hex, source = "fg over bg" }
end

--- The accent: the one color a theme chose that is not in its ANSI table. When
--- the cursor is not a color of its own (half of all themes), bright magenta
--- takes over, which also brings that slot to the screen.
local function assign_accent(theme, picks, floor, notes)
  local cursor = theme.cursor
  if cursor and Color.chroma(cursor) >= M.MIN_CHROMA and Color.distance(cursor, theme.fg) >= M.DISTINCT then
    local hex = Color.lift(cursor, theme.bg, floor)
    return { hex = hex, source = "cursor", from = hex ~= cursor and cursor or nil }
  end
  notes[#notes + 1] = {
    code = "unique.accent",
    role = "accent",
    message = "the theme's cursor is not a color of its own; accent comes from the palette",
  }
  if Color.chroma(theme.ansi[13]) >= M.MIN_CHROMA then
    return candidate(theme, 13, floor)
  end
  return { hex = picks.func.hex, source = picks.func.source, from = picks.func.from }
end

--- Solve a filled theme. `arrangement` is its casting.
---   roles[name] = { hex, source, from? }, plus .styles and .notes
function M.solve(theme, opts, arrangement)
  local floor = opts.contrast
  local notes = {}
  local names, picks = assign_syntax(theme, floor, notes)
  cast(picks, arrangement)
  local styles = assign_styles(names, picks, notes)
  local bg, fg = theme.bg, theme.fg

  local roles = {
    base = { hex = bg, source = "bg" },
    fg = { hex = fg, source = "fg" },
    comment = assign_comment(theme, notes),
    accent = assign_accent(theme, picks, floor, notes),
  }
  note_lift(notes, "accent", roles.accent, bg)
  for _, name in ipairs(names) do
    roles[name] = picks[name]
  end

  -- Normal slots carry syntax, so the bright ones carry meaning. Together they
  -- put all twelve chromatic slots on screen: a change to any of them shows.
  local function state(name, slot, partner)
    if Color.chroma(theme.ansi[slot]) < M.MIN_CHROMA and Color.chroma(theme.ansi[partner]) >= M.MIN_CHROMA then
      slot = partner
    end
    roles[name] = candidate(theme, slot, floor)
    note_lift(notes, name, roles[name], theme.bg)
  end
  state("error", 1, 9)
  state("warn", 3, 11)
  state("ok", 10, 2)
  state("info", 14, 6)
  state("hint", 12, 4)
  state("special", 9, 1)
  state("preproc", 13, 5)
  state("constant", 1, 9)

  local function surface(name, over, t)
    roles[name] = { hex = Color.mix(bg, over, t), source = ("%s over bg at %d%%"):format(
      over == fg and "fg" or "color", math.floor(t * 100 + 0.5)) }
  end
  surface("cursorline", fg, 0.05)
  surface("element", fg, 0.08)
  surface("statusline", fg, 0.10)
  surface("subtle", fg, 0.14)
  surface("visual", fg, 0.18)
  surface("border", fg, 0.24)
  surface("border_strong", fg, 0.40)
  surface("search", roles.warn.hex, 0.28)
  surface("diff_add", roles.ok.hex, 0.16)
  surface("diff_delete", roles.error.hex, 0.16)
  surface("diff_change", roles.warn.hex, 0.14)
  surface("diff_text", roles.warn.hex, 0.30)
  surface("accent_soft", roles.accent.hex, 0.18)

  local fg_contrast = Color.contrast(fg, bg)
  local muted = Color.lift(Color.mix(bg, fg, 0.72), bg, math.min(floor, fg_contrast))
  roles.muted = { hex = muted, source = "fg over bg at 72%" }

  --- Text that sits on a filled color: whichever of the theme's two text
  --- colors reads best on it.
  local function on(name, fill)
    local hex = Color.contrast(bg, fill) >= Color.contrast(fg, fill) and bg or fg
    roles[name] = { hex = hex, source = hex == bg and "bg" or "fg" }
  end
  on("on_accent", roles.accent.hex)
  on("on_error", roles.error.hex)
  on("on_warn", roles.warn.hex)
  on("on_ok", roles.ok.hex)
  on("on_keyword", roles.keyword.hex)

  roles.styles = styles
  roles.notes = notes
  return roles
end

return M
