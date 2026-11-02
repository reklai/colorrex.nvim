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
    number = { hex = "#e06c75" }, operator = { hex = "#39c5cf" },
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
    number = { hex = "#58a6ff" }, operator = { hex = "#39c5cf" },
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
  for _, fingerprint in ipairs({ false, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }) do
    local picks = {
      keyword = { hex = "#3fb950" }, func = { hex = "#58a6ff" }, type = { hex = "#d29922" },
      number = { hex = "#e06c75" }, operator = { hex = "#39c5cf" },
      preproc = { hex = "#bc8cff" }, special = { hex = "#ffa198" },
    }
    Casting.cast(picks, "#3fb950", fingerprint or nil)
    T.ok(picks.preproc.hex == "#3fb950" or picks.special.hex == "#3fb950", "it belongs on a role that need not be distinct")
  end
end)

T.test("force_unique: reads as well as the convention, from any fingerprint", function()
  local Casting = require("colorrex.roles.casting")
  for fingerprint = 0, 200 do
    local picks = {
      keyword = { hex = "#bc8cff" }, func = { hex = "#58a6ff" }, type = { hex = "#d29922" },
      number = { hex = "#e3b341" }, operator = { hex = "#39c5cf" },
      preproc = { hex = "#d2a8ff" }, special = { hex = "#ffa198" },
    }
    Casting.cast(picks, "#3fb950", fingerprint)
    T.ok(golds_on_leads(picks) <= 1, ("fingerprint %d put both golds on the leading roles"):format(fingerprint))
  end
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
  local b = Compiler.compile(F.theme(), Config.resolve({ contrast = 4.5, transparent = false, force_unique = true }))
  T.eq(a.id, b.id)
end)

T.test("force_unique: only chooses between results that look different", function()
  -- Three roles hold one color, so many arrangements differ only in which of them
  -- went where. A fingerprint picking between those would not be picking anything.
  local Casting = require("colorrex.roles.casting")
  local colors = {
    keyword = "#c678dd", func = "#61afef", type = "#e5c07b", number = "#e06c75",
    operator = "#56b6c2", preproc = "#56b6c2", special = "#56b6c2",
  }
  local seen = {}
  for fingerprint = 0, 199 do
    local picks = {}
    for role, hex in pairs(colors) do
      picks[role] = { hex = hex }
    end
    local casting = Casting.cast(picks, "#98c379", fingerprint)
    local result = {}
    for index, role in ipairs(Casting.ROLES) do
      result[index] = picks[role].hex
    end
    local key = table.concat(result)
    T.ok(seen[key] == nil or seen[key] == casting, "two castings, one result")
    seen[key] = casting
  end
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

T.test("force_unique: the same tint recasts the theme", function()
  local opts = Config.resolve({ force_unique = true })
  local one = Compiler.compile(F.theme({ bg = "#1b1f27" }), opts)
  local two = Compiler.compile(F.theme({ bg = "#1c2028" }), opts)
  T.ok(one.casting ~= two.casting)
end)

T.test("roles: red reaches code, as constants", function()
  local groups = Compiler.compile(F.theme(), Config.resolve()).groups
  T.eq(groups.Constant.fg, groups["@constant"].fg)
  T.eq(groups.Constant.fg, "#e06c75")
end)
