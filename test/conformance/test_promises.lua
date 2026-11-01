-- Every theme is a test. With a local Ghostty install this runs all of them;
-- without one it still runs the hand-picked hard cases below.
local T = require("harness")
local Compiler = require("color-rex.compiler")
local Config = require("color-rex.config")
local Theme = require("color-rex.theme")

local CORPUS = os.getenv("COLOR_REX_THEMES") or "/usr/share/ghostty/themes"
local OPTS = Config.resolve()
-- The fixed mapping. A test about what the palette itself reaches has to use this:
-- with casting on, any edit reshuffles the roles and the test would prove nothing.
local FIXED = Config.resolve({ identity = false })

local function corpus()
  local themes = {}
  local listing = io.popen(('ls "%s" 2>/dev/null'):format(CORPUS))
  for name in listing:lines() do
    local file = io.open(CORPUS .. "/" .. name)
    if file then
      themes[name] = Theme.parse(file:read("*a"))
      file:close()
    end
  end
  listing:close()
  return themes
end

local function ansi(list)
  local out = {}
  for i, hex in ipairs(list) do
    out[i - 1] = hex
  end
  return out
end

-- Palettes chosen because each once broke a naive mapping.
local HARD = {
  solarized_light = {
    fg = "#657b83", bg = "#fdf6e3", cursor = "#657b83",
    ansi = ansi({ "#073642", "#dc322f", "#859900", "#b58900", "#268bd2", "#d33682", "#2aa198", "#eee8d5",
      "#002b36", "#cb4b16", "#586e75", "#657b83", "#839496", "#6c71c4", "#93a1a1", "#fdf6e3" }),
  },
  one_light = {
    fg = "#383a42", bg = "#fafafa", cursor = "#526fff",
    ansi = ansi({ "#383a42", "#e45649", "#50a14f", "#c18401", "#0184bc", "#a626a4", "#0997b3", "#fafafa",
      "#4f525e", "#e06c75", "#98c379", "#e5c07b", "#61afef", "#c678dd", "#56b6c2", "#ffffff" }),
  },
  monochrome = {
    fg = "#cccccc", bg = "#000000",
    ansi = ansi({ "#000000", "#777777", "#777777", "#777777", "#777777", "#777777", "#777777", "#777777",
      "#444444", "#999999", "#999999", "#999999", "#999999", "#999999", "#999999", "#ffffff" }),
  },
  mid_grey_background = {
    fg = "#ffffff", bg = "#777777",
    ansi = ansi({ "#777777", "#787878", "#767676", "#797979", "#757575", "#7a7a7a", "#747474", "#7b7b7b",
      "#737373", "#7c7c7c", "#727272", "#7d7d7d", "#717171", "#7e7e7e", "#707070", "#7f7f7f" }),
  },
  unreadable_foreground = {
    fg = "#222222", bg = "#1c1c1c",
    ansi = ansi({ "#000000", "#330000", "#003300", "#333300", "#000033", "#330033", "#003333", "#333333",
      "#111111", "#440000", "#004400", "#444400", "#000044", "#440044", "#004444", "#444444" }),
  },
}

-- Lowered by hand as the compiler improves. Raising one means it got worse.
local TWIN_LIMIT, CLOSE_LIMIT = 8, 41

local function verify(name, theme)
  local colorscheme = Compiler.compile(theme, OPTS)
  local failures = Compiler.check(colorscheme, OPTS)
  if #failures > 0 then
    error(("%s: %s"):format(name, failures[1].message), 0)
  end
  return colorscheme
end

for name, theme in pairs(HARD) do
  T.test("promises: " .. name, function()
    verify(name, theme)
  end)
end

T.test("promises: every Ghostty theme, at both contrast settings", function()
  local themes = corpus()
  if next(themes) == nil then
    T.skip("no theme corpus at " .. CORPUS)
  end
  local strict = Config.resolve({ contrast = 4.5 })
  local count = 0
  for name, theme in pairs(themes) do
    verify(name, theme)
    local failures = Compiler.check(Compiler.compile(theme, strict), strict)
    if #failures > 0 then
      error(("%s at 4.5: %s"):format(name, failures[1].message), 0)
    end
    count = count + 1
  end
  print(("  %d themes kept the promises"):format(count))
end)

