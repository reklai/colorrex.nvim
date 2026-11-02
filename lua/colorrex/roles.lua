-- Decides what each of a theme's colors means in an editor: its roles.
--
-- It keeps two promises that pull against each other: FAITHFUL (use the theme's
-- colors, keep its hues) and UNIQUE (tell tokens apart). The rules, in order:
--
--   1. fg and bg are the theme's and are never altered.
--   2. Every syntax color comes from an ANSI slot. Nothing is invented.
--   3. A color too faint to read moves in lightness only, the minimum needed.
--   4. Two roles that would look the same: the lesser one moves along its own slots,
--      else to the nearest color that stands apart. A repair changes all it must and
--      nothing else.
--   5. Colors stay on their ANSI convention unless that would hurt readability.
--   6. Roles the palette cannot separate differ by weight or slant instead.
--   7. A surface that text sits on gives way until the text is readable, and stops
--      while it can still be seen. Text in a float is lifted against the float.
--
-- Every step that changes something leaves a note and records where the color came
-- from, so `:ColorRex explain` can show why any color on screen is what it is.
local Casting = require("colorrex.roles.casting")
local Color = require("colorrex.color")

local M = {}

M.fingerprint = Casting.fingerprint

M.MIN_CHROMA = 0.03 -- below this a slot is a grey, however it is named

local COMMENT_FLOOR = 2.5 -- comments may recede further than code, but stay legible

-- Each syntax role's slots, most natural first. The bright partner is the one kept
-- in reserve; `number` holds bright yellow only until the roles above it are settled,
-- when it takes the constant's color if it can. This order is also precedence: a
-- collision moves the later role, because a theme is recognized by its keywords,
-- functions, strings and types far more than by its numbers and operators.
M.SYNTAX = {
  { name = "keyword", slots = { 5, 13 } },
  { name = "func", slots = { 4, 12 } },
  { name = "string", slots = { 2, 10 } },
  { name = "type", slots = { 3, 11 } },
  { name = "number", slots = { 11, 3, 9, 1 } },
  { name = "operator", slots = { 6, 14 } },
}

-- Rarer in code, so they are cast with SYNTAX but need not stay distinct from it.
M.SECONDARY = {
  { name = "preproc", slots = { 13, 5 } },
  { name = "special", slots = { 9, 1 } },
}

local CONSTANT_SLOTS = { 1, 9 }

-- Roles that keep their slot whatever the casting. With the two lists above these
-- put all twelve chromatic slots on screen, so a change to any of them shows.
M.PALETTE = {
  { name = "error", slots = { 1, 9 } },
  { name = "warn", slots = { 11, 3 } },
  { name = "ok", slots = { 10, 2 } },
  { name = "info", slots = { 14, 6 } },
  { name = "hint", slots = { 12, 4 } },
  { name = "constant", slots = CONSTANT_SLOTS },
}

-- Colors for surfaces: `over` mixed into the background. These are editor chrome,
-- which no terminal theme defines, so they derive from what it does define. A surface
-- with `least` lies under whatever syntax happens to be there, so it cannot choose its
-- text. It eases off instead, keeping at least that much contrast with the background,
-- because a selection you cannot see is worse than one that is hard to read through.
local SURFACES = {
  { name = "cursorline", over = "fg", mix = 0.05, least = 1.04 },
  { name = "element", over = "fg", mix = 0.08 },
  { name = "statusline", over = "fg", mix = 0.10 },
  { name = "subtle", over = "fg", mix = 0.14 },
  { name = "visual", over = "fg", mix = 0.18, least = 1.2 },
  { name = "border", over = "fg", mix = 0.24 },
  { name = "border_strong", over = "fg", mix = 0.40 },
  { name = "search", over = "warn", mix = 0.28 },
  { name = "diff_add", over = "ok", mix = 0.16, least = 1.1 },
  { name = "diff_delete", over = "error", mix = 0.16 },
  { name = "diff_change", over = "warn", mix = 0.14, least = 1.1 },
  { name = "diff_text", over = "warn", mix = 0.30 },
  { name = "accent_soft", over = "accent", mix = 0.18 },
}

-- How readable text must stay on those surfaces. Lower than `contrast`, which is
-- measured against the background: a surface cannot help costing some, and this is
-- what is left once a selection is only just visible. Comments may recede further, as
-- they do everywhere.
M.ON_SURFACE = { text = 2.5, comment = 2.25 }

local EASE_STEP = 0.01

local MUTED_ON = { "cursorline", "element" } -- the surfaces quiet text is used on

-- Roles used as text on a float, which sits on `element` and not on the background
-- they were made readable against. Each gets a `float_` role, lifted to suit.
local ON_FLOAT = { "accent", "error", "warn", "info", "hint", "ok" }

-- Roles used as a fill, which get an `on_` role for the text on top of them.
local FILLS = { "accent", "error", "warn", "ok", "keyword", "search", "diff_text" }

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

