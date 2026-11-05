-- Every theme is a test. With a local Ghostty install this runs all of them;
-- without one it still runs the hand-picked hard cases below.
local T = require("harness")
local Compiler = require("colorrex.compiler")
local Config = require("colorrex.config")
local Theme = require("colorrex.theme")

local CORPUS = os.getenv("COLORREX_THEMES") or "/usr/share/ghostty/themes"
local OPTS = Config.resolve()
local PLAIN = Config.resolve({ voice = false })

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
local CLASH_LIMIT, RECAST_LIMIT, FADED_LIMIT, TWIN_LIMIT = 11, 45, 19, 34
local VOICE_RECAST_LIMIT, VOICED_FLOOR = 20, 255

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

T.test("surface: what code lies under eases for it, and can still be seen", function()
  local Color = require("colorrex.color")
  local themes = corpus()
  if next(themes) == nil then
    T.skip("no theme corpus at " .. CORPUS)
  end
  local eased, names = {}, {}
  for name, theme in pairs(themes) do
    local colorscheme = Compiler.compile(theme, OPTS)
    local bg = colorscheme.filled.bg
    for _, note in ipairs(colorscheme.notes) do
      local surface, from, to = note.message:match("^(%S+) eased from (%d+)%% to (%d+)%%")
      if note.code == "faithful.surface" and surface then
        local role = colorscheme.roles[surface]
        if not eased[surface] then
          eased[surface], names[#names + 1] = 0, surface
        end
        eased[surface] = eased[surface] + 1
        T.ok(role.least, ("%s: %s eased with no floor to stop at"):format(name, surface))
        T.ok(tonumber(to) < tonumber(from), ("%s: %s grew"):format(name, surface))
        -- Easing stops while the surface still shows, unless one step more already did not.
        local before = Color.contrast(Color.mix(bg, role.over, role.mix + 0.01), bg)
        T.ok(Color.contrast(role.hex, bg) >= role.least - 0.01 or before < role.least,
          ("%s: %s faded out"):format(name, surface))
      end
    end
  end
  table.sort(names)
  local parts = {}
  for _, surface in ipairs(names) do
    parts[#parts + 1] = ("%s %d"):format(surface, eased[surface])
  end
  print(("  eased for the code on them: %s"):format(table.concat(parts, ", ")))
end)

T.test("voice: a theme's color stays off screen only if it would look like one that is on it", function()
  -- All twelve chromatic slots, in every theme: edit one and something on screen
  -- must change. The one exception is the solver doing its job: if the new color
  -- would read as a color already showing, leaving it out is what keeps tokens
  -- distinct. Anything else is a dead slot.
  local themes = corpus()
  if next(themes) == nil then
    T.skip("no theme corpus at " .. CORPUS)
  end
  local Color = require("colorrex.color")
  local Roles = require("colorrex.roles")
  local function rotated(hex)
    local r, g, b = hex:match("#(%x%x)(%x%x)(%x%x)")
    return "#" .. b .. r .. g
  end
  local function shows(colorscheme, hex)
    local shown = Color.lift(hex, colorscheme.filled.bg, OPTS.contrast)
    for _, role in pairs(colorscheme.roles) do
      if type(role) == "table" and role.hex and role.source:match("^ansi")
        and Color.distance(role.hex, shown) < Color.DISTINCT then
        return true
      end
    end
    return false
  end
  local dead, rejected, edits = {}, 0, 0
  for name, theme in pairs(themes) do
    local before = Compiler.compile(theme, OPTS).groups
    for _, slot in ipairs({ 1, 2, 3, 4, 5, 6, 9, 10, 11, 12, 13, 14 }) do
      local original = theme.ansi[slot]
      local edited = rotated(original)
      -- Both must be chromatic: the solver treats anything below this as a grey.
      if Color.chroma(original) >= Roles.MIN_CHROMA and Color.chroma(edited) >= Roles.MIN_CHROMA
        and Color.distance(original, edited) >= Color.DISTINCT then
        theme.ansi[slot] = edited
        local after = Compiler.compile(theme, OPTS)
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

local CHROMATIC = { 1, 2, 3, 4, 5, 6, 9, 10, 11, 12, 13, 14 }

--- A copy of a theme with `change` applied, leaving the original alone.
local function edited(theme, change)
  local copy = { fg = theme.fg, bg = theme.bg, cursor = theme.cursor, ansi = {} }
  for slot = 0, 15 do
    copy.ansi[slot] = theme.ansi[slot]
  end
  change(copy)
  return copy
end

--- One step of one channel: a difference nobody can see.
local function one_step(hex)
  local r, rest = hex:match("^#(%x%x)(.*)$")
  local value = tonumber(r, 16)
  return ("#%02x%s"):format(value < 255 and value + 1 or value - 1, rest)
end

T.test("identity: a difference nobody can see never changes how code reads", function()
  local themes = corpus()
  if next(themes) == nil then
    T.skip("no theme corpus at " .. CORPUS)
  end
  local Color = require("colorrex.color")
  local checked = 0
  for name, theme in pairs(themes) do
    local before = role_colors(Compiler.compile(theme, OPTS))
    for _, field in ipairs({ "bg", "fg" }) do
      local after = role_colors(Compiler.compile(edited(theme, function(copy)
        copy[field] = one_step(copy[field])
      end), OPTS))
      T.ok(roles_apart(before, after, Color, Color.DISTINCT) < 3, ("%s: one step of %s recast it"):format(name, field))
      checked = checked + 1
    end
  end
  print(("  %d invisible edits, none recast a theme"):format(checked))
end)

T.test("identity: most themes keep the ANSI convention untouched", function()
  local themes = corpus()
  if next(themes) == nil then
    T.skip("no theme corpus at " .. CORPUS)
  end
  local recast, total = 0, 0
  for _, theme in pairs(themes) do
    local colorscheme = Compiler.compile(theme, OPTS)
    recast = recast + (colorscheme.casting == 1 and 0 or 1)
    total = total + 1
  end
  print(("  %d of %d themes needed a role moved"):format(recast, total))
  T.ok(recast <= RECAST_LIMIT, ("%d themes"):format(recast))
end)

T.test("identity: a theme keeps as much color as it came with", function()
  local Casting = require("colorrex.roles.casting")
  local Color = require("colorrex.color")
  local Roles = require("colorrex.roles")
  local themes = corpus()
  if next(themes) == nil then
    T.skip("no theme corpus at " .. CORPUS)
  end
  local function middle(values)
    table.sort(values)
    return values[math.ceil(#values / 2)]
  end
  local faded = 0
  for _, theme in pairs(themes) do
    local colorscheme = Compiler.compile(theme, OPTS)
    local row = {} -- where each role was meant to sit, in this theme's voice if it has one
    for _, voice in ipairs(Casting.VOICES) do
      row = voice.name == colorscheme.voice and voice.roles or row
    end
    local shown, source = {}, {}
    for _, role in ipairs(Roles.SYNTAX) do
      shown[#shown + 1] = Color.chroma(colorscheme.roles[role.name].hex)
      source[#source + 1] = Color.chroma(colorscheme.filled.ansi[row[role.name] or role.slots[1]])
    end
    faded = faded + (middle(shown) < middle(source) * 0.9 and 1 or 0)
  end
  print(("  %d themes lost color to stay readable and distinct"):format(faded))
  T.ok(faded <= FADED_LIMIT, ("%d themes"):format(faded))
end)

T.test("practical: types and numbers do not share a hue", function()
  local Color = require("colorrex.color")
  local themes = corpus()
  if next(themes) == nil then
    T.skip("no theme corpus at " .. CORPUS)
  end
  local twins = 0
  for _, theme in pairs(themes) do
    local roles = Compiler.compile(theme, OPTS).roles
    local chromatic = Color.chroma(roles.type.hex) >= Color.HUE_MIN_CHROMA
      and Color.chroma(roles.number.hex) >= Color.HUE_MIN_CHROMA
    if chromatic and Color.hue_gap(roles.type.hex, roles.number.hex) < 15 then
      twins = twins + 1
    end
  end
  print(("  %d themes keep types and numbers in one hue"):format(twins))
  T.ok(twins <= TWIN_LIMIT, ("%d themes"):format(twins))
end)

local FAMILIES = {
  { "Everforest Dark Hard", "Everforest Dark Med" }, { "Everforest Dark Med", "Everforest Dark Soft" },
  { "Gruvbox Dark", "Gruvbox Dark Hard" }, { "Kanso Ink", "Kanso Zen" }, { "Noctis", "Noctis Obscuro" },
  { "Dark+", "Dark Modern" }, { "Modus Vivendi", "Modus Vivendi Tinted" },
}

T.test("identity: a theme family stays a family", function()
  local themes = corpus()
  if next(themes) == nil then
    T.skip("no theme corpus at " .. CORPUS)
  end
  local Color = require("colorrex.color")
  for _, pair in ipairs(FAMILIES) do
    local a = role_colors(Compiler.compile(themes[pair[1]], OPTS))
    local b = role_colors(Compiler.compile(themes[pair[2]], OPTS))
    T.ok(roles_apart(a, b, Color, Color.DISTINCT) <= 1, pair[1] .. " and " .. pair[2] .. " came apart")
  end
end)

T.test("identity: themes that read alike really do share their colors", function()
  -- Two themes may look the same on screen only if their palettes do. Otherwise a
  -- difference the theme's author made is being thrown away.
  local themes = corpus()
  if next(themes) == nil then
    T.skip("no theme corpus at " .. CORPUS)
  end
  local Color = require("colorrex.color")
  local Roles = require("colorrex.roles")
  local list = {}
  for name, theme in pairs(themes) do
    local colorscheme = Compiler.compile(theme, OPTS)
    local colors = role_colors(colorscheme)
    for _, role in ipairs(Roles.PALETTE) do -- errors and warnings show a theme's colors too
      colors[#colors + 1] = colorscheme.roles[role.name].hex
    end
    list[#list + 1] = { name = name, signature = colorscheme.signature, colors = colors, filled = colorscheme.filled }
  end
  local hidden = 0
  for i = 1, #list do
    for j = i + 1, #list do
      if list[i].signature ~= list[j].signature
        and roles_apart(list[i].colors, list[j].colors, Color, Color.DISTINCT) == 0 then
        for _, slot in ipairs(CHROMATIC) do
          -- As shown: two colors too faint to read both land on the contrast floor,
          -- so a difference between them was never one you could see.
          local a = Color.lift(list[i].filled.ansi[slot], list[i].filled.bg, OPTS.contrast)
          local b = Color.lift(list[j].filled.ansi[slot], list[j].filled.bg, OPTS.contrast)
          if Color.distance(a, b) >= Color.DISTINCT then
            hidden = hidden + 1
            break
          end
        end
      end
    end
  end
  print(("  %d pairs look alike despite a visible palette difference"):format(hidden))
  T.eq(hidden, 0)
end)

T.test("voice: a nudge to the cursor rarely changes how code reads", function()
  local themes = corpus()
  if next(themes) == nil then
    T.skip("no theme corpus at " .. CORPUS)
  end
  local Color = require("colorrex.color")
  local recast = 0
  for _, theme in pairs(themes) do
    local before = role_colors(Compiler.compile(theme, OPTS))
    local moved = false
    local function nudged(change)
      local after = role_colors(Compiler.compile(edited(theme, change), OPTS))
      moved = moved or roles_apart(before, after, Color, Color.DISTINCT) >= 3
    end
    for _, field in ipairs({ "bg", "fg", "cursor" }) do
      if theme[field] then
        nudged(function(copy)
          copy[field] = one_step(one_step(copy[field]))
        end)
      end
    end
    for slot = 1, 6 do
      nudged(function(copy)
        copy.ansi[slot] = one_step(one_step(copy.ansi[slot]))
      end)
    end
    recast = recast + (moved and 1 or 0)
  end
  print(("  voice: %d themes recast by a nudge"):format(recast))
  T.ok(recast <= VOICE_RECAST_LIMIT, ("%d themes"):format(recast))
end)

T.test("voice: most themes with a colored cursor speak in it", function()
  local themes = corpus()
  if next(themes) == nil then
    T.skip("no theme corpus at " .. CORPUS)
  end
  local voiced, total = 0, 0
  for _, theme in pairs(themes) do
    local colorscheme = Compiler.compile(theme, OPTS)
    if colorscheme.voice then
      voiced = voiced + 1
      T.ok(colorscheme.voice == "magenta" or colorscheme.casting == 1, "a voice is not recast too")
    end
    total = total + 1
  end
  print(("  voice: %d of %d themes"):format(voiced, total))
  T.ok(voiced >= VOICED_FLOOR, ("%d themes"):format(voiced))
end)

T.test("readable: the leading roles do not share one hue", function()
  -- Keywords, functions and types sit side by side in all code. This bound only
  -- ever moves down.
  local themes = corpus()
  if next(themes) == nil then
    T.skip("no theme corpus at " .. CORPUS)
  end
  local Casting = require("colorrex.roles.casting")
  local Color = require("colorrex.color")
  local LEADS = { "keyword", "func", "type" }
  local function clashes(colorscheme)
    for i = 1, #LEADS do
      for j = i + 1, #LEADS do
        local a, b = colorscheme.roles[LEADS[i]].hex, colorscheme.roles[LEADS[j]].hex
        if Color.chroma(a) >= Color.HUE_MIN_CHROMA and Color.chroma(b) >= Color.HUE_MIN_CHROMA
          and Color.hue_gap(a, b) < Casting.SAME_HUE then
          return true
        end
      end
    end
    return false
  end
  local plain, forced = 0, 0
  for _, theme in pairs(themes) do
    plain = plain + (clashes(Compiler.compile(theme, OPTS)) and 1 or 0)
    forced = forced + (clashes(Compiler.compile(theme, PLAIN)) and 1 or 0)
  end
  print(("  leading roles sharing a hue: %d themes, %d on the convention"):format(plain, forced))
  T.ok(plain <= CLASH_LIMIT, ("%d themes"):format(plain))
  T.ok(forced <= CLASH_LIMIT, ("%d themes on the convention"):format(forced))
end)

T.test("groups: a group defined in two areas is refused", function()
  local Editor = require("colorrex.groups.editor")
  package.loaded["colorrex.groups.editor"] = function(define)
    local groups = Editor(define)
    groups.Comment = {} -- groups/syntax.lua owns this one
    return groups
  end
  package.loaded["colorrex.groups"] = nil
  local ok, err = pcall(function()
    require("colorrex.groups").build(OPTS, Compiler.compile(HARD.one_light, OPTS).styles)
  end)
  package.loaded["colorrex.groups.editor"] = Editor
  package.loaded["colorrex.groups"] = nil
  T.ok(not ok and tostring(err):match("defined in two areas"), tostring(err))
end)

T.test("groups: every link leads to a group that exists, and no link goes in a circle", function()
  local specs = Compiler.compile(HARD.one_light, OPTS).group_specs
  for name in pairs(specs) do
    local seen, current = {}, name
    while specs[current].link do
      T.ok(not seen[current], name .. " links in a circle")
      seen[current] = true
      current = specs[current].link
      T.ok(specs[current], name .. " links to a group that does not exist")
    end
  end
end)

T.test("standalone: groups are written in sorted order, so a theme writes one file", function()
  local text = Compiler.standalone(Compiler.compile(HARD.one_light, OPTS), "x")
  local previous = ""
  for name in text:gmatch('\n  %[?"?([@%w_.]+)"?%]? = {\n') do
    T.ok(name > previous, ("%s came after %s"):format(name, previous))
    previous = name
  end
  T.ok(#previous > 0, "found no groups to compare")
end)

T.test("voice: leaves the base, the comment and the accent where they were", function()
  local themes = corpus()
  themes.one_light, themes.solarized_light = HARD.one_light, HARD.solarized_light
  for name, theme in pairs(themes) do
    local voiced, plain = Compiler.compile(theme, OPTS), Compiler.compile(theme, PLAIN)
    for _, role in ipairs({ "base", "fg", "comment", "accent", "error", "warn", "ok", "info", "hint" }) do
      T.eq(voiced.roles[role].hex, plain.roles[role].hex, name .. " " .. role)
    end
  end
end)

T.test("identity: every theme has a stable id of its own", function()
  local themes = corpus()
  if next(themes) == nil then
    T.skip("no theme corpus at " .. CORPUS)
  end
  local ids, count = {}, 0
  for name, theme in pairs(themes) do
    local first, second = Compiler.compile(theme, OPTS), Compiler.compile(theme, OPTS)
    T.eq(first.id, second.id, name)
    T.eq(first.casting, second.casting, name)
    T.ok(ids[first.id] == nil or ids[first.id] == first.signature, name .. " shares an id with another theme")
    ids[first.id] = first.signature
    count = count + 1
  end
  print(("  %d themes, each with an id"):format(count))
end)

T.test("practical: a style only separates colors when the palette truly cannot", function()
  -- Keeping the promise is not enough. Styles alone would satisfy it for every
  -- theme and leave hundreds of them flat, so this bounds how often they are
  -- needed. It only moves down: raising it means the solver got worse.
  local themes = corpus()
  if next(themes) == nil then
    T.skip("no theme corpus at " .. CORPUS)
  end
  local Color = require("colorrex.color")
  local Roles = require("colorrex.roles")
  local total, flat = 0, 0
  for _, theme in pairs(themes) do
    local roles = Compiler.compile(theme, OPTS).roles
    local names = { "keyword", "func", "string", "type", "number", "operator" }
    local touching = false
    for i = 1, #names do
      for j = i + 1, #names do
        if Color.distance(roles[names[i]].hex, roles[names[j]].hex) < Color.DISTINCT then
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

T.test("practical: a role with a spare color takes it instead of sharing", function()
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
  local colorscheme = Compiler.compile({ ansi = {} }, OPTS)
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
