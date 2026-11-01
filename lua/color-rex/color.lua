-- Color math. Pure Lua: no Neovim, no state, no allocation beyond strings.
--
-- OKLab is the working space because it is perceptually even: a distance means
-- roughly the same thing at every hue, and moving lightness keeps hue steady.
-- Contrast uses the WCAG formula, because that is the number people check.
local M = {}

local function clamp(v, lo, hi)
  return v < lo and lo or (v > hi and hi or v)
end

--- Parse "#rrggbb" (or "rrggbb") into 0-255 integers, or nil.
function M.parse(hex)
  if type(hex) ~= "string" then
    return nil
  end
  local r, g, b = hex:match("^#?(%x%x)(%x%x)(%x%x)$")
  if not r then
    return nil
  end
  return tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)
end

function M.format(r, g, b)
  return string.format("#%02x%02x%02x", r, g, b)
end

local function to_linear(channel)
  local c = channel / 255
  if c <= 0.04045 then
    return c / 12.92
  end
  return ((c + 0.055) / 1.055) ^ 2.4
end

local function from_linear(x)
  local c = x <= 0.0031308 and 12.92 * x or 1.055 * x ^ (1 / 2.4) - 0.055
  return math.floor(clamp(c, 0, 1) * 255 + 0.5)
end

--- Signed cube root: lms values can dip below zero just outside the gamut.
local function cbrt(x)
  return x < 0 and -((-x) ^ (1 / 3)) or x ^ (1 / 3)
end

--- OKLab coordinates of a hex color.
function M.oklab(hex)
  local r8, g8, b8 = M.parse(hex)
  local r, g, b = to_linear(r8), to_linear(g8), to_linear(b8)
  local l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
  local m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
  local s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
  return 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
end

local function oklab_to_linear(L, a, b)
  local l = (L + 0.3963377774 * a + 0.2158037573 * b) ^ 3
  local m = (L - 0.1055613458 * a - 0.0638541728 * b) ^ 3
  local s = (L - 0.0894841775 * a - 1.2914855480 * b) ^ 3
  return 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
end

local function in_gamut(r, g, b)
  local eps = 1e-4
  return r >= -eps and r <= 1 + eps and g >= -eps and g <= 1 + eps and b >= -eps and b <= 1 + eps
end

--- Hex of an OKLab color. Out-of-gamut colors lose chroma, never hue: clipping
--- channels independently would visibly turn a saturated color a different hue.
function M.from_oklab(L, a, b)
  L = clamp(L, 0, 1)
  local r, g, bl = oklab_to_linear(L, a, b)
  if not in_gamut(r, g, bl) then
    local lo, hi = 0, 1
    for _ = 1, 12 do
      local scale = (lo + hi) / 2
      if in_gamut(oklab_to_linear(L, a * scale, b * scale)) then
        lo = scale
      else
        hi = scale
      end
    end
    r, g, bl = oklab_to_linear(L, a * lo, b * lo)
  end
  return M.format(from_linear(r), from_linear(g), from_linear(bl))
end

--- Perceptual distance between two colors. 0 is identical; about 0.04 is where
--- two code tokens stop reading as different colors at a glance.
function M.distance(x, y)
  local L1, a1, b1 = M.oklab(x)
  local L2, a2, b2 = M.oklab(y)
  local dL, da, db = L1 - L2, a1 - a2, b1 - b2
  return math.sqrt(dL * dL + da * da + db * db)
end

function M.chroma(hex)
  local _, a, b = M.oklab(hex)
  return math.sqrt(a * a + b * b)
end

--- Hue angle in degrees, 0-360.
function M.hue(hex)
  local _, a, b = M.oklab(hex)
  return (math.deg(math.atan2(b, a)) + 360) % 360
end

--- Smallest angle between two hues.
function M.hue_gap(x, y)
  local gap = math.abs(M.hue(x) - M.hue(y)) % 360
  return gap > 180 and 360 - gap or gap
end

--- Move `from` toward `to` by t (0 = from, 1 = to), in OKLab.
function M.mix(from, to, t)
  local L1, a1, b1 = M.oklab(from)
  local L2, a2, b2 = M.oklab(to)
  return M.from_oklab(L1 + (L2 - L1) * t, a1 + (a2 - a1) * t, b1 + (b2 - b1) * t)
end

function M.luminance(hex)
  local r, g, b = M.parse(hex)
  return 0.2126 * to_linear(r) + 0.7152 * to_linear(g) + 0.0722 * to_linear(b)
end

--- WCAG contrast ratio, 1 to 21.
function M.contrast(x, y)
  local hi, lo = M.luminance(x), M.luminance(y)
  if lo > hi then
    hi, lo = lo, hi
  end
  return (hi + 0.05) / (lo + 0.05)
end

--- Same weights and threshold as Neovim's own 'background' detection, so the
--- two can never disagree about whether a theme is dark.
function M.is_dark(hex)
  local r, g, b = M.parse(hex)
  return (0.299 * r + 0.587 * g + 0.114 * b) / 255 < 0.5
end

--- The nearest color to `hex` with at least `floor` contrast against `bg`.
---
--- Only lightness moves, so a color keeps its hue and identity. Contrast rises
--- steadily along lightness, so bisection finds the smallest move. Every
--- background has at least 4.58:1 against black or white, so any floor up to
--- that is reachable.
function M.lift(hex, bg, floor)
  if M.contrast(hex, bg) >= floor then
    return hex
  end
  local L, a, b = M.oklab(hex)
  local goal = M.contrast("#ffffff", bg) >= M.contrast("#000000", bg) and 1 or 0
  local lo, hi = L, goal
  local best = goal == 1 and "#ffffff" or "#000000"
  for _ = 1, 16 do
    local mid = (lo + hi) / 2
    local candidate = M.from_oklab(mid, a, b)
    if M.contrast(candidate, bg) >= floor then
      best, hi = candidate, mid
    else
      lo = mid
    end
  end
  return best
end

return M
