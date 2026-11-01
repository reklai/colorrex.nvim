-- The wiring into real Neovim. Headless, so there is no TUI and no terminal
-- replies; test/e2e covers those. Where a test needs a terminal to exist, it builds
-- an App on the real host with ui_ready forced, because a fake host cannot show
-- what Neovim itself does to a colorscheme.
local T = require("harness")

local RT = vim.fs.normalize(T.root)
if not vim.startswith(RT, "/") then
  RT = vim.fn.fnamemodify(RT, ":p"):gsub("/$", "")
end
vim.opt.runtimepath:prepend(RT)
vim.env.XDG_STATE_HOME = vim.fn.tempname()
vim.cmd("runtime plugin/color-rex.lua")

local function hl(name, key)
  local value = vim.api.nvim_get_hl(0, { name = name, link = false })[key]
  return value and ("#%06x"):format(value) or nil
end

local function colorscheme()
  vim.cmd.colorscheme("color-rex")
end

T.test("neovim: :colorscheme color-rex loads, sets its name, and defines the groups", function()
  colorscheme()
  T.eq(vim.g.colors_name, "color-rex")
  T.ok(hl("Comment", "fg"))
  T.ok(hl("@function", "fg"))
  T.ok(vim.g.terminal_color_1)
  T.ok(vim.o.termguicolors)
end)

