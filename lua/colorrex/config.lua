-- Options. Few on purpose: the theme decides how things look.
local M = {}

-- One name everywhere: the colorscheme, the lualine theme, the state directory.
M.NAME = "colorrex"

M.defaults = {
  -- Leave the background to the terminal, so its exact color and any opacity
  -- show through. Off: Neovim paints the theme's background itself.
  transparent = true,
  -- Minimum contrast for code against the background. Up to 4.5, which every
  -- possible background can reach.
  contrast = 3.0,
  -- Give each theme its own voice: its cursor color takes the keywords, and the other
  -- roles follow one of six arrangements. Off: roles follow the ANSI convention, so a
  -- theme's colors decide how it reads, and themes with the same colors read the same.
  force_unique = false,
  -- Also sync on focus and on dark/light notifications. These cost nothing
  -- while idle. Off: only :ColorRex changes colors after launch.
  auto = true,
}

--- Defaults merged with `opts`. Raises on a mistake, so a typo in setup() is
--- reported at startup instead of silently doing nothing.
function M.resolve(opts)
  local out = {}
  for key, value in pairs(M.defaults) do
    out[key] = value
  end
  for key, value in pairs(opts or {}) do
    if M.defaults[key] == nil then
      error(("colorrex: unknown option '%s'"):format(tostring(key)), 0)
    end
    if type(value) ~= type(M.defaults[key]) then
      error(("colorrex: option '%s' must be a %s"):format(key, type(M.defaults[key])), 0)
    end
    out[key] = value
  end
  if out.contrast < 1 or out.contrast > 4.5 then
    error("colorrex: option 'contrast' must be between 1 and 4.5", 0)
  end
  return out
end

return M
