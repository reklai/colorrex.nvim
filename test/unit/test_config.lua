local T = require("harness")
local Config = require("colorrex.config")

T.test("config: a typo fails loudly", function()
  T.ok(not pcall(Config.resolve, { transparant = true }))
  T.ok(not pcall(Config.resolve, { contrast = "high" }))
  T.ok(not pcall(Config.resolve, { contrast = 9 }))
end)

T.test("config: a renamed option says what it is called now", function()
  local ok, err = pcall(Config.resolve, { force_unique = true })
  T.ok(not ok)
  T.ok(tostring(err):find("'voice'", 1, true), err)
end)
