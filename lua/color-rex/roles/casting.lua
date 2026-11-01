-- Casting: which role each of a theme's colors plays.
--
-- Two themes with nearly the same palette must compile to nearly the same colors,
-- or the compiler is not faithful. So color alone can never tell them apart: a
-- different background or a slight tint leaves the same colorscheme on screen.
-- What can differ is the casting. No terminal theme says which color is a keyword,
-- so that choice is the compiler's to make, and each theme can get its own.
--
-- Colors are never changed, only moved between roles, and strings and comments stay
-- where they are. Every arrangement is judged against the theme, so identity never
-- costs readability: an arrangement must first keep syntax roles from looking alike,
-- and then keep keywords, functions and types, which sit side by side in all code,
-- from sharing a hue. The theme's fingerprint chooses among the best that are left.
local Color = require("color-rex.color")

local M = {}

M.ROLES = { "keyword", "func", "type", "number", "operator", "preproc", "special" } -- the roles that move
M.FIXED = 1 -- the arrangement that moves nothing
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

--- Every arrangement in use. Each entry says, for each role in ROLES, which role's
--- color it takes. Only even permutations are kept, because two of them can never
--- differ in just two roles: that would be a single swap, which is odd. So any two
--- arrangements are at least three roles apart, by construction. The fixed mapping
--- goes first. Reordering this list recasts every theme, so a test pins it.
M.ARRANGEMENTS = (function()
  local identity = {}
  for index = 1, #M.ROLES do
    identity[index] = index
  end
  local kept = { identity }
  for _, candidate in ipairs(permutations({ unpack(identity) }, #identity, {})) do
    if even(candidate) and table.concat(candidate) ~= table.concat(identity) then
      kept[#kept + 1] = candidate
    end
  end
  return kept
end)()

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

--- The number of the arrangement for this theme: of those that read best, the one
--- its fingerprint picks.
local function choose(colors, fixed, fingerprint)
  local family, alike, alike_fixed = comparisons(colors, fixed)
  local best, lowest = {}, math.huge
  for index, arrangement in ipairs(M.ARRANGEMENTS) do
    local score = cost(arrangement, family, alike, alike_fixed)
    if score < lowest then
      best, lowest = {}, score
    end
    if score == lowest then
      best[#best + 1] = index
    end
  end
  return best[fingerprint % #best + 1]
end

--- Move `picks` between ROLES. `fixed` is a color that does not move and must stay
--- distinct from them. With no fingerprint nothing moves. Returns the number of the
--- arrangement used.
function M.cast(picks, fixed, fingerprint)
  local before, colors = {}, {}
  for index, role in ipairs(M.ROLES) do
    before[index], colors[index] = picks[role], picks[role].hex
  end
  local casting = fingerprint and choose(colors, fixed, fingerprint) or M.FIXED
  for index, role in ipairs(M.ROLES) do
    picks[role] = before[M.ARRANGEMENTS[casting][index]]
  end
  return casting
end

return M
