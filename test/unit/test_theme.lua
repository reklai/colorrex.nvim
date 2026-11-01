local F = require("fixtures")
local T = require("harness")
local Compiler = require("color-rex.compiler")
local Config = require("color-rex.config")
local Theme = require("color-rex.theme")

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
  local Casting = require("color-rex.roles.casting")
  T.eq(Casting.fingerprint("color-rex"), 209064343)
  T.eq(#Casting.ARRANGEMENTS, 2520)
  local rows = {}
  for index, arrangement in ipairs(Casting.ARRANGEMENTS) do
    rows[index] = table.concat(arrangement)
  end
  T.eq(Casting.fingerprint(table.concat(rows, ",")), ARRANGEMENT_CHECKSUM)
end)

T.test("identity: any two arrangements are at least three roles apart", function()
  local Casting = require("color-rex.roles.casting")
  local list = Casting.ARRANGEMENTS
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
  T.eq(table.concat(list[Casting.FIXED]), "1234567")
end)

T.test("identity: with room to, casting keeps the leading roles out of one hue", function()
  local Casting = require("color-rex.roles.casting")
  for fingerprint = 0, 200 do
    local picks = {
      keyword = { hex = "#bc8cff" }, func = { hex = "#58a6ff" }, type = { hex = "#d29922" },
      number = { hex = "#e3b341" }, operator = { hex = "#39c5cf" },
      preproc = { hex = "#d2a8ff" }, special = { hex = "#ffa198" },
    }
    Casting.cast(picks, "#3fb950", fingerprint)
    local golds = 0
    for _, role in ipairs({ "keyword", "func", "type" }) do
      if picks[role].hex == "#d29922" or picks[role].hex == "#e3b341" then
        golds = golds + 1
      end
    end
    T.ok(golds <= 1, ("fingerprint %d put both golds on the leading roles"):format(fingerprint))
  end
end)

T.test("identity: casting never gives a syntax role the color of strings when it can avoid it", function()
  local Casting = require("color-rex.roles.casting")
  for fingerprint = 0, 200 do
    local picks = {
      keyword = { hex = "#bc8cff" }, func = { hex = "#58a6ff" }, type = { hex = "#d29922" },
      number = { hex = "#e3b341" }, operator = { hex = "#39c5cf" },
      preproc = { hex = "#3fb950" }, special = { hex = "#ffa198" },
    }
    Casting.cast(picks, "#3fb950", fingerprint)
    T.eq(picks.preproc.hex, "#3fb950", "the lookalike stays on a role that need not be distinct")
  end
end)

T.test("identity: a background tint alone gives a theme a new fingerprint", function()
  local Casting = require("color-rex.roles.casting")
  local opts = Config.resolve()
  local one = Compiler.compile(F.theme(), opts)
  local two = Compiler.compile(F.theme({ bg = "#1c2028" }), opts)
  T.ok(one.id ~= two.id)
  T.eq(#one.id, 6)
  T.ok(one.casting >= 1 and one.casting <= #Casting.ARRANGEMENTS)
end)

T.test("identity: changing an option never changes a theme's casting", function()
  local a = Compiler.compile(F.theme(), Config.resolve())
  local b = Compiler.compile(F.theme(), Config.resolve({ contrast = 4.5, transparent = false }))
  T.eq(a.casting, b.casting)
  T.eq(a.id, b.id)
end)

T.test("identity: turned off, every theme uses the same fixed mapping", function()
  local opts = Config.resolve({ identity = false })
  for _, bg in ipairs({ "#1b1f27", "#1c2028", "#30343c" }) do
    local colorscheme = Compiler.compile(F.theme({ bg = bg }), opts)
    T.eq(colorscheme.casting, 1)
    T.eq(colorscheme.roles.keyword.source, "ansi 5")
    T.eq(colorscheme.roles.func.source, "ansi 4")
    T.eq(colorscheme.roles.type.source, "ansi 3")
  end
end)

T.test("identity: red reaches code, as constants", function()
  local groups = Compiler.compile(F.theme(), Config.resolve()).groups
  T.eq(groups.Constant.fg, groups["@constant"].fg)
  T.eq(groups.Constant.fg, "#e06c75")
end)
