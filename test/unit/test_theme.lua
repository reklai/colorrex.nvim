local F = require("fixtures")
local T = require("harness")
local Compiler = require("colorrex.compiler")
local Config = require("colorrex.config")
local Theme = require("colorrex.theme")

local ARRANGEMENT_CHECKSUM = 1570080868

T.test("theme: a saved theme compiles to exactly what the live one did", function()
  local theme = F.theme()
  local opts = Config.resolve()
  T.eq(Compiler.compile(Theme.parse(Theme.serialize(theme)), opts).signature, Compiler.compile(theme, opts).signature)
end)

T.test("theme: completeness says what is present", function()
  T.eq(Theme.completeness(F.theme()), "full")
  T.eq(Theme.completeness(F.theme({ cursor = false })), "full")
  T.eq(Theme.completeness(F.theme({ fg = false })), "partial")
  T.eq(Theme.completeness({ ansi = {} }), "none")
end)

T.test("theme: fill leaves nothing missing, and picks the set by scheme", function()
  local filled = Theme.fill({ ansi = {} }, "light")
  T.eq(filled.background, "light")
  for slot = 0, 15 do
    T.ok(filled.ansi[slot], "slot " .. slot)
  end
  T.eq(Theme.fill({ bg = "#000000", ansi = {} }, "light").background, "dark")
end)

T.test("theme: a bad line is skipped, not fatal", function()
  local theme = Theme.parse("palette = 99=#ffffff\nbackground = nope\nforeground = #AABBCC\nsomething else")
  T.eq(theme.fg, "#aabbcc")
  T.eq(theme.bg, nil)
end)

