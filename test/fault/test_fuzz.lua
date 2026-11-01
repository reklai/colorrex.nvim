-- Hostile input. Seeds are fixed so that any failure replays exactly.
local F = require("fixtures")
local T = require("harness")
local Compiler = require("color-rex.compiler")
local Config = require("color-rex.config")
local Protocol = require("color-rex.terminal.protocol")
local Terminal = require("color-rex.terminal")
local Theme = require("color-rex.theme")

local OPTS = Config.resolve()

local function bytes(rng, n)
  local out = {}
  for i = 1, n do
    out[i] = string.char(rng(256))
  end
  return table.concat(out)
end

local function hex(rng)
  return string.format("#%02x%02x%02x", rng(256), rng(256), rng(256))
end

T.test("fuzz: the protocol parser survives 200,000 garbage sequences", function()
  local rng = T.rng(1)
  local PREFIXES = { "", "\027]", "\027]21;", "\027]21;foreground=", "\027]21;1=rgb:", "\027]11;", "\027]11;rgb:", "\027[" }
  for _ = 1, 200000 do
    local input = PREFIXES[rng(#PREFIXES) + 1] .. bytes(rng, rng(40))
    local event = Protocol.parse(input)
    if event and event.kind == "theme" then
      for slot = 0, 15 do
        local color = event.theme.ansi[slot]
        T.ok(color == nil or color:match("^#%x%x%x%x%x%x$"), "a theme must hold only valid colors")
      end
    end
  end
end)

T.test("fuzz: non-string and oversized input is not an event", function()
  T.eq(Protocol.parse(nil), nil)
  T.eq(Protocol.parse(42), nil)
  T.eq(Protocol.parse({}), nil)
  T.eq(Protocol.parse(("\027]21;" .. ("f"):rep(100000))), nil)
end)

T.test("fuzz: the theme file parser survives garbage", function()
  local rng = T.rng(2)
  for _ = 1, 20000 do
    local text = bytes(rng, rng(200)):gsub("[%z]", "=")
    local theme = Theme.parse("palette = " .. text .. "\nbackground = " .. text)
    Compiler.compile(theme, OPTS)
  end
end)

T.test("fuzz: 20,000 random palettes keep every promise", function()
  local rng = T.rng(3)
  for round = 1, 20000 do
    local theme = { fg = hex(rng), bg = hex(rng), cursor = hex(rng), ansi = {} }
    for slot = 0, 15 do
      theme.ansi[slot] = hex(rng)
    end
    local failures = Compiler.check(Compiler.compile(theme, OPTS), OPTS)
    if #failures > 0 then
      error(("round %d bg=%s: %s"):format(round, theme.bg, failures[1].message), 0)
    end
  end
end)

T.test("fuzz: palettes with missing fields compile and judge cleanly", function()
  local rng = T.rng(4)
  for _ = 1, 5000 do
    local theme = { ansi = {} }
    if rng(2) == 0 then theme.fg = hex(rng) end
    if rng(2) == 0 then theme.bg = hex(rng) end
    if rng(2) == 0 then theme.cursor = hex(rng) end
    for slot = 0, 15 do
      if rng(2) == 0 then theme.ansi[slot] = hex(rng) end
    end
    local failures = Compiler.check(Compiler.compile(theme, OPTS), OPTS)
    if #failures > 0 then
      error(failures[1].message, 0)
    end
  end
end)

T.test("fuzz: any order of events always leaves the query able to run", function()
  local rng = T.rng(5)
  for _ = 1, 2000 do
    local host = F.fake_host()
    local settled = 0
    local terminal = Terminal.new({
      send = host.send,
      after = host.after,
      on_settle = function() settled = settled + 1 end,
      on_change = function() end,
    })
    local replies = { F.reply(F.theme()), F.reply(F.theme({ fg = false, bg = false })), "\027]11;rgb:fa/fa/fa" }
    for _ = 1, 40 do
      local action = rng(4)
      if action == 0 then
        terminal.query()
      elseif action == 1 then
        terminal.feed(replies[rng(#replies) + 1])
      elseif action == 2 then
        host.advance(rng(600))
      else
        terminal.feed(bytes(rng, rng(12)))
      end
    end
    -- A queued rerun may start one fresh query while time passes. Three passes
    -- cover that; a machine that is truly wedged stays stuck through all three.
    for _ = 1, 3 do
      host.advance(1000)
    end
    T.eq(terminal.phase(), "idle", "must never wedge in a query")
    terminal.query()
    terminal.feed(replies[1])
    T.eq(terminal.phase(), "idle")
  end
end)
