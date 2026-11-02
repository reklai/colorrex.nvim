local F = require("fixtures")
local T = require("harness")
local App = require("colorrex.app")
local Commands = require("colorrex.commands")
local Config = require("colorrex.config")

local function start()
  local host = F.fake_host()
  local app = App.new(host, Config.resolve())
  host.on_apply = function() app:load() end
  return app, host
end

local function answer(app, theme)
  app.terminal.feed(F.reply(theme))
end

T.test("commands: bare :ColorRex is sync, and a keybind runs the same entry", function()
  local app, host = start()
  app:load()
  answer(app, F.theme())
  Commands.run(app, {}, false)
  T.eq(#host.sent, 2)
  T.ok(app.announce)
end)

T.test("commands: bad input returns a message and runs nothing", function()
  local app = start()
  app:load()
  T.ok(Commands.run(app, { "nope" }, false):match("unknown command"))
  T.ok(Commands.run(app, { "status", "extra" }, false):match("at most 0"))
  T.ok(Commands.run(app, { "sync" }, false):match("unknown command"), "syncing has no subcommand")
end)

T.test("commands: completion offers names only in the first position", function()
  T.eq(Commands.complete("s", "ColorRex s")[1], "status")
  T.eq(#Commands.complete("", "ColorRex explain "), 0)
end)
