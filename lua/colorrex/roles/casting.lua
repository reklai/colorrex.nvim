-- Casting: which role each of a theme's colors plays.
--
-- No terminal theme says which color is a keyword. What it has is the ANSI
-- convention, which is the closest thing to what its author meant, so a theme keeps
-- that. Keywords stay magenta and functions blue, unless that would make the code
-- hard to read: two syntax roles that look alike, or keywords, functions and types,
-- which sit side by side in all code, sharing a hue. Then it moves as little as
-- that takes.
--
-- So casting follows the palette, and only the palette. Two themes with the same
-- colors read the same in code, whatever their backgrounds, because they are the
-- same colors. A change too small to see moves nothing, and a family of themes stays
-- a family. Colors are never changed, only moved between roles, and strings and
-- comments stay where they are.
--
-- force_unique is the exception, and asks for the opposite: a fingerprint of the
-- theme picks among the arrangements that read well, so that nearly identical themes
-- look different. A fingerprint knows nothing about a theme, so this separates them
-- by noise, and a change of one step in a background recasts most themes.
local Color = require("colorrex.color")

local M = {}

M.ROLES = { "keyword", "func", "type", "number", "operator", "preproc", "special" } -- the roles that move
M.CONVENTION = 1 -- the arrangement that moves nothing
M.SAME_HUE = 25 -- degrees apart, below which two colors read as one family

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

local function same_hue(x, y)
  return Color.chroma(x) >= Color.HUE_MIN_CHROMA and Color.chroma(y) >= Color.HUE_MIN_CHROMA
    and Color.hue_gap(x, y) < M.SAME_HUE
end

--- For each pair of colors, whether the eye would confuse them.
local function comparisons(colors, fixed)
  local family, alike, alike_fixed = {}, {}, {}
  for i = 1, #colors do
    family[i], alike[i] = {}, {}
    alike_fixed[i] = Color.distance(colors[i], fixed) < Color.DISTINCT
    for j = 1, #colors do
      family[i][j] = same_hue(colors[i], colors[j])
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

--- One arrangement per result. When two roles hold the same color, arrangements that
--- only trade them look identical, and a fingerprint choosing between those would not
--- be choosing anything.
local function distinct_results(arrangement_numbers, colors)
  local seen, out = {}, {}
  for _, number in ipairs(arrangement_numbers) do
    local result = {}
    for role, source in ipairs(M.arrangements()[number]) do
      result[role] = colors[source]
    end
    local key = table.concat(result)
    if not seen[key] then
      seen[key] = true
      out[#out + 1] = number
    end
  end
  return out
end

--- The number of the arrangement for these colors: the one closest to the convention
--- among those that read best, or with a fingerprint, the one it picks.
local function choose(colors, fixed, fingerprint)
  local family, alike, alike_fixed = comparisons(colors, fixed)
  local convention = { unpack(M.ROLES) }
  for index = 1, #convention do
    convention[index] = index
  end
  if not fingerprint and cost(convention, family, alike, alike_fixed) == 0 then
    return M.CONVENTION
  end
  local best = best_arrangements(family, alike, alike_fixed)
  if fingerprint then
    local results = distinct_results(best, colors)
    return results[fingerprint % #results + 1]
  end
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
function M.cast(picks, fixed, fingerprint)
  local before, colors = {}, {}
  for index, role in ipairs(M.ROLES) do
    before[index], colors[index] = picks[role], picks[role].hex
  end
  local casting = choose(colors, fixed, fingerprint)
  if casting ~= M.CONVENTION then
    local arrangement = M.arrangements()[casting]
    for index, role in ipairs(M.ROLES) do
      picks[role] = before[arrangement[index]]
    end
  end
  return casting
end

return M
