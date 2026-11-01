-- Casting: which role each of a theme's colors plays.
--
-- Two themes with nearly the same palette must compile to nearly the same colors,
-- or the compiler is not faithful. So color alone can never tell them apart: a
-- different background or a slight tint leaves the same colorscheme on screen.
-- What can differ is the casting. No terminal theme says which color is a keyword,
-- so that choice is the compiler's to make, and each theme can get its own.
--
-- A fingerprint of the theme picks one arrangement. Colors are never changed, only
-- moved between roles, and strings and comments stay where they are. Arrangements
-- differ from each other in at least MIN_APART roles, so that two themes that land
-- on different ones are visibly different colorschemes.
local M = {}

M.ROLES = { "keyword", "func", "type", "number", "operator" } -- the roles that move
M.MIN_APART = 3

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

local function moved(a, b)
  local count = 0
  for index = 1, #a do
    if a[index] ~= b[index] then
      count = count + 1
    end
  end
  return count
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

--- Every arrangement in use, starting with the fixed mapping. Each entry says, for
--- each role in ROLES, which role's color it takes. Built once, and always in the
--- same order, so a theme's casting never changes between sessions.
M.ARRANGEMENTS = (function()
  local chosen = { { 1, 2, 3, 4, 5 } }
  for _, candidate in ipairs(permutations({ 1, 2, 3, 4, 5 }, 5, {})) do
    local far_enough = true
    for _, existing in ipairs(chosen) do
      far_enough = far_enough and moved(candidate, existing) >= M.MIN_APART
    end
    if far_enough then
      chosen[#chosen + 1] = candidate
    end
  end
  return chosen
end)()

--- The arrangement for a fingerprint, and its number in ARRANGEMENTS.
function M.arrangement(fingerprint)
  local index = fingerprint % #M.ARRANGEMENTS + 1
  return M.ARRANGEMENTS[index], index
end

return M