T.test("neovim: every group in a default Neovim is covered or follows one that is", function()
  -- Ask a clean Neovim which groups it colors, so a group added upstream fails
  -- here rather than showing up as a stray default color on someone's screen.
  local out = vim.fn.system({
    vim.v.progpath, "--headless", "--clean", "-c",
    [[lua io.stdout:write(vim.json.encode(vim.tbl_keys(vim.api.nvim_get_hl(0, {})))) vim.cmd("qall!")]],
  })
  local names = vim.json.decode(out)
  colorscheme()
  local missing = {}
  for _, name in ipairs(names) do
    local raw = vim.api.nvim_get_hl(0, { name = name, link = false })
    local linked = vim.api.nvim_get_hl(0, { name = name }).link
    -- Colored by us, or linked to something that is. Neovim's own NvimXxx groups
    -- are the cmdline expression parser; those all link to a syntax group.
    if not linked and not raw.fg and not raw.bg and not raw.sp
      and not (raw.bold or raw.italic or raw.underline or raw.reverse or raw.strikethrough or raw.undercurl)
      and name:match("^%u") and not name:match("^Nvim") then
      local default = vim.fn.system({
        vim.v.progpath, "--headless", "--clean", "-c",
        ([[lua local h=vim.api.nvim_get_hl(0,{name=%q,link=false}) io.stdout:write((h.fg or h.bg or h.ctermfg or h.ctermbg) and "1" or "0") vim.cmd("qall!")]]):format(name),
      })
      if default == "1" then
        missing[#missing + 1] = name
      end
    end
  end
  T.eq(#missing, 0, "not covered: " .. table.concat(missing, ", "))
end)

T.test("neovim: compiled groups are accepted by nvim_set_hl, with styles intact", function()
  colorscheme()
  T.ok(vim.api.nvim_get_hl(0, { name = "Keyword" }).italic)
  T.ok(vim.api.nvim_get_hl(0, { name = "DiagnosticUnderlineError" }).undercurl)
  T.eq(vim.api.nvim_get_hl(0, { name = "@comment" }).link, "Comment")
end)

T.test("neovim: the command and every <Plug> mapping exist", function()
  T.eq(vim.fn.exists(":ColorRex"), 2)
  for _, lhs in ipairs({ "<Plug>(color-rex)", "<Plug>(color-rex-status)", "<Plug>(color-rex-explain)",
    "<Plug>(color-rex-check)" }) do
    T.ok(next(vim.fn.maparg(lhs, "n", false, true)) ~= nil, lhs)
  end
end)

T.test("neovim: command completion lists the catalog", function()
  local names = vim.fn.getcompletion("ColorRex ", "cmdline")
  T.ok(not vim.tbl_contains(names, "sync"), "syncing has no subcommand")
  T.ok(vim.tbl_contains(names, "explain"))
end)

T.test("neovim: a compiled standalone colorscheme loads with the plugin out of the way", function()
  colorscheme()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir .. "/colors", "p")
  local before = hl("Comment", "fg")
  local Compiler = require("color-rex.compiler")
  local text = Compiler.standalone(Compiler.compile({}, require("color-rex.config").resolve()), "standalone")
  local file = assert(io.open(dir .. "/colors/standalone.lua", "w"))
  file:write(text)
  file:close()
  local out = vim.fn.system({
    vim.v.progpath, "--headless", "--clean", "--cmd", "set rtp^=" .. dir, "-c", "colorscheme standalone",
    "-c", [[lua io.stdout:write(vim.g.colors_name .. ":" .. vim.g.terminal_color_1) vim.cmd("qall!")]],
  })
  T.ok(out:match("standalone:#"), out)
  T.ok(before)
end)

T.test("neovim: lualine finds the theme by name, without lualine being a dependency", function()
  colorscheme()
  local theme = dofile(RT .. "/lua/lualine/themes/color-rex.lua")
  for _, mode in ipairs({ "normal", "insert", "visual", "replace", "command", "inactive" }) do
    for _, section in ipairs({ "a", "b", "c" }) do
      T.ok(theme[mode][section].bg:match("^#%x+$"), mode .. "." .. section)
    end
  end
end)

T.test("neovim: switching to another colorscheme releases every autocommand", function()
  colorscheme()
  T.ok(#vim.api.nvim_get_autocmds({ group = "color-rex" }) > 0)
  vim.cmd.colorscheme("habamax")
  T.ok(not pcall(vim.api.nvim_get_autocmds, { group = "color-rex" }))
  colorscheme()
  T.ok(#vim.api.nvim_get_autocmds({ group = "color-rex" }) > 0)
end)

--- An App on the real host that believes a terminal is attached, wired up so
--- that :colorscheme color-rex reaches it.
local function live_app(options)
  local App = require("color-rex.app")
  local host = require("color-rex.neovim").new()
  host.ui_ready = function() return true end
  host.send = function() end
  local app = App.new(host, require("color-rex.config").resolve(options))
  package.loaded["color-rex"] = { load = function() app:load() end }
  return app, function()
    app:detach()
    package.loaded["color-rex"] = nil
  end
end

T.test("neovim: a write by another process reaches the real watcher", function()
  local app, finish = live_app({ auto = true })
  local sent = 0
  app.host.send = function() sent = sent + 1 end
  colorscheme()
  vim.wait(100, function() return false end)
  local before = sent
  local path = vim.fs.joinpath(vim.fn.stdpath("state"), "color-rex", "theme")
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  -- Written the way the plugin writes it, by something that is not this Neovim.
  vim.system({ "sh", "-c", ('printf "background = #123456\\n" > "%s.tmp" && mv "%s.tmp" "%s"'):format(path, path, path) }):wait()
  local noticed = vim.wait(1500, function() return sent > before end, 10)
  finish()
  T.ok(noticed, "the watcher never fired")
end)

T.test("neovim: leaving closes the watcher", function()
  local function watchers()
    local count = 0
    vim.uv.walk(function(handle)
      if handle:get_type() == "fs_event" and not handle:is_closing() then
        count = count + 1
      end
    end)
    return count
  end
  local before = watchers()
  local _, finish = live_app({ auto = true })
  colorscheme()
  T.eq(watchers(), before + 1, "subscribing opens one watcher")
  finish()
  T.eq(watchers(), before, "and leaving closes it")
end)

T.test("neovim: with auto off, flipping 'background' keeps the colorscheme alive", function()
  local _, finish = live_app({ auto = false })
  colorscheme()
  local comment = hl("Comment", "fg")
  vim.o.background = "light"
  vim.wait(200, function() return vim.o.background == "dark" end, 5)
  local name, background, after = vim.g.colors_name, vim.o.background, hl("Comment", "fg")
  finish()
  T.eq(name, "color-rex")
  T.eq(background, "dark", "the theme keeps its own background")
  T.eq(after, comment)
end)

T.test("neovim: with auto on, flipping 'background' waits for the real theme", function()
  local _, finish = live_app({ auto = true })
  colorscheme()
  vim.o.background = "light"
  local name, background = vim.g.colors_name, vim.o.background
  finish()
  vim.o.background = "dark"
  T.eq(name, "color-rex")
  T.eq(background, "light")
end)

T.test("neovim: explain finds the real group under the cursor on a Tree-sitter token", function()
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "-- a comment" })
  vim.treesitter.start(buf, "lua")
  vim.treesitter.get_parser(buf):parse(true)
  vim.api.nvim_win_set_cursor(0, { 1, 4 })
  colorscheme()
  local notes = {}
  local notify = vim.notify
  vim.notify = function(message) notes[#notes + 1] = message end
  vim.cmd("ColorRex explain")
  vim.notify = notify
  T.ok(notes[1]:match("Comment"), notes[1])
end)

T.test("neovim: in a terminal that is not libghostty, a real TUI explains why it is grey", function()
  -- Neovim's own :terminal is a real terminal that does not answer OSC 21.
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local init = dir .. "/init.lua"
  local file = assert(io.open(init, "w"))
  file:write(("vim.opt.rtp:prepend(%q)\nvim.cmd('runtime plugin/color-rex.lua')\nvim.cmd.colorscheme('color-rex')\n"):format(RT))
  file:close()
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  local job = vim.fn.jobstart({ vim.v.progpath, "-n", "-u", init }, {
    term = true,
    env = { XDG_STATE_HOME = dir .. "/state", TERM_PROGRAM = "", NVIM = "" },
  })
  local function screen()
    return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  end
  local found = vim.wait(8000, function() return screen():match("no colors reported") ~= nil end, 50)
  local text = screen()
  vim.fn.jobstop(job)
  T.ok(found, "the notice never appeared:\n" .. text:sub(-300))
  T.ok(not text:match("Press ENTER"), "the notice must not stop at a hit-enter prompt")
end)

T.test("neovim: below the version floor, the colorscheme refuses cleanly", function()
  local has = vim.fn.has
  local notes = {}
  local notify = vim.notify
  vim.fn.has = function(feature)
    return feature == "nvim-0.12" and 0 or has(feature)
  end
  vim.notify = function(message) notes[#notes + 1] = message end
  package.loaded["color-rex"] = nil
  local ok, err = pcall(function()
    local plugin = require("color-rex")
    plugin.load()
    plugin.load()
  end)
  vim.fn.has = has
  vim.notify = notify
  package.loaded["color-rex"] = nil
  T.ok(ok, err)
  T.eq(#notes, 1, "said once")
  T.ok(notes[1]:match("0%.12"), notes[1])
end)

T.test("neovim: :ColorRex with no terminal explains itself", function()
  colorscheme()
  local notes = {}
  local notify = vim.notify
  vim.notify = function(message) notes[#notes + 1] = message end
  vim.cmd("ColorRex")
  vim.cmd("ColorRex nope")
  vim.notify = notify
  T.ok(notes[1]:match("no terminal"), notes[1])
  T.ok(notes[2]:match("unknown command"), notes[2])
end)

T.test("neovim: :checkhealth runs clean", function()
  colorscheme()
  require("color-rex.health").check()
end)

T.test("neovim: the colorscheme loads in well under a frame", function()
  local start = vim.uv.hrtime()
  for _ = 1, 20 do
    colorscheme()
  end
  local ms = (vim.uv.hrtime() - start) / 1e6 / 20
  print(("  colorscheme: %.2f ms"):format(ms))
  T.ok(ms < 16, ("%.1f ms"):format(ms))
end)