T.test("unique: a theme's color stays off screen only if it would look like one that is on it", function()
  -- All twelve chromatic slots, in every theme: edit one and something on screen
  -- must change. The one exception is the solver doing its job: if the new color
  -- would read as a color already showing, leaving it out is what keeps tokens
  -- distinct. Anything else is a dead slot.
  local themes = corpus()
  if next(themes) == nil then
    T.skip("no theme corpus at " .. CORPUS)
  end
  local Color = require("color-rex.color")
  local Solver = require("color-rex.compiler.solver")
  local function rotated(hex)
    local r, g, b = hex:match("#(%x%x)(%x%x)(%x%x)")
    return "#" .. b .. r .. g
  end
  local function shows(colorscheme, hex)
    local shown = Color.lift(hex, colorscheme.filled.bg, OPTS.contrast)
    for _, role in pairs(colorscheme.roles) do
      if type(role) == "table" and role.hex and role.source:match("^ansi")
        and Color.distance(role.hex, shown) < Solver.DISTINCT then
        return true
      end
    end
    return false
  end
  local dead, rejected, edits = {}, 0, 0
  for name, theme in pairs(themes) do
    local before = Compiler.compile(theme, FIXED).groups
    for _, slot in ipairs({ 1, 2, 3, 4, 5, 6, 9, 10, 11, 12, 13, 14 }) do
      local original = theme.ansi[slot]
      local edited = rotated(original)
      -- Both must be chromatic: the solver treats anything below this as a grey.
      if Color.chroma(original) >= Solver.MIN_CHROMA and Color.chroma(edited) >= Solver.MIN_CHROMA
        and Color.distance(original, edited) >= Solver.DISTINCT then
        theme.ansi[slot] = edited
        local after = Compiler.compile(theme, FIXED)
        theme.ansi[slot] = original
        edits = edits + 1
        local same = true
        for group, spec in pairs(before) do
          local other = after.groups[group]
          if spec.fg ~= other.fg or spec.bg ~= other.bg or spec.sp ~= other.sp then
            same = false
            break
          end
        end
        if same and shows(after, edited) then
          rejected = rejected + 1
        elseif same then
          dead[#dead + 1] = ("%s ansi %d"):format(name, slot)
        end
      end
    end
  end
  print(("  %d single-color edits: %d rejected as lookalikes, %d dead"):format(edits, rejected, #dead))
  T.eq(#dead, 0, table.concat(dead, ", "):sub(1, 400))
end)

--- How many code roles visibly differ between two compiled colorschemes.
local CODE_ROLES = { "keyword", "func", "string", "type", "number", "operator", "comment", "preproc", "special", "constant" }

local function role_colors(colorscheme)
  local out = {}
  for index, role in ipairs(CODE_ROLES) do
    out[index] = colorscheme.roles[role].hex
  end
  return out
end

local function roles_apart(a, b, Color, limit)
  local count = 0
  for index = 1, #a do
    if Color.distance(a[index], b[index]) >= limit then
      count = count + 1
    end
  end
  return count
end

T.test("unique: a theme reads as its own colorscheme, not just a tint of another", function()
  -- The promise itself: compare only what you read in code, never fg, bg or
  -- surfaces. Each compile sees one theme, so casting cannot rule out two themes
  -- drawing the same arrangement, and these bounds only ever move down.
  local themes = corpus()
  if next(themes) == nil then
    T.skip("no theme corpus at " .. CORPUS)
  end
  local Color = require("color-rex.color")
  local Solver = require("color-rex.compiler.solver")
  local list = {}
  for name, theme in pairs(themes) do
    local colorscheme = Compiler.compile(theme, OPTS)
    list[#list + 1] = { name = name, key = colorscheme.key, colors = role_colors(colorscheme) }
  end
  local closest = {}
  for i = 1, #list do
    for j = i + 1, #list do
      if list[i].key ~= list[j].key then
        local apart = roles_apart(list[i].colors, list[j].colors, Color, Solver.DISTINCT)
        closest[i] = math.min(closest[i] or 99, apart)
        closest[j] = math.min(closest[j] or 99, apart)
      end
    end
  end
  local twins, close = 0, 0
  for i = 1, #list do
    twins = twins + (closest[i] == 0 and 1 or 0)
    close = close + (closest[i] <= 2 and 1 or 0)
  end
  print(("  %d themes: %d with an identical twin, %d within 2 roles of another"):format(#list, twins, close))
  T.ok(twins <= TWIN_LIMIT, ("%d themes have an identical twin"):format(twins))
  T.ok(close <= CLOSE_LIMIT, ("%d themes are within 2 roles of another"):format(close))
end)

T.test("unique: casting moves colors between roles and changes no color", function()
  local themes = corpus()
  themes.one_light, themes.solarized_light = HARD.one_light, HARD.solarized_light
  for name, theme in pairs(themes) do
    local cast, fixed = Compiler.compile(theme, OPTS), Compiler.compile(theme, FIXED)
    local a, b = {}, {}
    for _, role in ipairs({ "keyword", "func", "type", "number", "operator" }) do
      a[#a + 1], b[#b + 1] = cast.roles[role].hex, fixed.roles[role].hex
    end
    table.sort(a)
    table.sort(b)
    T.eq(table.concat(a), table.concat(b), name)
    T.eq(cast.roles.string.hex, fixed.roles.string.hex, name .. " string")
    T.eq(cast.roles.comment.hex, fixed.roles.comment.hex, name .. " comment")
  end
end)

T.test("unique: a theme keeps its casting and its id, and different themes get different ids", function()
  local themes = corpus()
  if next(themes) == nil then
    T.skip("no theme corpus at " .. CORPUS)
  end
  local Casting = require("color-rex.compiler.casting")
  local ids, used, count = {}, {}, 0
  for name, theme in pairs(themes) do
    local first, second = Compiler.compile(theme, OPTS), Compiler.compile(theme, OPTS)
    T.eq(first.id, second.id, name)
    T.eq(first.casting, second.casting, name)
    T.ok(ids[first.id] == nil or ids[first.id] == first.key, name .. " shares an id with another theme")
    ids[first.id] = first.key
    used[first.casting] = true
    count = count + 1
  end
  local arrangements = 0
  for _ in pairs(used) do
    arrangements = arrangements + 1
  end
  print(("  %d themes spread over %d of %d arrangements"):format(count, arrangements, #Casting.ARRANGEMENTS))
  T.eq(arrangements, #Casting.ARRANGEMENTS, "an arrangement no theme ever gets is a bug in the fingerprint")
end)

T.test("unique: arrangements really are that far apart, and the first is the fixed mapping", function()
  local Casting = require("color-rex.compiler.casting")
  T.eq(table.concat(Casting.ARRANGEMENTS[1], ","), "1,2,3,4,5")
  for i = 1, #Casting.ARRANGEMENTS do
    for j = i + 1, #Casting.ARRANGEMENTS do
      local moved = 0
      for k = 1, 5 do
        moved = moved + (Casting.ARRANGEMENTS[i][k] ~= Casting.ARRANGEMENTS[j][k] and 1 or 0)
      end
      T.ok(moved >= Casting.MIN_APART, ("%d and %d"):format(i, j))
    end
  end
end)

T.test("unique: a style only separates colors when the palette truly cannot", function()
  -- Keeping the promise is not enough. Styles alone would satisfy it for every
  -- theme and leave hundreds of them flat, so this bounds how often they are
  -- needed. It only moves down: raising it means the solver got worse.
  local themes = corpus()
  if next(themes) == nil then
    T.skip("no theme corpus at " .. CORPUS)
  end
  local Color = require("color-rex.color")
  local Solver = require("color-rex.compiler.solver")
  local total, flat = 0, 0
  for _, theme in pairs(themes) do
    local roles = Compiler.compile(theme, FIXED).roles
    local names = { "keyword", "func", "string", "type", "number", "operator" }
    local touching = false
    for i = 1, #names do
      for j = i + 1, #names do
        if Color.distance(roles[names[i]].hex, roles[names[j]].hex) < Solver.DISTINCT then
          touching = true
        end
      end
    end
    total = total + 1
    flat = flat + (touching and 1 or 0)
  end
  print(("  %d of %d themes need a style to separate colors"):format(flat, total))
  T.ok(flat / total <= 0.05, ("%d of %d themes"):format(flat, total))
end)

T.test("unique: a role with a spare color takes it instead of sharing", function()
  local theme = {
    fg = "#d0d0d0", bg = "#101010",
    ansi = { [0] = "#000000", [1] = "#ff5555", [2] = "#55ff55", [3] = "#ffff55", [4] = "#5555ff", [5] = "#5555ff",
      [6] = "#55ffff", [7] = "#c0c0c0", [8] = "#707070", [9] = "#ff8888", [10] = "#88ff88", [11] = "#ffff88",
      [12] = "#8888ff", [13] = "#ff55ff", [14] = "#88ffff", [15] = "#ffffff" },
  }
  local groups = Compiler.compile(theme, OPTS).groups
  T.ok(groups.Keyword.fg ~= groups.Function.fg, "ansi 4 and 5 match, but ansi 13 was free")
end)

T.test("determinism: the same theme compiles identically, in any order", function()
  local theme = HARD.one_light
  local first = Compiler.compile(theme, OPTS)
  Compiler.compile(HARD.monochrome, OPTS)
  local second = Compiler.compile(theme, OPTS)
  for name, spec in pairs(first.groups) do
    T.eq(spec.fg, second.groups[name].fg, name)
    T.eq(spec.bg, second.groups[name].bg, name)
  end
end)

T.test("transparent: only the opaque option paints a background on Normal", function()
  local clear = Compiler.compile(HARD.one_light, OPTS).groups.Normal
  local solid_opts = Config.resolve({ transparent = false })
  local solid = Compiler.compile(HARD.one_light, solid_opts).groups.Normal
  T.eq(clear.bg, nil)
  T.eq(solid.bg, "#fafafa")
end)

T.test("fallback: an unanswered query looks like nothing, not like a theme", function()
  local colorscheme = Compiler.compile({}, OPTS)
  T.eq(colorscheme.completeness, "none")
  local colors = {}
  for _, hex in ipairs({ colorscheme.groups.Keyword.fg, colorscheme.groups.String.fg, colorscheme.groups.Number.fg }) do
    colors[#colors + 1] = hex
  end
  for _, hex in ipairs(colors) do
    local r, g, b = hex:match("#(%x%x)(%x%x)(%x%x)")
    T.eq(r, g, "grey expected, got " .. hex)
    T.eq(g, b, "grey expected, got " .. hex)
  end
end)