--- Whether the cursor is a color the theme chose. Half of all themes leave it as fg.
function M.own_cursor(theme)
  local cursor = theme.cursor
  return cursor ~= nil and Color.chroma(cursor) >= M.MIN_CHROMA and Color.distance(cursor, theme.fg) >= Color.DISTINCT
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
      message = ("%s lifted from %s (%.2f:1) to %s (%.2f:1)"):format(
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

--- What `name` would move to: the first of its own slots that stands apart from every
--- other role, else the nearest color that does. Its own slots come first because
--- distance only sees lightness and hue together: left to itself it takes bright blue
--- over a bright cyan, or a green right beside the strings.
local function alternative(picks, pool, name)
  local apart = {}
  for _, option in ipairs(pool) do
    if nearest_other(picks, name, option.hex) >= Color.DISTINCT then
      apart[option.slot] = option
    end
  end
  for _, role in ipairs(M.SYNTAX) do
    if role.name == name then
      for _, slot in ipairs(role.slots) do
        if apart[slot] then
          return apart[slot]
        end
      end
    end
  end
  local best, nearest = nil, math.huge
  for _, option in ipairs(pool) do
    local move = Color.distance(picks[name].hex, option.hex)
    if apart[option.slot] and move < nearest then
      best, nearest = option, move
    end
  end
  return best
end

--- The smallest change that separates two roles. The later one moves if it can. The
--- farthest color would separate them just as well, and turn operators red in a theme
--- with a perfectly good bright cyan.
local function smallest_repair(picks, pool, first, second)
  for _, name in ipairs({ second, first }) do
    local option = alternative(picks, pool, name)
    if option then
      return option, name
    end
  end
end

--- For a palette too small to separate everything: whichever move opens the widest
--- gap, as long as it opens one at all.
local function widest_repair(picks, pool, first, second, gap)
  local best, best_name, best_gap = nil, nil, gap
  for _, name in ipairs({ second, first }) do
    for _, option in ipairs(pool) do
      local reach = nearest_other(picks, name, option.hex)
      if reach > best_gap + 1e-6 then
        best, best_name, best_gap = option, name, reach
      end
    end
  end
  return best, best_name
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
    local best, best_name = smallest_repair(picks, pool, first, second)
    if not best then
      best, best_name = widest_repair(picks, pool, first, second, gap)
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

--- The syntax colors in the theme's own voice, and the voice. Nothing when the cursor
--- is not a color of its own, or when the row would cost the theme a readable role:
--- then the theme keeps the convention, which never does.
local function voiced_syntax(theme, floor)
  if not M.own_cursor(theme) or Color.chroma(theme.cursor) < Color.HUE_MIN_CHROMA then
    return nil
  end
  local voice = Casting.voice(theme.cursor, theme.ansi)
  if not voice then
    return nil
  end
  local picks = {}
  for _, role in ipairs(M.SYNTAX) do
    local slot = voice.roles[role.name]
    if not chromatic(theme, slot) then
      return nil
    end
    picks[role.name] = from_slot(theme, slot, floor)
  end
  if closest(picks) < Color.DISTINCT or Casting.leads_clash(picks) then
    return nil
  end
  return picks, voice
end

--- Numbers are constants, and authored colorschemes paint them alike. Left on bright
--- yellow they sit beside `type` in one hue, which reads as one color however far apart
--- two lightnesses measure. This follows every repair so it can never cost another role
--- its color: a palette too small for that keeps `number` where those left it. It comes
--- before casting, which only moves colors, so a recast theme has the same ones to move.
local function number_as_constant(theme, picks, floor)
  local constant = from_slot(theme, natural_slot(theme, CONSTANT_SLOTS), floor)
  if nearest_other(picks, "number", constant.hex) >= Color.DISTINCT then
    picks.number = constant
  end
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

--- The text that can land on a surface, and how readable each must stay. `fg` and the
--- syntax roles are all held to one target, unless the theme itself never reached it.
function M.surface_text(roles, bg)
  local text = {}
  local function add(name, target)
    text[#text + 1] = { name = name, hex = roles[name].hex, floor = math.min(target, Color.contrast(roles[name].hex, bg)) }
  end
  add("fg", M.ON_SURFACE.text)
  for _, role in ipairs(M.SYNTAX) do
    add(role.name, M.ON_SURFACE.text)
  end
  add("comment", M.ON_SURFACE.comment)
  return text
end

--- The first text that is too faint on `hex`, if any.
function M.unreadable_on(text, hex)
  for _, item in ipairs(text) do
    if Color.contrast(item.hex, hex) < item.floor then
      return item
    end
  end
  return nil
end

--- Whether a surface could ease off once more and still be seen.
function M.can_ease(bg, over, mix, least)
  return mix - EASE_STEP > 0 and Color.contrast(Color.mix(bg, over, mix - EASE_STEP), bg) >= least
end

--- As much of `surface` as the text on it allows. Returns the mix it settled on.
local function eased_mix(surface, over, bg, text)
  local mix = surface.mix
  while M.unreadable_on(text, Color.mix(bg, over, mix)) and M.can_ease(bg, over, mix, surface.least) do
    mix = mix - EASE_STEP
  end
  return mix
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
  if M.own_cursor(theme) then
    local cursor = theme.cursor
    local hex = Color.lift(cursor, theme.bg, floor)
    return { hex = hex, source = "cursor", from = hex ~= cursor and cursor or nil }
  end
  notes[#notes + 1] = {
    code = "unique.accent",
    message = "the theme's cursor is not a color of its own; accent comes from the palette",
  }
  return chromatic(theme, 13) and from_slot(theme, 13, floor) or roles.func
end

--- The color marking where chunks start. The cursor shows where you are, so it shows
--- where things are too. Red is left to errors, and a theme with no cursor color of its
--- own has functions, which already mark most of what a landmark does.
local function landmark_role(theme, roles)
  local voice = roles.accent.source == "cursor" and Color.chroma(theme.cursor) >= Color.HUE_MIN_CHROMA
    and Casting.voice(theme.cursor, theme.ansi)
  if voice and voice.name ~= "red" then
    return { hex = roles.accent.hex, source = "cursor" }
  end
  return { hex = roles.func.hex, source = "function" }
end

--- Solve a filled theme.
---   roles[name] = { hex, source, from? }; styles[syntax role] = { bold?, ... }
function M.solve(theme, opts)
  local floor, notes = opts.contrast, {}
  local bg, fg = theme.bg, theme.fg

  local voiced, voice
  if opts.force_unique then
    voiced, voice = voiced_syntax(theme, floor)
  end
  local roles = voiced or pick_syntax(theme, floor, notes)
  for _, role in ipairs(M.SECONDARY) do
    roles[role.name] = from_slot(theme, natural_slot(theme, role.slots), floor)
  end
  local casting = Casting.CONVENTION
  if voice then
    notes[#notes + 1] = {
      code = "unique.voice",
      message = ("the cursor sits nearest ansi %d, so keywords lead in the %s voice"):format(voice.anchor, voice.name),
    }
  else
    number_as_constant(theme, roles, floor)
    casting = Casting.cast(roles, roles.string.hex)
    if casting ~= Casting.CONVENTION then
      notes[#notes + 1] = {
        code = "faithful.recast",
        message = "roles moved off the ANSI convention, which would have read as one color",
      }
    end
  end
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
  roles.landmark = landmark_role(theme, roles)

  for _, role in ipairs(M.PALETTE) do
    roles[role.name] = from_slot(theme, natural_slot(theme, role.slots), floor)
    note_lift(notes, role.name, roles[role.name], bg)
  end
  if voice then
    roles.constant = roles.number -- numbers are constants, in every voice
  end

  local surface_text = M.surface_text(roles, bg)
  for _, surface in ipairs(SURFACES) do
    local over = roles[surface.over].hex
    local mix = surface.least and eased_mix(surface, over, bg, surface_text) or surface.mix
    roles[surface.name] = {
      hex = Color.mix(bg, over, mix),
      source = ("%s over bg at %d%%"):format(surface.over, math.floor(mix * 100 + 0.5)),
      over = over,
      mix = mix,
      least = surface.least,
    }
    if mix ~= surface.mix then
      notes[#notes + 1] = {
        code = "faithful.surface",
        message = ("%s eased from %d%% to %d%% so the text on it stays readable"):format(
          surface.name, math.floor(surface.mix * 100 + 0.5), math.floor(mix * 100 + 0.5)),
      }
    end
  end

  local function lifted_onto(name, surface, description)
    local hex = Color.lift(roles[name].hex, roles[surface].hex, floor)
    return { hex = hex, source = description, from = hex ~= roles[name].hex and roles[name].hex or nil }
  end
  for _, name in ipairs(ON_FLOAT) do
    roles["float_" .. name] = lifted_onto(name, "element", name .. " on a float")
  end
  roles.diff_deleted = lifted_onto("error", "diff_delete", "error on a deleted line")

  -- Lifted against both surfaces it is used on. On a mid-tone background they can sit
  -- either side of the point where lifting changes direction, so one lift undoes the
  -- other, and then only fg reads on both.
  local muted = Color.mix(bg, fg, 0.72)
  local function muted_floor(surface)
    return math.min(floor, Color.contrast(fg, roles[surface].hex))
  end
  for _, surface in ipairs(MUTED_ON) do
    muted = Color.lift(muted, roles[surface].hex, muted_floor(surface))
  end
  for _, surface in ipairs(MUTED_ON) do
    if Color.contrast(muted, roles[surface].hex) < muted_floor(surface) then
      muted = fg
    end
  end
  roles.muted = { hex = muted, source = muted == fg and "fg" or "fg over bg at 72%" }

  for _, name in ipairs(FILLS) do
    local fill = roles[name].hex
    local on_bg = Color.contrast(bg, fill) >= Color.contrast(fg, fill)
    roles["on_" .. name] = { hex = on_bg and bg or fg, source = on_bg and "bg" or "fg" }
  end

  return { roles = roles, styles = styles, notes = notes, casting = casting, voice = voice and voice.name }
end

return M
