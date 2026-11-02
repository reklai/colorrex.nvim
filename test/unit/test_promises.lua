-- The promises must be able to fail. Without this, "819 themes kept the promises"
-- means nothing: a check that always passes would produce the same line.
local F = require("fixtures")
local T = require("harness")
local Compiler = require("colorrex.compiler")
local Config = require("colorrex.config")

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
  local Roles = require("colorrex.roles")
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
  local clash = F.theme().ansi
  clash[5], clash[4] = "#d29922", "#e3b341"
  T.ok(has(F.theme({ ansi = clash }), "faithful.recast"))
  T.ok(Roles)
end)

T.test("repair: a role that has to move stays near its own color", function()
  -- Cyan sits too close to green, and the theme has a bright cyan to spare. The
  -- farthest color would separate them too, and turn every operator red. Bright blue
  -- is slightly nearer by distance, but a cyan role has a cyan to go to.
  local ansi = F.theme().ansi
  ansi[2], ansi[6], ansi[14] = "#7cbfa0", "#66c2b5", "#86d9cc"
  ansi[4], ansi[12] = "#729fc0", "#8fb8d4"
  local roles = Compiler.compile(F.theme({ fg = "#c8d3d3", bg = "#14181a", ansi = ansi }), OPTS).roles
  T.eq(roles.operator.slot, 14)
  T.eq(roles.string.slot, 2)
end)

T.test("repair: the lesser role moves, so a theme keeps its types", function()
  -- On a light background, bright yellow has to darken and lands on yellow. Types
  -- gone red would read as errors, so numbers are the ones to go.
  local roles = Compiler.compile(F.theme({
    fg = "#4a382c", bg = "#f9efe6", cursor = "#c05a35",
    ansi = {
      [0] = "#4a382c", [1] = "#bd4a2d", [2] = "#5f8a3a", [3] = "#a97a16",
      [4] = "#47709f", [5] = "#9d5680", [6] = "#3e8570", [7] = "#ead9c8",
      [8] = "#857262", [9] = "#d55c3c", [10] = "#72a248", [11] = "#c18f22",
      [12] = "#5985b5", [13] = "#b36b95", [14] = "#4d9d86", [15] = "#fefaf5",
    },
  }), OPTS).roles
  T.eq(roles.type.slot, 3)
  T.eq(roles.number.slot, 1)
end)

T.test("number: wears the constant's color, because it is a constant", function()
  local roles = Compiler.compile(F.theme(), OPTS).roles
  T.eq(roles.number.hex, roles.constant.hex)
  T.ok(roles.number.hex ~= roles.type.hex)
end)

T.test("number: gives way to the roles a theme is known by", function()
  -- Four colors for six roles: red is the only home left for functions, so a number
  -- that took it would leave keywords and functions as one color.
  local function palette(red, green, yellow, purple)
    local ansi = F.theme().ansi
    ansi[1], ansi[9], ansi[11] = red, yellow, yellow
    ansi[2], ansi[6], ansi[10], ansi[14] = green, green, green, green
    ansi[3], ansi[4], ansi[5], ansi[12], ansi[13] = yellow, purple, purple, purple, purple
    return F.theme({ ansi = ansi })
  end
  local roles = Compiler.compile(palette("#ff6767", "#61ffca", "#ffca85", "#a277ff"), OPTS).roles
  T.eq(roles.func.hex, "#ff6767")
  T.ok(roles.number.hex ~= roles.func.hex)
  T.ok(roles.keyword.hex ~= roles.func.hex)
  T.ok(roles.keyword.hex ~= roles.string.hex)
end)

T.test("number: past yellow and a taken constant, goes to bright red", function()
  -- Red reads as the keyword here and yellow has no bright partner to spare, so the
  -- number cannot follow the constant, and the constant keeps a color of its own.
  local ansi = F.theme().ansi
  ansi[1], ansi[11] = ansi[5], ansi[3]
  local compiled = Compiler.compile(F.theme({ ansi = ansi }), OPTS)
  T.eq(compiled.roles.number.slot, 9)
  T.eq(compiled.groups.Constant.fg, compiled.roles.constant.hex)
  T.ok(compiled.roles.constant.hex ~= compiled.roles.number.hex)
end)

T.test("warn: wears bright yellow, the only role left to show it", function()
  local theme = F.theme()
  T.eq(Compiler.compile(theme, OPTS).roles.warn.slot, 11)
end)

