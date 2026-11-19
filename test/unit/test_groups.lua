-- A user's own groups, and the roles they are written in: the same vocabulary the
-- built-in groups use, held to the same rule.
local F = require("fixtures")
local T = require("harness")
local App = require("colorrex.app")
local Compiler = require("colorrex.compiler")
local Config = require("colorrex.config")
local Report = require("colorrex.report")

local function compile(groups, theme)
  local config = Config.resolve({ groups = groups })
  return Compiler.compile(theme or F.theme(), config), config
end

T.test("groups: a group of your own takes its colors from roles", function()
  local colorscheme = compile({ FlashLabel = { fg = "on_accent", bg = "accent", bold = true } })
  local group = colorscheme.groups.FlashLabel
  T.eq(group.fg, colorscheme.roles.on_accent.hex)
  T.eq(group.bg, colorscheme.roles.accent.hex)
  T.ok(group.bold)
  T.eq(colorscheme.custom.FlashLabel, "new")
end)

T.test("groups: it follows the theme, as every other group does", function()
  local groups = { Mine = { fg = "accent" } }
  local first = compile(groups, F.theme({ cursor = "#ff79c6" }))
  local second = compile(groups, F.theme({ cursor = "#50fa7b" }))
  T.ok(first.groups.Mine.fg ~= second.groups.Mine.fg, "the accent moved, and the group went with it")
  T.eq(second.groups.Mine.fg, second.roles.accent.hex)
end)

T.test("groups: a name colorrex defines is replaced, and nothing else moves", function()
  local plain = compile({})
  local colorscheme = compile({ Comment = { fg = "muted" }, CursorLine = { link = "Visual" } })
  T.eq(colorscheme.groups.Comment.fg, colorscheme.roles.muted.hex)
  T.eq(colorscheme.groups.Comment.italic, nil, "replaced whole, not merged")
  T.eq(colorscheme.groups.CursorLine.link, "Visual")
  T.eq(colorscheme.custom.Comment, "replaced")
  local moved = 0
  for name, spec in pairs(plain.groups) do
    if name ~= "Comment" and name ~= "CursorLine" then
      for key, value in pairs(spec) do
        moved = moved + (colorscheme.groups[name][key] ~= value and 1 or 0)
      end
    end
  end
  T.eq(moved, 0)
  T.eq(colorscheme.signature, plain.signature, "the theme is the same theme")
end)

T.test("groups: a role that does not exist is refused by name, before anything changes", function()
  local config = Config.resolve({ groups = { Mine = { fg = "acent" } } })
  local ok, err = pcall(App.validate, config)
  T.ok(not ok)
  T.ok(tostring(err):find("group 'Mine' names an unknown role 'acent'", 1, true), tostring(err))
  T.ok(tostring(err):find("colorrex-roles", 1, true), "and says where the roles are listed")
  T.ok(pcall(App.validate, Config.resolve({ groups = { Mine = { fg = "accent" } } })))
end)

T.test("groups: every role roles() hands out can be named in a group", function()
  local app = App.new(F.fake_host(), Config.resolve())
  local groups = {}
  for name in pairs(app:roles()) do
    groups["Mine_" .. name] = { fg = name }
  end
  T.ok(next(groups), "there are roles")
  T.ok(pcall(App.validate, Config.resolve({ groups = groups })))
end)

T.test("groups: yours are judged by the promises, on what can be judged", function()
  -- Text on its own fill is measurable, whoever wrote it.
  local colorscheme, config = compile({ Mine = { fg = "base", bg = "cursorline" } })
  local found = false
  for _, failure in ipairs(Compiler.check(colorscheme, config)) do
    found = found or failure.message:find("Mine is", 1, true) ~= nil
  end
  T.ok(found, "unreadable text on its own fill is reported")

  -- A bare fill under a new name is the user's to place: only they know what is drawn there.
  colorscheme, config = compile({ MyBar = { bg = "statusline" } })
  T.eq(#Compiler.check(colorscheme, config), 0)

  -- A replacement of ours is still judged as ours was: code lies on a selection.
  colorscheme, config = compile({ Visual = { bg = "statusline" } })
  local failures = Compiler.check(colorscheme, config)
  T.ok(#failures > 0 and failures[1].message:find("Visual lies under code", 1, true), "a selection that never eases")
end)

T.test("groups: the standalone file holds them, in the theme's colors", function()
  local colorscheme, config = compile({ FlashLabel = { fg = "on_accent", bg = "accent" }, Linked = { link = "Comment" } })
  local source = Compiler.standalone(colorscheme, "mine")
  T.ok(source:find("FlashLabel", 1, true))
  T.ok(source:find("Linked", 1, true))
  T.eq(#Compiler.check(colorscheme, config), 0)
end)

T.test("groups: explain says which are yours", function()
  local colorscheme = compile({ FlashLabel = { fg = "on_accent", bg = "accent" }, Comment = { fg = "muted" } })
  local text = Report.explain(colorscheme, { "FlashLabel" })
  T.ok(text:find("FlashLabel, from your setup", 1, true), text)
  T.ok(text:find("role accent", 1, true), text)
  T.ok(Report.explain(colorscheme, { "Comment" }):find("Comment, from your setup", 1, true))
  T.ok(not Report.explain(colorscheme, { "String" }):find("from your setup", 1, true))
end)

T.test("groups: setup can add and remove them while running", function()
  local host = F.fake_host()
  local app = App.new(host, Config.resolve())
  host.on_apply = function() app:load() end
  app:load()
  T.eq(host.shown.groups.Mine, nil)
  app:configure(Config.resolve({ groups = { Mine = { fg = "accent" } } }))
  app:repaint()
  T.eq(host.shown.groups.Mine.fg, app:roles().accent)
  app:configure(Config.resolve())
  app:repaint()
  T.eq(host.shown.groups.Mine, nil)
end)

T.test("roles: every role has a color, and the table is the caller's to keep", function()
  local app = App.new(F.fake_host(), Config.resolve())
  local roles = app:roles()
  for _, name in ipairs({ "fg", "base", "accent", "keyword", "func", "string", "type", "failure", "comment", "muted",
    "error", "warn", "ok", "info", "hint", "element", "border", "visual", "cursorline", "on_accent", "accent_soft" }) do
    T.ok(type(roles[name]) == "string" and roles[name]:match("^#%x%x%x%x%x%x$"), name)
  end
  roles.accent = "#000000"
  T.ok(app:roles().accent ~= "#000000", "a change to the table changes nothing here")
end)

T.test("roles: base is the background even when transparent leaves Normal without one", function()
  local host = F.fake_host()
  local app = App.new(host, Config.resolve({ transparent = true }))
  host.on_apply = function() app:load() end
  app:load()
  app.terminal.feed(F.reply(F.theme({ bg = "#282a36" })))
  T.eq(host.shown.groups.Normal.bg, nil, "the terminal paints it")
  T.eq(app:roles().base, "#282a36", "and a plugin that needs it can still be told")
end)

T.test("roles: they are the new theme's by the time a repaint is seen", function()
  local host = F.fake_host()
  local app = App.new(host, Config.resolve())
  local seen = {}
  host.on_apply = function()
    app:load()
    seen[#seen + 1] = app:roles().base -- what a ColorScheme autocommand would read
  end
  app:load()
  app.terminal.feed(F.reply(F.theme({ bg = "#282a36" })))
  app:sync("manual")
  app.terminal.feed(F.reply(F.theme({ bg = "#fafafa", fg = "#383a42" })))
  T.eq(seen[#seen - 1], "#282a36")
  T.eq(seen[#seen], "#fafafa")
end)
