local F = require("fixtures")
local T = require("harness")
local App = require("colorrex.app")
local Config = require("colorrex.config")
local Theme = require("colorrex.theme")

local function start(host_overrides)
  local host = F.fake_host(host_overrides)
  local app = App.new(host, Config.resolve())
  -- Stand-in for Neovim: :colorscheme colorrex runs colors/colorrex.lua.
  host.on_apply = function() app:load() end
  return app, host
end

local function answer(app, theme)
  app.terminal.feed(F.reply(theme))
end

local DRACULA = F.theme({ fg = "#f8f8f2", bg = "#282a36", cursor = "#ff79c6" })
local LIGHT = F.theme({ fg = "#383a42", bg = "#fafafa" })

T.test("app: launch paints immediately, then the live theme", function()
  local app, host = start()
  app:load()
  T.eq(host.renders, 1, "first frame must not wait on the terminal")
  T.eq(#host.sent, 1, "and a query went out")
  answer(app, DRACULA)
  T.eq(host.shown.filled.bg, "#282a36")
  T.eq(app:status().source, "terminal")
end)

T.test("app: the first frame of a later launch is the last real theme", function()
  local app, host = start()
  app:load()
  answer(app, DRACULA)
  local second, next_host = start({ saved = host.saved })
  next_host.ready = false
  second:load()
  T.eq(next_host.shown.filled.bg, "#282a36")
  T.eq(second:status().source, "cache")
end)

T.test("app: an unchanged theme repaints nothing", function()
  local app, host = start()
  app:load()
  answer(app, DRACULA)
  local renders = host.renders
  app:sync("focus")
  answer(app, DRACULA)
  T.eq(host.renders, renders)
end)

T.test("app: a dark-to-dark change arrives through a manual sync and says so", function()
  local app, host = start()
  app:load()
  answer(app, F.theme())
  app:sync("manual")
  answer(app, DRACULA)
  T.eq(host.shown.filled.bg, "#282a36")
  T.eq(host.messages[#host.messages].message, "synced to the terminal's theme")
end)

T.test("app: manual sync reports an unchanged theme", function()
  local app, host = start()
  app:load()
  answer(app, DRACULA)
  app:sync("manual")
  answer(app, DRACULA)
  T.eq(host.messages[#host.messages].message, "already in sync")
end)

T.test("app: focus syncs quietly and auto=false turns that off", function()
  local app, host = start()
  app:load()
  answer(app, F.theme())
  host.handlers.focus()
  T.eq(#host.sent, 2)
  answer(app, F.theme())
  T.eq(#host.messages, 0)

  local quiet, quiet_host = start()
  quiet.config = Config.resolve({ auto = false })
  quiet:load()
  answer(quiet, F.theme())
  quiet_host.handlers.focus()
  T.eq(#quiet_host.sent, 1)
end)

T.test("app: a partial reply never replaces a complete theme", function()
  local app, host = start()
  app:load()
  answer(app, DRACULA)
  app:sync("manual")
  answer(app, F.theme({ fg = false, bg = false, cursor = false }))
    T.eq(host.shown.filled.bg, "#282a36")
  T.ok(host.messages[#host.messages].message:match("only part"))
end)

T.test("app: with nothing better, a partial reply is shown, then retried until the theme lands", function()
  local app, host = start()
  app:load()
  local partial = F.theme({ fg = false, bg = false, cursor = false })
  answer(app, partial)
    T.eq(app.colorscheme.completeness, "partial")
  T.eq(#host.sent, 1)
  host.advance(250)
  T.eq(#host.sent, 2, "the first retry")
  answer(app, DRACULA)
  T.eq(app.colorscheme.completeness, "full")
  host.advance(10000)
  T.eq(#host.sent, 2, "a full theme ends the retries")
end)

T.test("app: retries are bounded on a block that never gets a theme", function()
  local app, host = start()
  app:load()
  local partial = F.theme({ fg = false, bg = false, cursor = false })
  for _ = 1, 8 do
    answer(app, partial)
        host.advance(5000)
  end
  T.eq(#host.sent, 4, "launch plus three retries")
end)

T.test("broadcast: another Neovim's write makes this one ask its own terminal", function()
  local app, host = start()
  app:load()
  answer(app, F.theme())
  local sent = #host.sent
  host.saved = Theme.serialize(DRACULA) -- what another Neovim just saved
  host.handlers.theme_saved()
  host.advance(30)
  T.eq(#host.sent, sent + 1)
  T.eq(host.shown.filled.bg, "#1b1f27", "the file is a nudge, its colors are never used")
  answer(app, DRACULA)
  T.eq(host.shown.filled.bg, "#282a36")
end)

T.test("broadcast: its own write costs no query", function()
  local app, host = start()
  app:load()
  answer(app, F.theme())
  local sent = #host.sent
  host.handlers.theme_saved()
  host.advance(30)
  T.eq(#host.sent, sent)
end)

T.test("broadcast: a burst of filesystem events is one query", function()
  local app, host = start()
  app:load()
  answer(app, F.theme())
  local sent = #host.sent
  host.saved = Theme.serialize(DRACULA)
  for _ = 1, 5 do
    host.handlers.theme_saved()
  end
  host.advance(30)
  answer(app, DRACULA) -- without the wait, the extra events would queue a second query
  T.eq(#host.sent, sent + 1)
end)

T.test("app: changing options recompiles the current theme", function()
  local app = start()
  app:load()
  answer(app, DRACULA)
  T.eq(app.colorscheme.groups.Normal.bg, nil)
  app:configure(Config.resolve({ transparent = false }))
  T.eq(app.colorscheme.groups.Normal.bg, "#282a36")
end)

T.test("app: launch resets the retries for a fresh start", function()
  local app, host = start()
  app:load()
  local partial = F.theme({ fg = false, bg = false, cursor = false })
  for _ = 1, 4 do
    answer(app, partial)
    host.advance(5000)
  end
  T.eq(app.retries, 3)
  app:sync("launch")
  T.eq(app.retries, 0)
end)

T.test("app: a sync while detached with no terminal says so", function()
  local app, host = start({ ready = false })
  app:load()
  host.handlers.colorscheme_changed("habamax")
  app:sync("manual")
  T.ok(host.messages[1].message:match("no terminal"), "must report, not stay silent")
  T.eq(app.announce, false)
end)

T.test("status: says when a query is still in flight", function()
  local app = start()
  app:load()
  local Report = require("colorrex.report")
  T.ok(Report.status(app:status()):match("launch: waiting"))
end)

T.test("broadcast: a follower never rewrites the file, so the chain ends", function()
  local app, host = start()
  app:load()
  answer(app, F.theme())
  local writes = 0
  local write = host.save_theme
  host.save_theme = function(text)
    writes = writes + 1
    write(text)
  end
  host.saved = Theme.serialize(DRACULA)
  host.handlers.theme_saved()
  host.advance(30)
  answer(app, DRACULA)
  T.eq(writes, 0, "the file already says this")
end)

T.test("broadcast: a block showing its own theme ignores it and writes nothing", function()
  local app, host = start()
  app:load()
  answer(app, F.theme())
  local mine = host.saved
  host.saved = Theme.serialize(DRACULA)
  host.handlers.theme_saved()
  host.advance(30)
  local other = host.saved
  answer(app, F.theme()) -- this block still shows its own theme
  T.eq(host.shown.filled.bg, "#1b1f27")
  T.eq(host.saved, other, "and it does not overwrite the other block's theme")
  T.ok(mine ~= other)
end)

T.test("broadcast: auto off ignores it", function()
  local app, host = start()
  app.config = Config.resolve({ auto = false })
  app:load()
  answer(app, F.theme())
  local sent = #host.sent
  host.saved = Theme.serialize(DRACULA)
  host.handlers.theme_saved()
  host.advance(30)
  T.eq(#host.sent, sent)
end)

T.test("broadcast: leaving cancels a pending check", function()
  local app, host = start()
  app:load()
  answer(app, F.theme())
  local sent = #host.sent
  host.saved = Theme.serialize(DRACULA)
  host.handlers.theme_saved()
  host.handlers.leaving()
  host.advance(30)
  T.eq(#host.sent, sent)
end)

T.test("notice: a terminal that never answers is told so, once, in one short line", function()
  local app, host = start()
  app:load()
  host.advance(500) -- the query times out
  T.eq(#host.messages, 0, "not yet: a slow link can still answer")
  host.advance(2000)
  T.eq(#host.messages, 1)
  T.eq(host.messages[1].level, "warn")
  T.ok(host.messages[1].message:match("Ghostty or Rex"))
  T.ok(#("colorrex: " .. host.messages[1].message) <= 60, "past v:echospace, Neovim stops at a hit-enter prompt")
  host.handlers.colorscheme_changed("habamax")
  app:load() -- back to colorrex: a second launch in the same session
  host.advance(500)
  host.advance(5000)
  T.eq(#host.messages, 1, "once is enough")
end)

T.test("notice: a focus event at startup does not swallow it", function()
  -- Terminals send a focus event the moment reporting is enabled, so in a terminal
  -- that needs this notice, the launch query is usually not the one that settles.
  local app, host = start()
  app:load()
  host.handlers.focus()
  host.advance(500) -- the launch query, replaced by the rerun
  host.advance(500) -- the rerun, whose reason is now focus
  host.advance(2000)
  T.eq(#host.messages, 1)
end)

T.test("notice: a slow answer cancels it", function()
  local app, host = start()
  app:load()
  host.advance(500)
  host.advance(1000)
  answer(app, DRACULA)
  host.advance(5000)
  T.eq(#host.messages, 0)
  T.eq(host.shown.filled.bg, "#282a36")
end)

T.test("notice: a block that is only waiting for its theme says nothing", function()
  local app, host = start()
  app:load()
  answer(app, F.theme({ fg = false, bg = false, cursor = false }))
  host.advance(10000)
  T.eq(#host.messages, 0)
end)

T.test("notice: a terminal that answered once is never called silent", function()
  local app, host = start()
  app:load()
  answer(app, DRACULA)
  app:sync("launch")
  host.advance(500)
  host.advance(5000)
  T.eq(#host.messages, 0)
end)

T.test("notice: a UI with no terminal, such as a GUI, is told straight away", function()
  local app, host = start({ ready = false })
  app:load()
  host.handlers.ui_enter()
  T.eq(#host.messages, 1)
  T.ok(host.messages[1].message:match("Ghostty or Rex"))
end)

T.test("notice: closing Neovim during the wait cancels it", function()
  local app, host = start()
  app:load()
  host.advance(500)
  host.handlers.leaving()
  host.advance(5000)
  T.eq(#host.messages, 0)
end)

T.test("app: a silent terminal is not retried and nothing changes", function()
  local app, host = start()
  app:load()
  local shown = host.shown
  host.advance(500)
  host.advance(10000)
  T.eq(#host.sent, 1)
  T.eq(host.shown, shown)
end)

T.test("app: repaints when 'background' disagrees and the terminal has nothing to offer", function()
  local app, host = start()
  app:load()
  answer(app, F.theme())
  local applies = host.applies
  host.bg = "light"
  app:sync("manual")
  host.advance(500) -- no answer
  T.eq(host.applies, applies + 1)
  T.eq(host.bg, "dark")
end)

T.test("app: with no terminal, 'background' flipping restores the colors once we are out of the handler", function()
  local app, host = start({ ready = false })
  app:load()
  local renders = host.renders
  host.bg = "light"
  app:load()
  T.eq(host.renders, renders + 1)
  T.eq(host.bg, "dark")
  T.eq(host.applies, 1, "through :colorscheme, not from inside the option handler")
end)

T.test("app: Neovim flipping 'background' does not paint the stale theme back", function()
  local app, host = start()
  app:load()
  answer(app, F.theme())
  local renders = host.renders
  host.bg = "light" -- Neovim set this from the OSC 11 reply, then re-sourced us
  app:load()
  T.eq(host.renders, renders, "the old colors must not be repainted")
  T.eq(host.bg, "light")
  answer(app, LIGHT)
  T.eq(host.shown.background, "light")
end)

T.test("app: with auto off, Neovim flipping 'background' cannot change the colors", function()
  local app, host = start()
  app.config = Config.resolve({ auto = false })
  app:load()
  answer(app, F.theme())
  local sent = #host.sent
  host.bg = "light"
  app:load()
  T.eq(#host.sent, sent, "only :ColorRex may ask the terminal")
  T.eq(host.bg, "dark", "the theme keeps its own background")
end)

T.test("app: with auto off, resuming from suspend asks the terminal nothing", function()
  local app, host = start()
  app.config = Config.resolve({ auto = false })
  app:load()
  answer(app, F.theme())
  local sent = #host.sent
  host.handlers.resume()
  T.eq(#host.sent, sent)
end)

T.test("app: a sync abandoned by detaching stays silent at the next launch", function()
  local app, host = start()
  app:load()
  answer(app, F.theme())
  app:sync("manual")
  host.handlers.colorscheme_changed("habamax")
  app:load()
  answer(app, F.theme())
  T.eq(#host.messages, 0)
end)

T.test("app: a reply slower than the timeout still applies", function()
  local app, host = start()
  app:load()
  host.advance(1000)
  answer(app, DRACULA)
  T.eq(host.shown.filled.bg, "#282a36")
end)

T.test("app: a new palette on the same background still gets through", function()
  local app, host = start()
  app:load()
  answer(app, F.theme())
  app.terminal.feed("\027]11;rgb:1b/1f/27")
  answer(app, F.theme({ fg = "#ffffff" }))
  T.eq(host.shown.filled.fg, "#ffffff")
end)

T.test("app: a change the terminal reports triggers a sync", function()
  local app, host = start()
  app:load()
  answer(app, F.theme())
  local sent = #host.sent
  app.terminal.feed("\027]11;rgb:fafa/fafa/fafa")
  T.eq(#host.sent, sent + 1)
end)

T.test("app: another colorscheme detaches, and a sync brings rex back", function()
  local app, host = start()
  app:load()
  answer(app, F.theme())
  host.handlers.colorscheme_changed("habamax")
  T.eq(app.terminal, nil)
  T.eq(host.handlers, nil)
  app:sync("manual")
  T.ok(app.terminal)
  answer(app, DRACULA)
  answer(app, DRACULA)
  T.eq(host.shown.filled.bg, "#282a36")
end)

T.test("app: manual sync with no terminal says so rather than hanging", function()
  local app, host = start({ ready = false })
  app:load()
  app:sync("manual")
  T.ok(host.messages[1].message:match("no terminal"))
  T.eq(#host.sent, 0)
end)

--- Run the clock in small steps for `ms`, answering every query with `theme`.
--- Returns how many queries went out.
local function answering(app, host, theme, ms)
  local before = #host.sent
  for _ = 1, ms / 10 do
    local sent = #host.sent
    host.advance(10)
    if #host.sent > sent then
      answer(app, theme)
    end
  end
  return #host.sent - before
end

T.test("watch: an unfocused Neovim follows a theme nobody reports, such as a preview", function()
  local app, host = start()
  app:load()
  answer(app, F.theme())
  host.handlers.blur()
  T.eq(answering(app, host, F.theme(), 30), 1, "asked within 30 ms")
  answering(app, host, DRACULA, 30)
  T.eq(host.shown.filled.bg, "#282a36")
  answering(app, host, LIGHT, 30)
  T.eq(host.shown.filled.bg, "#fafafa")
end)

T.test("watch: each ask waits for the last reply, so a silent link does not pile them up", function()
  local app, host = start()
  app:load()
  answer(app, F.theme())
  host.handlers.blur()
  local sent = #host.sent
  host.advance(30)
  for _ = 1, 100 do
    host.advance(10) -- a second, and the terminal never answers
  end
  -- One ask, its 500 ms timeout, the next 30 ms later, and its timeout still running.
  T.eq(#host.sent - sent, 2)
end)

T.test("watch: eases off while nothing changes, then stops", function()
  local app, host = start()
  app:load()
  answer(app, F.theme())
  host.handlers.blur()
  T.ok(answering(app, host, F.theme(), 1000) >= 25, "fast at first")
  answering(app, host, F.theme(), 4500)
  T.ok(answering(app, host, F.theme(), 1000) <= 4, "slower once nothing has changed for a while")
  answering(app, host, F.theme(), 60000)
  T.eq(answering(app, host, F.theme(), 5000), 0, "stopped")
  T.eq(app.watching, false)
end)

T.test("watch: a change while easing off makes it fast again", function()
  local app, host = start()
  app:load()
  answer(app, F.theme())
  host.handlers.blur()
  answering(app, host, F.theme(), 6000)
  answering(app, host, DRACULA, 300)
  T.eq(host.shown.filled.bg, "#282a36")
  T.ok(answering(app, host, DRACULA, 1000) >= 25)
end)

T.test("watch: focus coming back stops it, and so does leaving", function()
  local app, host = start()
  app:load()
  answer(app, F.theme())
  host.handlers.blur()
  answering(app, host, F.theme(), 100)
  local sent = #host.sent
  host.handlers.focus()
  answer(app, F.theme())
  answering(app, host, F.theme(), 1000)
  T.eq(#host.sent - sent, 1, "only the focus sync itself")
  host.handlers.blur()
  host.handlers.leaving()
  T.eq(answering(app, host, F.theme(), 1000), 0)
end)

T.test("watch: auto off, or no terminal, never watches", function()
  local app, host = start()
  app.config = Config.resolve({ auto = false })
  app:load()
  answer(app, F.theme())
  host.handlers.blur()
  T.eq(answering(app, host, F.theme(), 1000), 0)

  local headless, headless_host = start({ ready = false })
  headless:load()
  headless_host.handlers.blur()
  T.eq(answering(headless, headless_host, F.theme(), 1000), 0)
end)

T.test("explain: traces a color to its role and its slot", function()
  local app, host = start()
  app:load()
  answer(app, F.theme({ fg = "#383a42", bg = "#fafafa", ansi = LIGHT.ansi }))
  app:explain("Number")
  local text = host.messages[#host.messages].message
  T.ok(text:match("role number, from ansi %d+"), text)
end)

T.test("explain: under the cursor it skips what it does not define and reads @x.lang as @x", function()
  local app, host = start({ cursor_groups = { "@spell.lua", "@comment.lua" } })
  app:load()
  app:explain()
  local text = host.messages[#host.messages].message
  T.ok(text:match("links to Comment"), text)
end)

T.test("status: names the theme by its id and casting", function()
  local app, host = start()
  app:load()
  answer(app, DRACULA)
  app:report_status()
  local status = app:status()
  T.eq(#status.id, 6)
  T.ok(host.messages[#host.messages].message:find(status.id, 1, true), "status must show the id")
end)

T.test("compile: writes a standalone file and refuses to clobber without a bang", function()
  local app, host = start()
  app:load()
  answer(app, DRACULA)
  app:compile_to("mine")
  T.ok(host.files["/colors/mine.lua"]:match("nvim_set_hl"))
  host.files["/colors/mine.lua"] = "user content"
  app:compile_to("mine")
  T.eq(host.files["/colors/mine.lua"], "user content")
  app:compile_to("mine", true)
  T.ok(host.files["/colors/mine.lua"]:match("nvim_set_hl"))
end)

T.test("compile: the standalone colorscheme is valid Lua", function()
  local app, host = start()
  app:load()
  app:compile_to("mine")
  T.ok(loadstring(host.files["/colors/mine.lua"]))
end)

T.test("chunks: off unless asked for, and gone when the colorscheme goes", function()
  local Config = require("colorrex.config")
  local plain = F.fake_host()
  local app = App.new(plain, Config.resolve())
  app:load()
  T.eq(plain.decorating.landmarks, nil)
  T.ok(plain.decorating.refine, "meanings are drawn with no option at all")

  local host = F.fake_host()
  app = App.new(host, Config.resolve({ chunks = true }))
  app:load()
  T.ok(host.decorating.landmarks, "asked for, so it draws")
  host.handlers.colorscheme_changed("habamax")
  T.eq(host.decorating, nil, "another colorscheme sees nothing of ours")
end)

T.test("chunks: setup can turn them on and off while running", function()
  local Config = require("colorrex.config")
  local host = F.fake_host()
  local app = App.new(host, Config.resolve())
  app:load()
  app:configure(Config.resolve({ chunks = true }))
  T.ok(host.decorating.landmarks)
  app:configure(Config.resolve())
  T.eq(host.decorating.landmarks, nil)
end)

-- Layers between Neovim and the terminal ---------------------------------------------

local function answer_xterm(app, theme)
  for _, sequence in ipairs(F.xterm_replies(theme)) do
    app.terminal.feed(sequence)
  end
end

T.test("app: a pause in typing asks once, then not again for a while", function()
  local app, host = start()
  app:load()
  answer(app, F.theme())
  local sent = #host.sent
  host.handlers.pause()
  T.eq(#host.sent, sent + 1)
  answer(app, DRACULA)
  T.eq(host.shown.filled.bg, "#282a36", "a change tmux or herdr dropped still shows")
  host.handlers.pause()
  T.eq(#host.sent, sent + 1, "a second pause soon after asks nothing")
  host.advance(2000)
  host.handlers.pause()
  T.eq(#host.sent, sent + 2)
end)

T.test("app: auto = false turns the pause check off", function()
  local app, host = start()
  app.config = Config.resolve({ auto = false })
  app:load()
  answer(app, F.theme())
  local sent = #host.sent
  host.handlers.pause()
  T.eq(#host.sent, sent)
end)

T.test("app: through tmux, the cursor tmux hides comes from the last full read", function()
  -- A direct Neovim on this machine saw Dracula with its pink cursor.
  local direct, direct_host = start()
  direct:load()
  answer(direct, DRACULA)
  local app, host = start({ saved = direct_host.saved, in_tmux = true })
  app:load()
  answer_xterm(app, DRACULA)
  T.eq(host.shown.filled.cursor, "#ff79c6")
  T.ok(app:status().borrowed)
  T.eq(app:status().route, "xterm")
  T.eq(host.shown.voice, direct_host.shown.voice, "the theme reads the same through tmux")
end)

T.test("app: through tmux, a palette never seen whole keeps no cursor", function()
  local app, host = start({ in_tmux = true })
  app:load()
  answer_xterm(app, DRACULA)
  T.eq(host.shown.filled.cursor, nil)
  T.eq(app:status().borrowed, false)
end)

T.test("app: inside tmux, silence is blamed on tmux, with where to look", function()
  local app, host = start({ in_tmux = true })
  app:load()
  host.advance(500)
  host.advance(2000)
  T.ok(host.messages[1].message:find("tmux", 1, true), host.messages[1].message)
  T.ok(#host.messages[1].message <= 68, "fits v:echospace, so launch never waits on Enter")
end)

T.test("app: a terminal that reports fg and bg but no palette still gets the notice", function()
  -- Neovim's own :terminal answers OSC 10 and 11 and nothing else.
  local app, host = start()
  app:load()
  app.terminal.feed("\027]10;rgb:ffff/ffff/ffff")
  app.terminal.feed("\027]11;rgb:0000/0000/0000")
  host.advance(500)
  host.advance(2000)
  T.ok(host.messages[1] and host.messages[1].message:find("no colors reported", 1, true))
end)

T.test("app: through tmux that knows no fg or bg yet, the palette alone finds the theme", function()
  local direct, direct_host = start()
  direct:load()
  answer(direct, DRACULA)
  local app, host = start({ saved = direct_host.saved, in_tmux = true })
  app:load()
  local replies = F.xterm_replies(DRACULA)
  for index = 3, #replies do -- the palette only
    app.terminal.feed(replies[index])
  end
  host.advance(500)
  T.eq(host.shown.filled.bg, "#282a36")
  T.eq(host.shown.filled.cursor, "#ff79c6")
end)

T.test("app: a reported color that disagrees with the last read is never overruled", function()
  local direct, direct_host = start()
  direct:load()
  answer(direct, DRACULA)
  local app, host = start({ saved = direct_host.saved, in_tmux = true })
  app:load()
  answer_xterm(app, F.theme({ fg = "#f8f8f2", bg = "#101010", cursor = false, ansi = DRACULA.ansi }))
  T.eq(host.shown.filled.bg, "#101010")
  T.eq(host.shown.filled.cursor, nil, "another theme with the same palette borrows nothing")
end)

T.test("app: through tmux, a fresh palette is shown even when tmux knows no fg or bg", function()
  local app, host = start({ in_tmux = true })
  app:load()
  answer_xterm(app, DRACULA)
  local gruvbox = F.theme({ ansi = { [0] = "#282828", "#cc241d", "#98971a", "#d79921", "#458588", "#b16286",
    "#689d6a", "#a89984", "#928374", "#fb4934", "#b8bb26", "#fabd2f", "#83a598", "#d3869b", "#8ec07c", "#ebdbb2" } })
  app:sync("pause")
  local replies = F.xterm_replies(gruvbox)
  for index = 3, #replies do
    app.terminal.feed(replies[index])
  end
  host.advance(500)
  T.eq(host.shown.filled.ansi[1], "#cc241d", "the palette tmux did report")
  T.eq(host.shown.filled.bg, "#282a36", "the last background known, not an invented one")
  T.ok(app:status().borrowed:find("tmux", 1, true))
end)

T.test("app: a theme filled from the last known colors is shown but never saved", function()
  -- The saved file is what this machine saw whole. A mix written there would stand
  -- in for the real theme at the next launch, and in every other Neovim.
  local direct, direct_host = start()
  direct:load()
  answer(direct, DRACULA)
  local saved = direct_host.saved
  local app, host = start({ saved = saved, in_tmux = true })
  app:load()
  local other = F.theme({ ansi = { [0] = "#1d1f21", "#cc6666", "#b5bd68", "#f0c674", "#81a2be", "#b294bb",
    "#8abeb7", "#c5c8c6", "#666666", "#d54e53", "#b9ca4a", "#e7c547", "#7aa6da", "#c397d8", "#70c0b1", "#eaeaea" } })
  local replies = F.xterm_replies(other)
  for index = 3, #replies do
    app.terminal.feed(replies[index])
  end
  host.advance(500)
  T.eq(host.shown.filled.ansi[1], "#cc6666")
  T.eq(host.saved, saved)
end)