T.test("repair: with its own slots taken, a role takes the nearest color left", function()
  -- Bright cyan is as close to the strings as cyan is, so operators have to leave
  -- home. Bright blue is next door. Red would separate them too.
  local ansi = F.theme().ansi
  ansi[2], ansi[6], ansi[14] = "#7cbfa0", "#66c2b5", "#80c8a6"
  ansi[4], ansi[12] = "#729fc0", "#8fb8d4"
  local roles = Compiler.compile(F.theme({ fg = "#c8d3d3", bg = "#14181a", ansi = ansi }), OPTS).roles
  T.eq(roles.operator.slot, 12)
end)

T.test("repair: a palette too small to separate everything still opens a gap", function()
  -- Atom One Light. Each bright slot repeats its normal one, so nothing stands apart
  -- from every role, and leaving it alone would give numbers the color of types.
  local roles = Compiler.compile(F.theme({
    fg = "#2a2c33", bg = "#f9f9f9", cursor = "#bbbbbb",
    ansi = {
      [0] = "#000000", [1] = "#de3e35", [2] = "#3f953a", [3] = "#d2b67c",
      [4] = "#2f5af3", [5] = "#950095", [6] = "#3f953a", [7] = "#bbbbbb",
      [8] = "#000000", [9] = "#de3e35", [10] = "#3f953a", [11] = "#d2b67c",
      [12] = "#2f5af3", [13] = "#a00095", [14] = "#3f953a", [15] = "#ffffff",
    },
  }), OPTS).roles
  T.ok(roles.number.hex ~= roles.type.hex, "numbers read as types")
end)

local Color = require("colorrex.color")

--- A dark theme with faint comments, the case a selection is hardest on.
local function faint_comments()
  local ansi = F.theme().ansi
  ansi[8] = "#5f5c58"
  return Compiler.compile(F.theme({ fg = "#d6d2cc", bg = "#161616", cursor = "#e05d3a", ansi = ansi }), OPTS)
end

--- A light theme with all its color at the contrast floor.
local function at_the_floor()
  local ansi = {}
  for slot = 0, 15 do
    ansi[slot] = "#8e8e8e"
  end
  ansi[1], ansi[5], ansi[4], ansi[3], ansi[6] = "#c44f36", "#9c5589", "#4472ac", "#ab7c1c", "#3a8878"
  ansi[9], ansi[13], ansi[12], ansi[11], ansi[2], ansi[10] =
    "#c44f36", "#9c5589", "#4472ac", "#ab7c1c", "#578c42", "#578c42"
  ansi[14] = "#4c9cb0" -- too faint for this background, so it lands right on the floor
  return Compiler.compile(F.theme({ fg = "#1a1a1a", bg = "#f4f4f4", cursor = "#1a1a1a", ansi = ansi }), OPTS)
end

T.test("surface: a selection eases off until comments stay readable", function()
  local colorscheme = faint_comments()
  local roles = colorscheme.roles
  T.ok(roles.visual.mix < 0.18, "the selection did not move")
  -- 1.90 at full strength. This theme runs out of room just under the 2.25 target.
  T.ok(Color.contrast(roles.comment.hex, roles.visual.hex) >= 2.2, "comments are too faint when selected")
  T.ok(roles.visual.source:find("at " .. math.floor(roles.visual.mix * 100 + 0.5) .. "%%"), roles.visual.source)
  local noted = false
  for _, note in ipairs(colorscheme.notes) do
    noted = noted or note.code == "faithful.surface"
  end
  T.ok(noted, "the adjustment left no note")
end)

T.test("surface: a selection stops easing while it can still be seen", function()
  -- These comments would need the selection gone to reach their target.
  local roles = faint_comments().roles
  T.ok(Color.contrast(roles.visual.hex, roles.base.hex) >= 1.2, "the selection faded out")
end)

T.test("surface: a selection stays stronger than the cursor line", function()
  local roles = at_the_floor().roles
  T.ok(roles.visual.mix > roles.cursorline.mix)
end)

T.test("surface: colored text in a float is readable on the float", function()
  local colorscheme = at_the_floor()
  T.ok(colorscheme.roles.float_info.hex ~= colorscheme.roles.info.hex, "nothing needed lifting, so this proves nothing")
  for _, name in ipairs({ "DiagnosticFloatingError", "DiagnosticFloatingInfo", "FloatTitle", "PmenuMatch" }) do
    local group = colorscheme.groups[name]
    T.ok(Color.contrast(group.fg, group.bg) >= 3 - 0.01, name)
  end
end)

