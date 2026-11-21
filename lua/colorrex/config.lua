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
  -- Give each theme its own voice: a cursor with a color of its own takes the keywords,
  -- and the other roles follow one of six arrangements. Off: roles always follow the
  -- ANSI convention, and themes with the same colors read the same.
  voice = true,
  -- Mark where each chunk of code starts: the name on its first line stands out, so
  -- a file can be scanned by its shape. Needs Treesitter highlighting in the buffer.
  chunks = false,
  -- Also sync on focus and on dark/light notifications, and watch for a while after
  -- focus leaves, which is when Rex's picker previews themes unannounced. Nothing
  -- runs while idle. Off: only :ColorRex changes colors after launch.
  auto = true,
  -- Give file icons the theme's colors. nvim-web-devicons ships a fixed color for every
  -- file type, the same in every theme; each takes the nearest of the theme's own. On,
  -- because installing this is asking for the terminal's theme everywhere. Off: its
  -- colors are left as they shipped, which is also how to keep icon colors of your own.
  icons = true,
  -- Highlight groups of your own, or ones a plugin defines, written as the built-in ones
  -- are: each color names a role, never a hex value, so it follows every theme. A name
  -- colorrex already defines is replaced. See :help colorrex-roles.
  groups = {},
}

-- What a group may set. Colors name roles; `link` names a group; the rest are the
-- styles nvim_set_hl takes.
local GROUP_COLORS = { fg = true, bg = true, sp = true }
local GROUP_STYLES = {
  bold = true, italic = true, underline = true, undercurl = true, underdouble = true, underdotted = true,
  underdashed = true, strikethrough = true, reverse = true, nocombine = true, standout = true,
}

--- A copy of the user's groups, or an error naming the first mistake. Whether a role
--- exists is the compiler's to say; this checks the shape.
local function resolve_groups(groups)
  local out = {}
  for name, spec in pairs(groups) do
    if type(name) ~= "string" or name == "" then
      error("colorrex: option 'groups' is keyed by highlight group names", 0)
    end
    if type(spec) ~= "table" then
      error(("colorrex: group '%s' must be a table, such as { fg = \"accent\" }"):format(name), 0)
    end
    local copy = {}
    for key, value in pairs(spec) do
      if GROUP_COLORS[key] then
        if type(value) ~= "string" then
          error(("colorrex: group '%s': %s must name a role"):format(name, key), 0)
        end
        if value:sub(1, 1) == "#" then
          error(("colorrex: group '%s': %s is the color %s; it must name a role, such as \"accent\""):format(
            name, key, value), 0)
        end
      elseif key == "link" then
        if type(value) ~= "string" or value == "" then
          error(("colorrex: group '%s': link must name a highlight group"):format(name), 0)
        end
      elseif key == "blend" then
        if type(value) ~= "number" or not (value >= 0 and value <= 100) then
          error(("colorrex: group '%s': blend must be a number from 0 to 100"):format(name), 0)
        end
      elseif GROUP_STYLES[key] then
        if type(value) ~= "boolean" then
          error(("colorrex: group '%s': %s must be true or false"):format(name, key), 0)
        end
      else
        error(("colorrex: group '%s' has an unknown key '%s'"):format(name, tostring(key)), 0)
      end
      copy[key] = value
    end
    if copy.link and next(copy, next(copy)) ~= nil then
      error(("colorrex: group '%s' links to %s, so it can set nothing else"):format(name, copy.link), 0)
    end
    out[name] = copy
  end
  return out
end

-- Options that were renamed, so an old config says what to write instead.
local RENAMED = { force_unique = "voice" }

--- Defaults merged with `opts`. Raises on a mistake, so a typo in setup() is
--- reported at startup instead of silently doing nothing.
function M.resolve(opts)
  local out = {}
  for key, value in pairs(M.defaults) do
    out[key] = value
  end
  for key, value in pairs(opts or {}) do
    if RENAMED[key] then
      error(("colorrex: option '%s' is now '%s'"):format(key, RENAMED[key]), 0)
    end
    if M.defaults[key] == nil then
      error(("colorrex: unknown option '%s'"):format(tostring(key)), 0)
    end
    if type(value) ~= type(M.defaults[key]) then
      error(("colorrex: option '%s' must be a %s"):format(key, type(M.defaults[key])), 0)
    end
    out[key] = value
  end
  if not (out.contrast >= 1 and out.contrast <= 4.5) then
    error("colorrex: option 'contrast' must be between 1 and 4.5", 0)
  end
  out.groups = resolve_groups(out.groups)
  return out
end

return M
