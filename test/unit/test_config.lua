local T = require("harness")
local Config = require("colorrex.config")

T.test("config: a typo fails loudly", function()
  T.ok(not pcall(Config.resolve, { transparant = true }))
  T.ok(not pcall(Config.resolve, { contrast = "high" }))
  T.ok(not pcall(Config.resolve, { contrast = 9 }))
end)

T.test("config: groups are checked by shape, and the first mistake is named", function()
  local function refused(groups, says)
    local ok, err = pcall(Config.resolve, { groups = groups })
    T.ok(not ok, "accepted: " .. says)
    T.ok(tostring(err):find(says, 1, true), tostring(err))
  end
  refused({ "Normal" }, "keyed by highlight group names")
  refused({ Mine = "accent" }, "'Mine' must be a table")
  refused({ Mine = { fg = "#ff0000" } }, "must name a role")
  refused({ Mine = { fg = 3 } }, "fg must name a role")
  refused({ Mine = { colour = "accent" } }, "unknown key 'colour'")
  refused({ Mine = { bold = "yes" } }, "bold must be true or false")
  refused({ Mine = { link = "Comment", bold = true } }, "can set nothing else")
  refused({ Mine = { blend = 300 } }, "blend must be a number")
end)

T.test("config: groups are copied, so a table changed after setup changes nothing", function()
  local mine = { Mine = { fg = "accent", bold = true } }
  local config = Config.resolve({ groups = mine })
  mine.Mine.fg = "error"
  mine.Other = { fg = "warn" }
  T.eq(config.groups.Mine.fg, "accent")
  T.eq(config.groups.Other, nil)
  T.eq(next(Config.resolve().groups), nil, "and there are none by default")
end)

T.test("config: a setup written before these options existed means what it meant", function()
  -- Every option an installed config could already hold, at every value it could hold.
  local config = Config.resolve({ transparent = false, contrast = 4.5, voice = false, chunks = true, auto = false })
  T.eq(config.transparent, false)
  T.eq(config.contrast, 4.5)
  T.eq(config.voice, false)
  T.eq(config.chunks, true)
  T.eq(config.auto, false)
  -- What was added since asks for nothing: no groups, and icons that can be turned off.
  T.eq(next(config.groups), nil)
  T.eq(config.icons, true)
  T.eq(Config.resolve({ icons = false }).icons, false)
end)

T.test("config: a renamed option says what it is called now", function()
  local ok, err = pcall(Config.resolve, { force_unique = true })
  T.ok(not ok)
  T.ok(tostring(err):find("'voice'", 1, true), err)
end)
