local F = require("fixtures")
local T = require("harness")
local Compiler = require("color-rex.compiler")
local Config = require("color-rex.config")
local Theme = require("color-rex.theme")

T.test("theme: a saved theme compiles to exactly what the live one did", function()
  local theme = F.theme()
  local opts = Config.resolve()
  T.eq(Compiler.compile(Theme.parse(Theme.serialize(theme)), opts).key, Compiler.compile(theme, opts).key)
end)

T.test("theme: completeness says what is present", function()
  T.eq(Theme.completeness(F.theme()), "full")
  T.eq(Theme.completeness(F.theme({ cursor = false })), "full")
  T.eq(Theme.completeness(F.theme({ fg = false })), "partial")
  T.eq(Theme.completeness({ ansi = {} }), "none")
  T.eq(Theme.completeness(nil), "none")
end)

T.test("theme: fill leaves nothing missing, and picks the set by scheme", function()
  local filled = Theme.fill({}, "light")
  T.eq(filled.background, "light")
  for slot = 0, 15 do
    T.ok(filled.ansi[slot], "slot " .. slot)
  end
  T.eq(Theme.fill({ bg = "#000000" }, "light").background, "dark")
end)

T.test("theme: a bad line is skipped, not fatal", function()
  local theme = Theme.parse("palette = 99=#ffffff\nbackground = nope\nforeground = #AABBCC\nsomething else")
  T.eq(theme.fg, "#aabbcc")
  T.eq(theme.bg, nil)
end)

T.test("identity: a background tint alone gives a theme a new fingerprint", function()
  local Casting = require("color-rex.compiler.casting")
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

T.test("identity: turning it on or off repaints", function()
  local on = Compiler.compile(F.theme(), Config.resolve())
  local off = Compiler.compile(F.theme(), Config.resolve({ identity = false }))
  T.ok(on.key ~= off.key)
end)

T.test("identity: red reaches code, as constants", function()
  local groups = Compiler.compile(F.theme(), Config.resolve()).groups
  T.eq(groups.Constant.fg, groups["@constant"].fg)
  T.eq(groups.Constant.fg, "#e06c75")
end)