T.test("identity: the fingerprint and the arrangements are pinned, because they recast every theme", function()
  local Casting = require("colorrex.roles.casting")
  T.eq(Casting.fingerprint("colorrex"), 651681459)
  T.eq(#Casting.arrangements(), 2520)
  local rows = {}
  for index, arrangement in ipairs(Casting.arrangements()) do
    rows[index] = table.concat(arrangement)
  end
  T.eq(Casting.fingerprint(table.concat(rows, ",")), ARRANGEMENT_CHECKSUM)
end)

T.test("identity: any two arrangements are at least three roles apart", function()
  local Casting = require("colorrex.roles.casting")
  local list = Casting.arrangements()
  -- Every pair is 3 million comparisons, so check each against a spread of others.
  for i = 1, #list, 7 do
    for j = i + 1, #list, 11 do
      local moved = 0
      for k = 1, #Casting.ROLES do
        moved = moved + (list[i][k] ~= list[j][k] and 1 or 0)
      end
      T.ok(moved >= 3, ("%d and %d are only %d apart"):format(i, j, moved))
    end
  end
  T.eq(table.concat(list[Casting.CONVENTION]), "1234567")
end)

T.test("casting: a palette with nothing wrong keeps the convention", function()
  local Casting = require("colorrex.roles.casting")
  local picks = {
    keyword = { hex = "#bc8cff" }, func = { hex = "#58a6ff" }, type = { hex = "#d29922" },
    failure = { hex = "#e06c75" }, operator = { hex = "#39c5cf" },
    preproc = { hex = "#d2a8ff" }, special = { hex = "#ffa198" },
  }
  T.eq(Casting.cast(picks, "#3fb950"), Casting.CONVENTION)
  T.eq(picks.keyword.hex, "#bc8cff")
end)

local function golds_on_leads(picks)
  local golds = 0
  for _, role in ipairs({ "keyword", "func", "type" }) do
    if picks[role].hex == "#d29922" or picks[role].hex == "#e3b341" then
      golds = golds + 1
    end
  end
  return golds
end

T.test("casting: a clash between the leading roles moves as little as it takes", function()
  local Casting = require("colorrex.roles.casting")
  local picks = {
    keyword = { hex = "#d29922" }, func = { hex = "#e3b341" }, type = { hex = "#bc8cff" },
    failure = { hex = "#58a6ff" }, operator = { hex = "#39c5cf" },
    preproc = { hex = "#d2a8ff" }, special = { hex = "#ffa198" },
  }
  local casting = Casting.cast(picks, "#3fb950")
  T.ok(casting ~= Casting.CONVENTION)
  T.ok(golds_on_leads(picks) <= 1)
  local moved = 0
  for index, source in ipairs(Casting.arrangements()[casting]) do
    moved = moved + (source ~= index and 1 or 0)
  end
  T.eq(moved, 3, "a clash needs one three-way move and no more")
end)

T.test("casting: a role never takes the color of strings when it can avoid it", function()
  local Casting = require("colorrex.roles.casting")
  local picks = {
    keyword = { hex = "#3fb950" }, func = { hex = "#58a6ff" }, type = { hex = "#d29922" },
    failure = { hex = "#e06c75" }, operator = { hex = "#39c5cf" },
    preproc = { hex = "#bc8cff" }, special = { hex = "#ffa198" },
  }
  Casting.cast(picks, "#3fb950")
  T.ok(picks.preproc.hex == "#3fb950" or picks.special.hex == "#3fb950", "it belongs on a role that need not be distinct")
end)

T.test("identity: a background tint alone gives a theme a new id", function()
  local opts = Config.resolve()
  local one = Compiler.compile(F.theme(), opts)
  local two = Compiler.compile(F.theme({ bg = "#1c2028" }), opts)
  T.ok(one.id ~= two.id)
  T.eq(#one.id, 6)
end)

T.test("identity: changing an option never changes a theme's id", function()
  local a = Compiler.compile(F.theme(), Config.resolve())
  local b = Compiler.compile(F.theme(), Config.resolve({ contrast = 4.5, transparent = false, voice = false }))
  T.eq(a.id, b.id)
end)

T.test("transparent: a plugin that blends toward the background still gets the theme's", function()
  -- Normal has no background to read, so nvim-notify would warn and fade to black.
  local colorscheme = Compiler.compile(F.theme({ bg = "#1c2028" }), Config.resolve({ transparent = true }))
  T.eq(colorscheme.groups.Normal.bg, nil)
  T.eq(colorscheme.groups.NotifyBackground.bg, "#1c2028")
end)

T.test("plugins: a notification's level wears the theme's color, as a diagnostic does", function()
  local colorscheme = Compiler.compile(F.theme(), Config.resolve())
  T.eq(colorscheme.groups.NotifyERRORTitle.fg, colorscheme.groups.DiagnosticError.fg)
  T.eq(colorscheme.groups.NotifyWARNIcon.fg, colorscheme.groups.DiagnosticWarn.fg)
  T.eq(colorscheme.groups.NotifyINFOBorder.fg, colorscheme.groups.DiagnosticInfo.fg)
end)

T.test("casting: a background tint changes nothing in code, by default", function()
  local opts = Config.resolve()
  for _, bg in ipairs({ "#1b1f27", "#1c2028", "#30343c" }) do
    local colorscheme = Compiler.compile(F.theme({ bg = bg }), opts)
    T.eq(colorscheme.casting, 1)
    T.eq(colorscheme.roles.keyword.source, "ansi 5")
    T.eq(colorscheme.roles.func.source, "ansi 4")
    T.eq(colorscheme.roles.type.source, "ansi 3")
  end
end)

local VOICED = Config.resolve({ voice = true })

T.test("voice: on by default, and false keeps every theme on the convention", function()
  local cursor = F.theme().ansi[4]
  T.eq(Compiler.compile(F.theme({ cursor = cursor }), Config.resolve()).voice, "blue")
  local plain = Compiler.compile(F.theme({ cursor = cursor }), Config.resolve({ voice = false }))
  T.eq(plain.voice, nil)
  T.eq(plain.roles.keyword.slot, 5)
  T.eq(plain.roles.func.slot, 4)
end)

T.test("voice: a tint in the background leaves it alone", function()
  local one = Compiler.compile(F.theme({ bg = "#1b1f27" }), VOICED)
  local two = Compiler.compile(F.theme({ bg = "#1c2028" }), VOICED)
  T.eq(one.voice, two.voice)
  T.eq(one.roles.keyword.source, two.roles.keyword.source)
end)

T.test("voice: the cursor's nearest color takes the keywords", function()
  local ansi = F.theme().ansi
  for cursor, voice in pairs({
    [ansi[5]] = "magenta", [ansi[1]] = "red", [ansi[4]] = "blue",
    [ansi[2]] = "green", [ansi[3]] = "yellow", [ansi[6]] = "cyan",
  }) do
    local compiled = Compiler.compile(F.theme({ cursor = cursor }), VOICED)
    T.eq(compiled.voice, voice)
    T.eq(compiled.roles.keyword.hex, cursor)
  end
end)

T.test("voice: every row gives each role its own color", function()
  local Casting = require("colorrex.roles.casting")
  T.eq(#Casting.VOICES, 6)
  for _, voice in ipairs(Casting.VOICES) do
    T.eq(voice.roles.keyword, voice.anchor)
    local seen = {}
    for role, slot in pairs(voice.roles) do
      T.ok(not seen[slot], voice.name .. " uses a slot twice, on " .. role)
      seen[slot] = true
    end
  end
end)

T.test("voice: the magenta row is the convention, so that voice changes nothing", function()
  local theme = F.theme({ cursor = F.theme().ansi[5] })
  local voiced = Compiler.compile(theme, VOICED).roles
  local plain = Compiler.compile(theme, Config.resolve()).roles
  for _, role in ipairs({ "keyword", "func", "string", "type", "number", "operator" }) do
    T.eq(voiced[role].hex, plain[role].hex, role)
  end
end)

T.test("voice: a cursor that is not a color of its own leaves the convention", function()
  local theme = F.theme()
  for _, cursor in ipairs({ theme.fg, "#808080" }) do
    T.eq(Compiler.compile(F.theme({ cursor = cursor }), VOICED).voice, nil)
  end
  T.eq(Compiler.compile(F.theme({ cursor = false }), VOICED).voice, nil)
end)

T.test("voice: a row that would collapse two roles gives way to the convention", function()
  local ansi = F.theme().ansi
  ansi[6], ansi[1] = ansi[3], ansi[1] -- the red row puts cyan on types and yellow on strings
  local compiled = Compiler.compile(F.theme({ cursor = ansi[1], ansi = ansi }), VOICED)
  T.eq(compiled.voice, nil)
end)

T.test("voice: a row that would put two leading roles in one hue gives way too", function()
  local Color = require("colorrex.color")
  local ansi = F.theme().ansi
  ansi[2] = "#ffb0b4" -- apart from red, but the red row would put keywords and functions in one hue
  T.ok(Color.distance(ansi[1], ansi[2]) >= Color.DISTINCT)
  local compiled = Compiler.compile(F.theme({ cursor = ansi[1], ansi = ansi }), VOICED)
  T.eq(compiled.voice, nil)
end)

T.test("voice: a row that would blur types and numbers gives way too", function()
  local ansi = F.theme().ansi
  ansi[5] = "#a0e0f0" -- magenta turned cyan: the red row would put numbers in the type's hue
  local compiled = Compiler.compile(F.theme({ cursor = ansi[1], ansi = ansi }), VOICED)
  T.eq(compiled.voice, nil)
end)

T.test("voice: a row that needs a grey gives way too", function()
  local ansi = F.theme().ansi
  ansi[6] = "#808080" -- the red row puts cyan on types
  local compiled = Compiler.compile(F.theme({ cursor = ansi[1], ansi = ansi }), VOICED)
  T.eq(compiled.voice, nil)
end)

T.test("voice: a cursor too faint to have a hue is not a voice", function()
  local Color = require("colorrex.color")
  local Roles = require("colorrex.roles")
  local theme = F.theme({ cursor = "#a08070" })
  T.ok(Roles.own_cursor(theme), "it passes for a color of its own")
  T.ok(Color.chroma(theme.cursor) < Color.HUE_MIN_CHROMA, "but its hue is rounding noise")
  T.eq(Compiler.compile(theme, VOICED).voice, nil)
end)

T.test("voice: nil keeps the color its voice gives it, and owns it", function()
  -- The red voice puts keywords on red, and nil where numbers used to be.
  local compiled = Compiler.compile(F.theme({ cursor = F.theme().ansi[1] }), VOICED)
  local R, G = compiled.roles, compiled.groups
  T.eq(R.failure.slot, 5)
  T.eq(G["@keyword.exception"].fg, R.failure.hex)
  T.eq(G.ColorRexFailure.fg, R.failure.hex)
  T.ok(R.number.hex ~= R.failure.hex, "a number never wears failure's color")
  T.eq(G.Constant.fg, R.number.hex, "a named constant is a value")
end)

T.test("voice: says why, and leaves the comment and the accent alone", function()
  local theme = F.theme({ cursor = F.theme().ansi[4] })
  local voiced, plain = Compiler.compile(theme, VOICED), Compiler.compile(theme, Config.resolve())
  T.eq(voiced.roles.comment.hex, plain.roles.comment.hex)
  T.eq(voiced.roles.accent.hex, plain.roles.accent.hex)
  local said
  for _, note in ipairs(voiced.notes) do
    said = said or (note.code == "voice.cursor" and note.message)
  end
  T.ok(said and said:find("ansi 4", 1, true) and said:find("blue voice", 1, true), tostring(said))
end)

T.test("voice: the status names it", function()
  local Report = require("colorrex.report")
  local status = {
    background = "dark", source = "terminal", completeness = "full", id = "abc123", casting = 1, voice = "red",
    fg = "#ffffff", bg = "#000000", accent = "#ff0000", last = {}, auto = true, adjustments = 0,
  }
  T.ok(Report.status(status):find("abc123, red voice", 1, true))
  status.voice = nil
  T.ok(Report.status(status):find("abc123, casting 1", 1, true))
end)

T.test("landmark: takes the theme's cursor color", function()
  local ansi = F.theme().ansi
  for _, cursor in ipairs({ ansi[2], ansi[3], ansi[4], ansi[5], ansi[6] }) do
    local compiled = Compiler.compile(F.theme({ cursor = cursor }), Config.resolve())
    T.eq(compiled.roles.landmark.hex, cursor)
    T.eq(compiled.groups.ColorRexLandmark.fg, cursor)
    T.eq(compiled.groups.ColorRexLandmark.bold, true)
  end
end)

T.test("landmark: leaves red to errors", function()
  local compiled = Compiler.compile(F.theme({ cursor = F.theme().ansi[1] }), Config.resolve())
  T.eq(compiled.roles.landmark.hex, compiled.roles.func.hex)
  T.eq(compiled.roles.landmark.source, "function")
end)

T.test("landmark: a cursor that is not a color of its own leaves it to functions", function()
  local theme = F.theme()
  -- The last is a color, but too faint to have a hue worth trusting, and sits nearest blue.
  for _, overrides in ipairs({ { cursor = theme.fg }, { cursor = "#808080" }, { cursor = false }, { cursor = "#76889f" } }) do
    local compiled = Compiler.compile(F.theme(overrides), Config.resolve())
    T.eq(compiled.roles.landmark.hex, compiled.roles.func.hex)
  end
end)

T.test("landmark: stays readable when the cursor is too faint on the background", function()
  local Color = require("colorrex.color")
  local opts = Config.resolve()
  local compiled = Compiler.compile(F.theme({ cursor = "#22304a", bg = "#10141c" }), opts)
  T.ok(Color.contrast(compiled.roles.landmark.hex, compiled.filled.bg) >= opts.contrast - 0.01)
end)

T.test("landmark: follows functions in every voice that leaves it to them", function()
  local ansi = F.theme().ansi
  local compiled = Compiler.compile(F.theme({ cursor = ansi[1] }), Config.resolve({ voice = true }))
  T.eq(compiled.voice, "red")
  T.eq(compiled.roles.landmark.hex, compiled.roles.func.hex)
end)

T.test("property: a field has a color of its own, apart from what is read beside it", function()
  local Color = require("colorrex.color")
  local compiled = Compiler.compile(F.theme({ cursor = false }), Config.resolve())
  local R = compiled.roles
  T.eq(R.property.source, "ansi 14")
  T.eq(compiled.groups["@property"].fg, R.property.hex)
  T.eq(compiled.groups["@variable.member"].fg, R.property.hex)
  T.eq(compiled.groups["@lsp.type.property"].fg, R.property.hex)
  T.ok(R.property.hex ~= R.fg.hex and R.property.hex ~= R.func.hex)
  T.eq(compiled.groups["@variable"].fg, R.fg.hex)
  T.ok(Color.distance(R.property.hex, R.func.hex) >= Color.DISTINCT)
end)

T.test("property: moves off a hue that a voice gave to functions", function()
  local Casting = require("colorrex.roles.casting")
  local ansi = F.theme().ansi
  local R = Compiler.compile(F.theme({ cursor = ansi[4] }), Config.resolve()).roles
  T.eq(R.func.slot, 6, "the blue voice puts functions on cyan")
  T.ok(not Casting.same_hue(R.property.hex, R.func.hex), R.property.source)
end)

T.test("property: stays off keywords and types too", function()
  local Casting = require("colorrex.roles.casting")
  local ansi = F.theme().ansi
  ansi[14] = ansi[5]
  ansi[13] = ansi[3]
  local R = Compiler.compile(F.theme({ cursor = false, ansi = ansi }), Config.resolve()).roles
  T.ok(R.property.source == "ansi 12" or R.property.source == "ansi 10", R.property.source)
  T.ok(not Casting.same_hue(R.property.hex, R.keyword.hex))
  T.ok(not Casting.same_hue(R.property.hex, R.type.hex))
end)

T.test("property: too near plain text to show, it does not pretend", function()
  -- All five are real colors, off every leading hue, and just beside a tinted fg.
  local ansi = F.theme().ansi
  for _, slot in ipairs({ 10, 11, 12, 13, 14 }) do
    ansi[slot] = "#a8dcba"
  end
  local compiled = Compiler.compile(F.theme({ fg = "#a8d8b8", cursor = false, ansi = ansi }), Config.resolve())
  T.eq(compiled.roles.property.source, "fg")
end)

T.test("property: selections have to stay readable under fields too", function()
  local Roles = require("colorrex.roles")
  local compiled = Compiler.compile(F.theme(), Config.resolve())
  local names = {}
  for _, item in ipairs(Roles.surface_text(compiled.roles, compiled.filled.bg)) do
    names[item.name] = true
  end
  T.ok(names.property)
end)

T.test("property: a monochrome theme keeps fields as text", function()
  local ansi = {}
  for slot = 0, 15 do
    ansi[slot] = "#909090"
  end
  local compiled = Compiler.compile(F.theme({ ansi = ansi, cursor = false }), Config.resolve())
  T.eq(compiled.roles.property.hex, compiled.filled.fg)
end)

T.test("practical: what shape already says stays quiet", function()
  local compiled = Compiler.compile(F.theme({ cursor = false }), Config.resolve())
  local G, R = compiled.groups, compiled.roles
  for _, group in ipairs({ "Operator", "@operator", "@keyword.operator", "@variable.builtin", "@variable.parameter.builtin" }) do
    T.eq(G[group].fg, R.muted.hex, group)
  end
end)

T.test("servers: a token speaks only where a server knows what a grammar cannot", function()
  local Meanings = require("colorrex.meanings")
  local compiled = Compiler.compile(F.theme({ cursor = false }), Config.resolve())
  local G, R = compiled.groups, compiled.roles
  -- The ones that restate the grammar are empty, and not missing: Neovim would link a
  -- missing one back to a capture, over the grammar's own reading.
  for _, token in ipairs(Meanings.SILENT_TOKENS) do
    T.eq(next(G["@lsp.type." .. token]), nil, token)
  end
  for token, name in pairs(Meanings.TOKENS) do
    T.eq(G["@lsp.type." .. token].fg, R[Meanings.ROLE[name]].hex, token)
  end
  -- A parameter is a name with a server or without one, and the grammar's, which sees
  -- `cb(x)` called, stands.
  T.eq(next(G["@lsp.type.parameter"]), nil)
  T.eq(G["@variable.parameter"].fg, G["@variable"].fg)
  -- clangd's `comment` is code an `#if` turned off, and reads as a comment; anywhere
  -- else a server's comment is over a comment the grammar already drew.
  T.eq(compiled.group_specs["@lsp.type.comment.c"].link, "Comment")
  T.eq(compiled.group_specs["@lsp.type.comment.cpp"].link, "Comment")
  T.eq(compiled.group_specs["@lsp.type.comment.lua"], nil)
  -- What a server knows beyond what a word is never changes its color.
  T.eq(G["@lsp.mod.deprecated"].fg, nil)
end)

T.test("practical: red means something, so a builtin is what it is", function()
  local compiled = Compiler.compile(F.theme({ cursor = false }), Config.resolve())
  local G, R = compiled.groups, compiled.roles
  T.eq(G["@function.builtin"].fg, R.func.hex)
  T.eq(G["@constant.builtin"].fg, R.number.hex, "a value, until the lexicon says it is nil")
  T.eq(G["@module.builtin"].fg, R.type.hex)
  T.eq(G["@attribute.builtin"].fg, R.type.hex)
end)

T.test("practical: words that only color can separate keep it", function()
  local compiled = Compiler.compile(F.theme({ cursor = false }), Config.resolve())
  local G, R = compiled.groups, compiled.roles
  T.eq(G["@property"].fg, R.property.hex)
  T.eq(G["@function.method.call"].fg, R.func.hex)
  T.eq(G["@type"].fg, R.type.hex)
  T.eq(G["@variable"].fg, R.fg.hex)
  T.eq(G["@string.escape"].fg, R.operator.hex)
end)

T.test("practical: a tag reads as a kind of element, and never as failure", function()
  local compiled = Compiler.compile(F.theme({ cursor = false }), Config.resolve())
  local G, R = compiled.groups, compiled.roles
  T.eq(G["@tag"].fg, R.type.hex)
  T.eq(G["@tag.builtin"].fg, R.type.hex)
  T.eq(G["@tag.attribute"].fg, R.property.hex)
  T.ok(G["@tag"].fg ~= R.failure.hex)
end)

T.test("practical: a symbol is a value, and a word operator reads as its symbol", function()
  local compiled = Compiler.compile(F.theme({ cursor = false }), Config.resolve())
  local G, R = compiled.groups, compiled.roles
  T.eq(G["@string.special.symbol"].fg, R.number.hex)
  T.eq(G["@keyword.operator"].fg, G["@operator"].fg)
  T.eq(G["@keyword.conditional.ternary"].fg, G["@operator"].fg)
  -- The color escapes wear is theirs alone among what text holds.
  for _, capture in ipairs({ "@string.escape", "@string.regexp", "@character.special", "@punctuation.special" }) do
    T.eq(G[capture].fg, R.operator.hex, capture)
  end
end)

T.test("roles: red reaches code, as failure and nothing else", function()
  local compiled = Compiler.compile(F.theme(), Config.resolve())
  local groups = compiled.groups
  T.eq(groups["@keyword.exception"].fg, "#e06c75")
  T.eq(groups.ColorRexFailure.fg, "#e06c75")
  T.eq(groups.Exception.fg, "#e06c75")
  T.eq(groups.Constant.fg, groups["@constant"].fg)
  T.ok(groups.Constant.fg ~= "#e06c75", "constants are values")
end)

T.test("diagnostics: severity reads by shape as well as by color", function()
  local G = Compiler.compile(F.theme(), Config.resolve()).groups
  T.ok(G.DiagnosticUnderlineError.undercurl)
  T.ok(G.DiagnosticUnderlineWarn.underdashed)
  T.ok(G.DiagnosticUnderlineInfo.underdotted)
  T.ok(G.DiagnosticUnderlineHint.underdotted)
  T.ok(not G.SpellBad.undercurl, "a misspelling never takes an error's shape")
end)

T.test("light: a loud grey comment eases below the code, keeping its hue", function()
  -- One Half Light's bright black is a strong grey, louder on white than its code.
  local Color = require("colorrex.color")
  local theme = F.theme({ fg = "#383a42", bg = "#fafafa", cursor = false, ansi = {
    [0] = "#383a42", [1] = "#e45649", [2] = "#50a14f", [3] = "#c18401", [4] = "#0184bc", [5] = "#a626a4",
    [6] = "#0997b3", [7] = "#fafafa", [8] = "#4f525e", [9] = "#e06c75", [10] = "#98c379", [11] = "#e5c07b",
    [12] = "#61afef", [13] = "#c678dd", [14] = "#56b6c2", [15] = "#ffffff" } })
  local roles = Compiler.compile(theme, Config.resolve()).roles
  local comment = Color.contrast(roles.comment.hex, "#fafafa")
  T.ok(comment < Color.contrast(roles.keyword.hex, "#fafafa"), "quieter than the code")
  T.ok(comment >= 2.5 - 0.01, "and still readable")
  T.eq(roles.comment.from, "#4f525e")
  T.ok(Color.hue_gap(roles.comment.hex, "#4f525e") < 12 or Color.chroma("#4f525e") < 0.03, "the same grey, only lighter")
end)

T.test("dark: a comment derived from fg also sits below the code", function()
  -- Apple System Colors: bright black is too faint to use, and a blend of white into
  -- the background came out at 5.3:1, louder than half its code.
  local Color = require("colorrex.color")
  local theme = F.theme({ fg = "#ffffff", bg = "#1e1e1e", cursor = false, ansi = {
    [0] = "#1a1a1a", [1] = "#cc372e", [2] = "#26a439", [3] = "#cdac08", [4] = "#0869cb", [5] = "#9647bf",
    [6] = "#479ec2", [7] = "#98989d", [8] = "#464646", [9] = "#ff453a", [10] = "#32d74b", [11] = "#ffd60a",
    [12] = "#0a84ff", [13] = "#bf5af2", [14] = "#76d6ff", [15] = "#ffffff" } })
  local roles = Compiler.compile(theme, Config.resolve()).roles
  local code = {}
  for _, name in ipairs({ "keyword", "func", "string", "type", "failure", "operator" }) do
    code[#code + 1] = Color.contrast(roles[name].hex, "#1e1e1e")
  end
  table.sort(code)
  local comment = Color.contrast(roles.comment.hex, "#1e1e1e")
  T.ok(comment < code[3], ("%.2f against code at %.2f"):format(comment, code[3]))
  T.ok(comment >= 2.5 - 0.01, "and still readable")
  T.eq(roles.comment.source, "fg over bg")
end)

T.test("chosen: every list marks the item Enter acts on the same way, apart from a selection", function()
  local colorscheme = Compiler.compile(F.theme(), Config.resolve())
  local G, chosen = colorscheme.groups, colorscheme.roles.accent_soft.hex
  for _, name in ipairs({ "PmenuSel", "TelescopeSelection", "BlinkCmpMenuSelection", "QuickFixLine", "WildMenu" }) do
    T.eq(G[name].bg, chosen, name)
    T.ok(G[name].bold, name .. " is bold")
  end
  T.ok(G.Visual.bg ~= chosen, "a text selection keeps its own surface")
  T.ok(G.CursorLine.bg ~= chosen, "the cursor line keeps its own surface")
  T.eq(G.PmenuMatchSel.fg, colorscheme.roles.select_accent.hex)
end)

T.test("debugger: the stopped line shows, and is not the cursor line", function()
  local colorscheme = Compiler.compile(F.theme(), Config.resolve())
  local G = colorscheme.groups
  T.eq(G.debugPC.bg, colorscheme.roles.stopped.hex)
  T.ok(G.debugPC.bg ~= G.CursorLine.bg and G.debugPC.bg ~= G.Visual.bg)
end)

T.test("gitsigns: a hunk preview's changed words wear the diff's, not reverse video", function()
  local specs = Compiler.compile(F.theme(), Config.resolve()).group_specs
  for _, name in ipairs({ "GitSignsAddInline", "GitSignsChangeInline", "GitSignsDeleteInline" }) do
    T.eq(specs[name].link, "DiffText", name)
  end
end)

T.test("suggestions: text that is not in the file is neither code nor a comment", function()
  local Color = require("colorrex.color")
  for _, theme in ipairs({ F.theme(), F.theme({ cursor = false }) }) do
    local colorscheme = Compiler.compile(theme, Config.resolve())
    local G, roles, bg = colorscheme.groups, colorscheme.roles, colorscheme.filled.bg
    T.eq(G.ComplHint.fg, roles.predicted.hex)
    T.ok(G.ComplHint.italic)
    T.ok(G.ComplHint.fg ~= G.Comment.fg, "a suggestion looks like a comment")
    T.ok(Color.contrast(roles.predicted.hex, bg) <= Color.contrast(roles.comment.hex, bg) + 0.01,
      "a suggestion is louder than a comment")
    T.eq(colorscheme.group_specs.BlinkCmpGhostText.link, "ComplHint")
    T.eq(G.PreInsert.fg, nil, "provisional text lost its own colors")
    T.ok(G.PreInsert.underdotted)
  end
end)

T.test("negation: wears control's color, in bold", function()
  local G = Compiler.compile(F.theme(), Config.resolve()).groups
  T.eq(G.ColorRexNegation.fg, G["@keyword"].fg)
  T.ok(G.ColorRexNegation.bold)
end)
