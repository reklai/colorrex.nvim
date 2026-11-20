-- Strays: the colors on screen that are not the theme's, and the families that are
-- given the theme's instead.
local F = require("fixtures")
local T = require("harness")
local App = require("colorrex.app")
local Color = require("colorrex.color")
local Compiler = require("colorrex.compiler")
local Config = require("colorrex.config")
local Report = require("colorrex.report")

local function compiled(theme, opts)
  return Compiler.compile(theme or F.theme(), Config.resolve(opts))
end

--- What Neovim would hold: every group of ours, and `extra` beside them.
local function live_of(colorscheme, extra)
  local live = {}
  for name, spec in pairs(colorscheme.groups) do
    live[name] = { fg = spec.fg, bg = spec.bg, sp = spec.sp, link = spec.link }
  end
  for name, spec in pairs(extra or {}) do
    live[name] = spec
  end
  return live
end

--- A blend in RGB, as a plugin does it.
local function rgb_blend(from, to, t)
  local out = "#"
  for index = 2, 6, 2 do
    local a, b = tonumber(from:sub(index, index + 1), 16), tonumber(to:sub(index, index + 1), 16)
    out = out .. ("%02x"):format(math.floor(a + (b - a) * t + 0.5))
  end
  return out
end

T.test("strays: nothing colorrex defines is a stray, in any option", function()
  for _, opts in ipairs({ {}, { transparent = false }, { voice = false }, { contrast = 4.5 } }) do
    local colorscheme = compiled(nil, opts)
    T.eq(#Compiler.strays(colorscheme, live_of(colorscheme)), 0)
  end
  local light = compiled(F.theme({ fg = "#383a42", bg = "#fafafa" }))
  T.eq(#Compiler.strays(light, live_of(light)), 0)
end)

T.test("strays: a color from nowhere in the theme is found, with the role nearest it", function()
  local colorscheme = compiled()
  local strays = Compiler.strays(colorscheme, live_of(colorscheme, {
    RainbowRed = { fg = "#cc241d" },
    SomeFill = { bg = "#0b2a13" },
  }))
  T.eq(#strays, 2)
  T.eq(strays[1].group, "RainbowRed")
  T.eq(strays[1].key, "fg")
  T.eq(strays[1].hex, "#cc241d")
  local red = colorscheme.roles[strays[1].nearest].hex
  T.ok(Color.hue_gap(red, "#cc241d") < 40, "the nearest text role to a red is a red: " .. strays[1].nearest)
  T.eq(strays[2].group, "SomeFill")
  T.eq(strays[2].nearest, "base", "and a fill is offered a surface")
end)

T.test("strays: a group that links is judged where it leads, and a theme color is never one", function()
  local colorscheme = compiled()
  local roles = colorscheme.roles
  local strays = Compiler.strays(colorscheme, live_of(colorscheme, {
    Linked = { link = "Comment" },
    InTheme = { fg = roles.accent.hex:upper(), bg = roles.element.hex, sp = roles.error.hex },
    Slot = { fg = colorscheme.filled.ansi[7] },
    Bare = {},
  }))
  T.eq(#strays, 0)
end)

T.test("strays: a color dimmed toward the background still follows the theme", function()
  local colorscheme = compiled()
  local theme, roles = colorscheme.filled, colorscheme.roles
  local strays = Compiler.strays(colorscheme, live_of(colorscheme, {
    Dimmed = { fg = rgb_blend(theme.bg, roles.keyword.hex, 0.4) },
    Tinted = { bg = rgb_blend(theme.bg, roles.error.hex, 0.15) },
    Faded = { fg = rgb_blend(theme.fg, roles.func.hex, 0.5) },
  }))
  T.eq(#strays, 0)
end)

T.test("strays: a theme color darkened or lightened still follows the theme, but black is not a shade", function()
  -- gitsigns dims a staged sign toward black; bufferline shades the background for its tabs.
  local colorscheme = compiled()
  local roles = colorscheme.roles
  local strays = Compiler.strays(colorscheme, live_of(colorscheme, {
    Darkened = { fg = rgb_blend("#000000", roles.ok.hex, 0.5) },
    Shaded = { bg = rgb_blend("#000000", colorscheme.filled.bg, 0.8) },
    Lightened = { fg = rgb_blend("#ffffff", roles.keyword.hex, 0.6) },
    Black = { bg = "#000000" },
    White = { fg = "#ffffff" },
  }))
  T.eq(#strays, 2)
  T.eq(strays[1].group, "Black")
  T.eq(strays[2].group, "White")
end)

T.test("strays: a backdrop's black is a shade of what is under it, and is left as shipped", function()
  local colorscheme = compiled()
  local strays = Compiler.strays(colorscheme, live_of(colorscheme, {
    MasonBackdrop = { bg = "#000000" }, LazyBackdrop = { bg = "#000000" }, SnacksBackdrop = { bg = "#000000" },
    FzfLuaBackdrop = { bg = "#000000" },
    PinkBackdrop = { bg = "#ff007c" }, -- a color someone chose is still one
    BackdropTitle = { bg = "#000000" }, -- and so is black anywhere else
  }))
  T.eq(#strays, 2)
  T.eq(strays[1].group, "BackdropTitle")
  T.eq(strays[2].group, "PinkBackdrop")
end)

T.test("strays: the same result every time, whatever order the groups come in", function()
  local colorscheme = compiled()
  local extra = {}
  for index = 1, 40 do
    extra[("Plugin%02d"):format(index)] = { fg = ("#%02x10%02x"):format(index * 5, 255 - index * 5) }
  end
  local first = Compiler.strays(colorscheme, live_of(colorscheme, extra))
  local second = Compiler.strays(colorscheme, live_of(colorscheme, extra))
  T.ok(#first > 0)
  for index, stray in ipairs(first) do
    T.eq(second[index].group, stray.group)
    T.eq(second[index].nearest, stray.nearest)
    T.ok(index == 1 or first[index - 1].group <= stray.group, "sorted by name")
  end
end)

T.test("report: strays are counted whole, and a plugin's many groups are one line", function()
  local colorscheme = compiled()
  local extra = { RainbowRed = { fg = "#cc241d" }, ["@odd.name"] = { sp = "#123456" } }
  for index = 1, 30 do
    extra[("ToyIcon%02d"):format(index)] = { fg = ("#%02x20%02x"):format(index * 8, 250 - index * 8) }
  end
  local strays = Compiler.strays(colorscheme, live_of(colorscheme, extra))
  local text = Report.check(colorscheme, {}, strays, Config.resolve())
  T.ok(text:find("32 highlights from elsewhere wear colors that are not this theme's", 1, true), text)
  T.ok(text:find("ToyIcon* (30 groups), such as ToyIcon01", 1, true), text)
  T.ok(text:find("RainbowRed  fg #cc241d (nearest role: ", 1, true), text)
  T.ok(not text:find("ToyIcon02", 1, true), "the family is not listed out")
  -- The fix it shows can be pasted as it is, even for a name that is not an identifier.
  local example = text:match("\n  (groups = %b{})")
  T.ok(example, text)
  local groups = assert(loadstring("return { " .. example .. " }"))().groups
  T.ok(pcall(App.validate, Config.resolve({ groups = groups })), example)
  T.ok(groups["@odd.name"], "the first stray by name is the example: " .. example)
end)

T.test("report: lualine on a theme of its own is told about ours, and only then", function()
  local colorscheme = compiled()
  local extra = {}
  for _, mode in ipairs({ "normal", "insert", "visual", "replace", "command", "inactive" }) do
    extra["lualine_a_" .. mode] = { fg = "#1c1c1c", bg = "#5f87af" }
  end
  local text = Report.check(colorscheme, {}, Compiler.strays(colorscheme, live_of(colorscheme, extra)), Config.resolve())
  T.ok(text:find("lualine_a_* (6 groups)", 1, true), text)
  T.ok(text:find('theme = "colorrex"', 1, true), text)
  local other = Compiler.strays(colorscheme, live_of(colorscheme, { RainbowRed = { fg = "#cc241d" } }))
  T.ok(not Report.check(colorscheme, {}, other, Config.resolve()):find("lualine", 1, true))
end)

T.test("report: a clean screen says so, and a check with no screen says nothing of it", function()
  local colorscheme = compiled()
  T.ok(Report.check(colorscheme, {}, {}):find("every highlight on screen wears this theme's colors", 1, true))
  T.ok(not Report.check(colorscheme, {}):find("highlight", 1, true))
end)

T.test("report: a long list stops, and says there is more", function()
  local colorscheme = compiled()
  local extra = {}
  for index = 1, 26 do
    extra[string.char(64 + index) .. "plugin"] = { fg = ("#%02x40%02x"):format(index * 9, 250 - index * 9) }
  end
  local strays = Compiler.strays(colorscheme, live_of(colorscheme, extra))
  local text = Report.check(colorscheme, {}, strays, Config.resolve())
  T.ok(text:find(("%d highlights"):format(#strays), 1, true), text)
  T.ok(text:find("and more; fix these and run it again", 1, true), text)
end)

-- Icons -------------------------------------------------------------------------------

T.test("icons: a fixed color takes the theme's nearest in hue, and a grey goes quiet", function()
  local colorscheme = compiled()
  local roles = colorscheme.roles
  local changes = Compiler.adopt(colorscheme, {
    DevIconLua = { fg = "#51a0cf" },
    DevIconRs = { fg = "#dea584" },
    DevIconDefault = { fg = "#6d8086" },
    DevIconLinked = { link = "Comment" },
    DevIconDone = { fg = roles.func.hex },
    lualine_x_filetype_DevIconLua_normal = { fg = "#51a0cf", bg = roles.statusline.hex },
    NotAnIcon = { fg = "#51a0cf" },
  })
  T.ok(changes.DevIconLua and Color.hue_gap(changes.DevIconLua, "#51a0cf") < 30, "a blue stays a blue")
  T.ok(Compiler.strays(colorscheme, { X = { fg = changes.DevIconLua } })[1] == nil, "and is the theme's own")
  T.ok(changes.DevIconRs ~= changes.DevIconLua, "two hues stay two colors")
  T.eq(changes.DevIconDefault, roles.muted.hex)
  T.eq(changes.DevIconLinked, nil)
  T.eq(changes.DevIconDone, nil, "already the theme's, so left alone")
  T.eq(changes.lualine_x_filetype_DevIconLua_normal, changes.DevIconLua, "lualine's copy of an icon follows it")
  T.eq(changes.NotAnIcon, nil, "nothing outside the family is touched")
end)

T.test("icons: every color handed out is one the theme's code is written in", function()
  local rng = T.rng(7)
  for _, theme in ipairs({ F.theme(), F.theme({ fg = "#383a42", bg = "#fafafa" }), { ansi = {} } }) do
    local colorscheme = compiled(theme)
    for _ = 1, 200 do
      local hex = ("#%02x%02x%02x"):format(rng(256), rng(256), rng(256))
      local own = Compiler.adopt(colorscheme, { DevIconX = { fg = hex } }).DevIconX
      T.ok(own == nil or #Compiler.strays(colorscheme, { X = { fg = own } }) == 0, hex .. " became " .. tostring(own))
      if own then
        T.ok(Color.contrast(own, colorscheme.filled.bg) >= math.min(3.0, Color.contrast(colorscheme.filled.fg,
          colorscheme.filled.bg)) - 0.01 or own == colorscheme.roles.muted.hex, hex .. " became unreadable " .. own)
      end
    end
  end
end)

T.test("icons: none takes the color of an error or of failure, so red keeps its one meaning", function()
  local reds = { "#e44d26", "#f54d27", "#cc3e44", "#701516", "#e8274b", "#ff3e00", "#9c4221", "#ff0000" }
  local one_red = F.theme() -- one red for both slots, as TokyoNight has
  one_red.ansi[1], one_red.ansi[9] = "#f7768e", "#f7768e"
  local themes = { F.theme(), F.theme({ cursor = false }), F.theme({ fg = "#383a42", bg = "#fafafa" }), one_red }
  for _, theme in ipairs(themes) do
    for _, opts in ipairs({ {}, { voice = false } }) do
      local colorscheme = compiled(theme, opts)
      local roles = colorscheme.roles
      for _, hex in ipairs(reds) do
        local own = Compiler.adopt(colorscheme, { DevIconX = { fg = hex } }).DevIconX
        T.ok(own ~= roles.error.hex and own ~= roles.failure.hex, hex .. " took the color of an error: " .. tostring(own))
        T.ok(own ~= roles.muted.hex, hex .. " lost its color, when the theme had another to give")
      end
    end
  end
end)

T.test("icons: a palette with red as its only color has none to give, so icons go quiet", function()
  local ansi = {}
  for slot = 0, 15 do
    ansi[slot] = "#808080"
  end
  ansi[1], ansi[9] = "#cc3333", "#ff5555"
  local colorscheme = compiled({ fg = "#d0d0d0", bg = "#101010", ansi = ansi })
  T.eq(Compiler.adopt(colorscheme, { DevIconX = { fg = "#e44d26" } }).DevIconX, colorscheme.roles.muted.hex)
end)

local function start(opts, live)
  local host = F.fake_host({ live = live })
  local app = App.new(host, Config.resolve(opts))
  host.on_apply = function() app:load() end
  return app, host
end

local ICONS = { DevIconDefault = "#6d8086", DevIconLua = "#51a0cf" }
local function icons()
  local out = {}
  for name, fg in pairs(ICONS) do
    out[name] = { fg = fg }
  end
  return out
end

T.test("icons: icons defined before the colorscheme are the theme's after it loads", function()
  local app, host = start({ icons = true }, icons())
  app:load()
  T.eq(host.live.DevIconDefault.fg, app:roles().muted)
  T.ok(host.live.DevIconLua.fg ~= "#51a0cf")
end)

T.test("icons: icons a plugin defines later are noticed when Neovim settles, at the cost of one lookup", function()
  local app, host = start({ icons = true }, {})
  app:load()
  host.handlers.settled()
  host.handlers.settled()
  T.eq(host.reads, 0, "no icons, so nothing was read")
  host.live = icons() -- the plugin loads
  host.handlers.settled()
  T.eq(host.reads, 1)
  T.ok(host.live.DevIconLua.fg ~= "#51a0cf")
  for _ = 1, 5 do
    host.handlers.settled()
  end
  T.eq(host.reads, 1, "and once they are the theme's, settling reads nothing more")
end)

T.test("icons: a new theme recolors them from the plugin's colors, not from the last theme's", function()
  local app, host = start({ icons = true }, icons())
  app:load()
  app.terminal.feed(F.reply(F.theme()))
  local first = host.live.DevIconLua.fg
  -- The plugin puts its own colors back on every ColorScheme, before the deferred look.
  host.defer = function(fn)
    host.live = icons()
    fn()
  end
  app:sync("manual")
  app.terminal.feed(F.reply(F.theme({ fg = "#383a42", bg = "#fafafa", ansi = {
    [0] = "#383a42", [1] = "#e45649", [2] = "#50a14f", [3] = "#c18401", [4] = "#0184bc", [5] = "#a626a4",
    [6] = "#0997b3", [7] = "#fafafa", [8] = "#4f525e", [9] = "#e06c75", [10] = "#98c379", [11] = "#e5c07b",
    [12] = "#61afef", [13] = "#c678dd", [14] = "#56b6c2", [15] = "#ffffff" } })))
  local second = host.live.DevIconLua.fg
  T.ok(second ~= first and second ~= "#51a0cf", "the light theme's blue, not the dark one's")
  T.eq(#Compiler.strays(app.colorscheme, { X = { fg = second } }), 0)
end)

T.test("icons: a plugin that puts its colors back with no colorscheme in between is caught again", function()
  -- nvim-web-devicons does this whenever 'background' is set, even to what it was.
  local app, host = start({ icons = true }, icons())
  app:load()
  local own = host.live.DevIconLua.fg
  for _ = 1, 3 do
    host.live = icons()
    host.handlers.settled()
    T.eq(host.live.DevIconLua.fg, own)
    T.eq(host.live.DevIconDefault.fg, app:roles().muted)
  end
end)

T.test("icons: a sentinel that will not change is tried once, not on every keystroke", function()
  local app, host = start({ icons = true }, icons())
  host.recolor = function() end -- nothing sticks
  app:load()
  local reads = host.reads
  for _ = 1, 10 do
    host.handlers.settled()
  end
  T.eq(host.reads, reads)
end)

T.test("icons: on with no option set, because installing this asks for the theme everywhere", function()
  local app, host = start({}, icons())
  app:load()
  T.ok(host.live.DevIconLua.fg ~= "#51a0cf")
  T.eq(host.live.DevIconDefault.fg, app:roles().muted)
end)

T.test("icons: off leaves the plugin's colors alone, and so does another colorscheme", function()
  local app, host = start({ icons = false }, icons())
  app:load()
  host.handlers.settled()
  T.eq(host.live.DevIconLua.fg, "#51a0cf")
  T.eq(host.reads, 0)

  app, host = start({ icons = true }, {})
  app:load()
  local settled = host.handlers.settled
  host.handlers.colorscheme_changed("habamax")
  host.live = icons()
  settled() -- a late event from before the switch
  T.eq(host.live.DevIconLua.fg, "#51a0cf")
end)

T.test("check: looks at the screen while colorrex is showing, and only then", function()
  local app, host = start({ icons = false }, { DevIconLua = { fg = "#51a0cf" }, Linked = { link = "Comment" } })
  app:load()
  app:check()
  local text = host.messages[#host.messages].message
  T.ok(text:find("1 highlight from elsewhere wears colors that are not this theme's", 1, true), text)
  T.ok(text:find("DevIconLua  fg #51a0cf", 1, true), text)

  host.handlers.colorscheme_changed("habamax")
  local reads = host.reads
  app:check()
  T.eq(host.reads, reads, "another colorscheme's highlights are not ours to judge")
  T.ok(not host.messages[#host.messages].message:find("from elsewhere", 1, true))
end)

T.test("check: with icons adopted, a setup with nothing else astray is clean", function()
  local app, host = start({ icons = true }, icons())
  app:load()
  app:check()
  T.ok(host.messages[#host.messages].message:find("every highlight on screen wears this theme's colors", 1, true),
    host.messages[#host.messages].message)
end)
