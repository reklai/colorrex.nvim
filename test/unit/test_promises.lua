-- The promises must be able to fail. Without this, "819 themes kept the promises"
-- means nothing: a check that always passes would produce the same line.
local F = require("fixtures")
local T = require("harness")
local Compiler = require("color-rex.compiler")
local Config = require("color-rex.config")

local OPTS = Config.resolve()

local function good()
  return Compiler.compile(F.theme(), OPTS)
end

local function codes(colorscheme, opts)
  local out = {}
  for _, failure in ipairs(Compiler.check(colorscheme, opts or OPTS)) do
    out[failure.code] = true
  end
  return out
end

T.test("promises: an untouched colorscheme keeps them all", function()
  T.eq(next(codes(good())), nil)
end)

T.test("promises: altering fg or bg is caught", function()
  local colorscheme = good()
  colorscheme.roles.base = { hex = "#000000", source = "bg" }
  T.ok(codes(colorscheme)["faithful.base"])
end)

T.test("promises: a group holding a color nothing derived is caught", function()
  local colorscheme = good()
  colorscheme.groups.Comment = { fg = "#123456" }
  T.ok(codes(colorscheme)["faithful.stray"])
end)

T.test("promises: a syntax role with no ANSI slot is caught", function()
  local colorscheme = good()
  colorscheme.roles.string = { hex = colorscheme.roles.string.hex, source = "invented" }
  T.ok(codes(colorscheme)["faithful.source"])
end)

T.test("promises: a lifted color that drifted in hue is caught", function()
  local colorscheme = good()
  local role = colorscheme.roles.string
  role.from = "#ff0000"
  role.slot = 1
  colorscheme.filled.ansi[1] = "#ff0000"
  role.hex = "#00c800"
  T.ok(codes(colorscheme)["faithful.hue"])
end)

T.test("promises: a role below the contrast floor is caught, on each list of roles", function()
  for _, name in ipairs({ "keyword", "preproc", "error", "accent" }) do
    local colorscheme = good()
    colorscheme.roles[name] = { hex = colorscheme.filled.bg, slot = 1, source = "ansi 1" }
    T.ok(codes(colorscheme)["faithful.contrast"], name)
  end
end)

T.test("promises: a comment louder than the text is caught", function()
  local colorscheme = good()
  colorscheme.filled.fg = "#555555"
  colorscheme.roles.fg.hex = "#555555"
  colorscheme.roles.comment = { hex = "#ffffff", source = "ansi 8" }
  T.ok(codes(colorscheme)["faithful.comment"])
end)

T.test("promises: a comment too faint to read is caught", function()
  local colorscheme = good()
  colorscheme.roles.comment = { hex = colorscheme.filled.bg, source = "ansi 8" }
  T.ok(codes(colorscheme)["faithful.comment"])
end)

T.test("promises: two roles alike in color and style are caught", function()
  local colorscheme = good()
  colorscheme.roles.func = colorscheme.roles.string
  colorscheme.styles.func = colorscheme.styles.string
  T.ok(codes(colorscheme)["unique.collision"])
end)

T.test("notes: each adjustment the solver makes leaves one", function()
  local Roles = require("color-rex.roles")
  local function has(theme, code)
    for _, note in ipairs(Compiler.compile(theme, OPTS).notes) do
      if note.code == code then
        return true
      end
    end
    return false
  end
  T.ok(has(F.theme({ cursor = false }), "unique.accent"))
  T.ok(has(F.theme({ fg = "#303030", bg = "#fafafa" }), "faithful.lifted"))
  local ansi = F.theme().ansi
  ansi[8] = "#000000"
  T.ok(has(F.theme({ ansi = ansi }), "faithful.comment"))
  local grey = {}
  for slot = 0, 15 do
    grey[slot] = "#808080"
  end
  grey[5], grey[4] = "#ff5555", "#ff5656"
  T.ok(has({ fg = "#d0d0d0", bg = "#101010", ansi = grey }, "unique.style"))
  local pair = F.theme().ansi
  pair[4] = pair[5]
  T.ok(has(F.theme({ ansi = pair }), "unique.reassigned"))
  T.ok(Roles)
end)

T.test("report: a failed promise is an error, and adjustments are listed", function()
  local Report = require("color-rex.report")
  local colorscheme = good()
  local text, level = Report.check(colorscheme, { { code = "faithful.base", message = "fg or bg was altered" } })
  T.ok(text:match("BROKEN faithful.base"), text)
  T.eq(level, "error")
  T.ok(select(1, Report.check(colorscheme, {})):match("promises kept"))
end)

T.test("report: an unanswered theme is called out", function()
  local Report = require("color-rex.report")
  local text = Report.check(Compiler.compile({ ansi = {} }, OPTS), {})
  T.ok(text:match("not the terminal's full theme"), text)
end)
