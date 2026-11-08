-- Casting: which role each of a theme's colors plays.
--
-- No terminal theme says which color is a keyword. What it has is the ANSI
-- convention, which is the closest thing to what its author meant, so a theme keeps
-- that when it has nothing else to say. Keywords stay magenta and functions blue,
-- unless that would make the code hard to read: two syntax roles that look alike, or
-- keywords, functions and types, which sit side by side in all code, sharing a hue.
-- Then it moves as little as that takes.
--
-- So casting follows the palette, and only the palette. Two themes with the same
-- colors read the same in code, whatever their backgrounds, because they are the
-- same colors. A change too small to see moves nothing, and a family of themes stays
-- a family. Colors are never changed, only moved between roles, and strings and
-- comments stay where they are.
--
-- A theme that gave its cursor a color of its own has said something, though: it made
-- one decision the convention ignores. So that color takes the keywords, and the rest
-- follows one of six arrangements modeled on themes people recognize. This is its
-- voice. It is colorrex's own rule, not what the author meant: terminal themes do not
-- say that. Rules that respond smoothly cannot split palettes that are nearly identical,
-- so those stay alike, and differ in the accent instead.
local Color = require("colorrex.color")

local M = {}

M.ROLES = { "keyword", "func", "type", "failure", "operator", "preproc", "special" } -- the roles that move
M.CONVENTION = 1 -- the arrangement that moves nothing
M.SAME_HUE = 25 -- degrees apart, below which two colors read as one family

-- The six voices, in slots. `anchor` is the color a cursor has to sit nearest. Blue
-- leans on Nord, green on Solarized, cyan on Rose Pine, red on Monokai and Gruvbox, and
-- magenta is the convention. Yellow has no precedent. With red left to errors wherever
-- a row can spare it, operators take their keyword's bright partner. `failure` is the
-- color of nil and of everything that fails: whatever a voice gives it, nothing else
-- in code shares it, so in every language an eye learns where things can go wrong.
M.VOICES = {
  { name = "magenta", anchor = 5, roles = { keyword = 5, func = 4, string = 2, type = 3, failure = 1, operator = 6 } },
  { name = "red", anchor = 1, roles = { keyword = 1, func = 2, string = 3, type = 6, failure = 5, operator = 4 } },
  { name = "blue", anchor = 4, roles = { keyword = 4, func = 6, string = 2, type = 3, failure = 5, operator = 12 } },
  { name = "green", anchor = 2, roles = { keyword = 2, func = 4, string = 6, type = 3, failure = 5, operator = 10 } },
  { name = "yellow", anchor = 3, roles = { keyword = 3, func = 4, string = 2, type = 6, failure = 5, operator = 11 } },
  { name = "cyan", anchor = 6, roles = { keyword = 6, func = 5, string = 3, type = 4, failure = 2, operator = 14 } },
}

local LEADS = 3 -- the first three of ROLES are read side by side
local KEPT_DISTINCT = 5 -- the first five of ROLES must stay distinct; see Roles.SYNTAX

-- A role collision always matters more than a shared hue: at most 3 pairs of leads
-- can share one, so this keeps the two scores from ever trading against each other.
local COLLISION_COST = 10

local MODULUS, MULTIPLIER = 2147483647, 48271 -- stays exact in a double

--- A stable number for a theme's signature. Any change to the theme changes it.
function M.fingerprint(signature)
  local hash = 1
  for index = 1, #signature do
    hash = (hash * MULTIPLIER + signature:byte(index)) % MODULUS
  end
  for _ = 1, 4 do -- so that themes differing late in the signature still spread
    hash = (hash * MULTIPLIER + 1) % MODULUS
  end
  return hash
end

--- Whether an arrangement is an even permutation: reachable by an even number of
--- swaps.
local function even(arrangement)
  local inversions = 0
  for i = 1, #arrangement do
    for j = i + 1, #arrangement do
      if arrangement[i] > arrangement[j] then
        inversions = inversions + 1
      end
    end
  end
  return inversions % 2 == 0
end

