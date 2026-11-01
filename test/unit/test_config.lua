local T = require("harness")
local Config = require("color-rex.config")

T.test("config: a typo fails loudly", function()
  T.ok(not pcall(Config.resolve, { transparant = true }))
  T.ok(not pcall(Config.resolve, { contrast = "high" }))
  T.ok(not pcall(Config.resolve, { contrast = 9 }))
end)