T.test("surface: the lift for a float leaves the same color everywhere else", function()
  local colorscheme = at_the_floor()
  T.eq(colorscheme.groups.DiagnosticInfo.fg, colorscheme.roles.info.hex)
  T.eq(colorscheme.groups.Title.fg, colorscheme.roles.accent.hex)
end)

T.test("surface: changed words and deleted lines set a text color that reads", function()
  local colorscheme = faint_comments()
  for _, name in ipairs({ "DiffText", "DiffDelete", "Search" }) do
    local group = colorscheme.groups[name]
    T.ok(group.fg, name .. " leaves its text to whatever is underneath")
    T.ok(Color.contrast(group.fg, group.bg) >= 3, name)
  end
end)

T.test("surface: on a mid-tone background, text picks the side that reads", function()
  local ansi = F.theme().ansi
  ansi[3], ansi[11] = "#ffff55", "#ffff55"
  local colorscheme = Compiler.compile(F.theme({ fg = "#a0a0ff", bg = "#4040e0", ansi = ansi }), OPTS)
  for name, role in pairs({ Search = "on_search", DiffText = "on_diff_text" }) do
    local group = colorscheme.groups[name]
    T.eq(group.fg, colorscheme.roles[role].hex)
    T.ok(Color.contrast(group.fg, group.bg) >= math.max(
      Color.contrast("#a0a0ff", group.bg), Color.contrast("#4040e0", group.bg)) - 0.01, name)
  end
end)

T.test("surface: when the two lifts for quiet text disagree, it falls back to fg", function()
  -- On this red the cursor line and a float sit either side of the turning point.
  local colorscheme = Compiler.compile(F.theme({ fg = "#c7cee9", bg = "#d91d01" }), OPTS)
  T.eq(colorscheme.roles.muted.hex, "#c7cee9")
  T.eq(next(codes(colorscheme)), nil)
end)

T.test("promises: a theme is not faulted for its own faint foreground", function()
  -- Equal luminance: the fg is unreadable before any surface is involved.
  local colorscheme = Compiler.compile(F.theme({ fg = "#3d4e0a", bg = "#0f08ea" }), OPTS)
  T.eq(codes(colorscheme)["faithful.surface"], nil)
end)

T.test("promises: text too faint on a surface that could ease is caught", function()
  local colorscheme = faint_comments()
  local visual = colorscheme.roles.visual
  visual.mix, visual.hex = 0.18, Color.mix("#161616", visual.over, 0.18)
  T.ok(codes(colorscheme)["faithful.surface"])
end)

T.test("promises: a selection fainter than the cursor line is caught", function()
  local colorscheme = good()
  colorscheme.roles.visual.mix = colorscheme.roles.cursorline.mix
  T.ok(codes(colorscheme)["faithful.surface"])
end)

T.test("promises: text too faint on its own fill is caught", function()
  local colorscheme = good()
  colorscheme.groups.Pmenu.fg = colorscheme.groups.Pmenu.bg
  T.ok(codes(colorscheme)["faithful.surface"])
end)

T.test("promises: a readable fg on a fill it cannot read on is caught", function()
  local colorscheme = good()
  colorscheme.groups.Search.fg = colorscheme.filled.fg
  colorscheme.groups.Search.bg = colorscheme.filled.fg
  T.ok(codes(colorscheme)["faithful.surface"])
end)

T.test("promises: lines are not held to the standard of text", function()
  local colorscheme = good()
  colorscheme.groups.FloatBorder.fg = colorscheme.groups.FloatBorder.bg
  colorscheme.groups.MsgSeparator.fg = colorscheme.groups.MsgSeparator.bg
  T.eq(codes(colorscheme)["faithful.surface"], nil)
end)

T.test("report: a failed promise is an error, and adjustments are listed", function()
  local Report = require("colorrex.report")
  local colorscheme = good()
  local text, level = Report.check(colorscheme, { { code = "faithful.base", message = "fg or bg was altered" } })
  T.ok(text:match("BROKEN faithful.base"), text)
  T.eq(level, "error")
  T.ok(select(1, Report.check(colorscheme, {})):match("promises kept"))
end)

T.test("report: an unanswered theme is called out", function()
  local Report = require("colorrex.report")
  local text = Report.check(Compiler.compile({ ansi = {} }, OPTS), {})
  T.ok(text:match("not the terminal's full theme"), text)
end)