local function permutations(items, size, out)
  if size == 0 then
    out[#out + 1] = { unpack(items) }
    return out
  end
  for index = 1, size do
    items[index], items[size] = items[size], items[index]
    permutations(items, size - 1, out)
    items[index], items[size] = items[size], items[index]
  end
  return out
end

local arrangements

--- Every arrangement. Each entry says, for each role in ROLES, which role's color it
--- takes. Only even permutations are kept, because two of them can never differ in
--- just two roles: that would be a single swap, which is odd. So any two arrangements
--- are at least three roles apart, by construction. The convention goes first.
--- Reordering this list recasts themes, so a test pins it. Built on first use: most
--- themes need no repair, and this takes over a millisecond.
function M.arrangements()
  if arrangements then
    return arrangements
  end
  local convention = {}
  for index = 1, #M.ROLES do
    convention[index] = index
  end
  arrangements = { convention }
  for _, candidate in ipairs(permutations({ unpack(convention) }, #convention, {})) do
    if even(candidate) and table.concat(candidate) ~= table.concat(convention) then
      arrangements[#arrangements + 1] = candidate
    end
  end
  return arrangements
end

function M.same_hue(x, y)
  return Color.chroma(x) >= Color.HUE_MIN_CHROMA and Color.chroma(y) >= Color.HUE_MIN_CHROMA
    and Color.hue_gap(x, y) < M.SAME_HUE
end

--- Whether this voice would blur roles read side by side: any two leads in one hue, or
--- types and failure, which share lines like `(n int, err error)`.
function M.blurs(picks)
  for i = 1, LEADS do
    for j = i + 1, LEADS do
      if M.same_hue(picks[M.ROLES[i]].hex, picks[M.ROLES[j]].hex) then
        return true
      end
    end
  end
  return M.same_hue(picks.type.hex, picks.failure.hex)
end

--- The voice whose anchor sits nearest `cursor` in hue. A palette without a usable
--- color at an anchor has no such voice, and one with no colors at all has none.
function M.voice(cursor, ansi)
  local best, nearest = nil, math.huge
  for _, voice in ipairs(M.VOICES) do
    local anchor = ansi[voice.anchor]
    if Color.chroma(anchor) >= Color.HUE_MIN_CHROMA then
      local gap = Color.hue_gap(cursor, anchor)
      if gap < nearest then
        best, nearest = voice, gap
      end
    end
  end
  return best
end

--- For each pair of colors, whether the eye would confuse them.
local function comparisons(colors, fixed)
  local family, alike, alike_fixed = {}, {}, {}
  for i = 1, #colors do
    family[i], alike[i] = {}, {}
    alike_fixed[i] = Color.distance(colors[i], fixed) < Color.DISTINCT
    for j = 1, #colors do
      family[i][j] = M.same_hue(colors[i], colors[j])
      alike[i][j] = Color.distance(colors[i], colors[j]) < Color.DISTINCT
    end
  end
  return family, alike, alike_fixed
end

--- How much this arrangement would hurt readability. Lower is better.
local function cost(arrangement, family, alike, alike_fixed)
  local total = 0
  for i = 1, LEADS do
    for j = i + 1, LEADS do
      if family[arrangement[i]][arrangement[j]] then
        total = total + 1
      end
    end
  end
  for i = 1, KEPT_DISTINCT do
    if alike_fixed[arrangement[i]] then
      total = total + COLLISION_COST
    end
    for j = i + 1, KEPT_DISTINCT do
      if alike[arrangement[i]][arrangement[j]] then
        total = total + COLLISION_COST
      end
    end
  end
  return total
end

local function roles_moved(arrangement)
  local count = 0
  for index, source in ipairs(arrangement) do
    if source ~= index then
      count = count + 1
    end
  end
  return count
end

--- The numbers of the arrangements that read best.
local function best_arrangements(family, alike, alike_fixed)
  local best, lowest = {}, math.huge
  for index, arrangement in ipairs(M.arrangements()) do
    local score = cost(arrangement, family, alike, alike_fixed)
    if score < lowest then
      best, lowest = {}, score
    end
    if score == lowest then
      best[#best + 1] = index
    end
  end
  return best
end

--- The number of the arrangement for these colors: the one closest to the convention
--- among those that read best.
local function choose(colors, fixed)
  local family, alike, alike_fixed = comparisons(colors, fixed)
  local convention = { unpack(M.ROLES) }
  for index = 1, #convention do
    convention[index] = index
  end
  if cost(convention, family, alike, alike_fixed) == 0 then
    return M.CONVENTION
  end
  local best = best_arrangements(family, alike, alike_fixed)
  local closest, fewest = nil, math.huge
  for _, index in ipairs(best) do
    local moved = roles_moved(M.arrangements()[index])
    if moved < fewest then
      closest, fewest = index, moved
    end
  end
  return closest
end

--- Move `picks` between ROLES. `fixed` is a color that does not move and must stay
--- distinct from them. Returns the number of the arrangement used.
function M.cast(picks, fixed)
  local before, colors = {}, {}
  for index, role in ipairs(M.ROLES) do
    before[index], colors[index] = picks[role], picks[role].hex
  end
  local casting = choose(colors, fixed)
  if casting ~= M.CONVENTION then
    local arrangement = M.arrangements()[casting]
    for index, role in ipairs(M.ROLES) do
      picks[role] = before[arrangement[index]]
    end
  end
  return casting
end

return M
