-- The lifecycle: seed, render, sync, repaint.
--
-- App holds every decision about WHEN colors change and owns no effects: everything
-- it does to the world goes through an injected host, and neovim.lua is the one real
-- host. So all of this runs, and is tested, under plain LuaJIT with a fake one.
-- Ghostty keeps its core and its apprt apart the same way.
local Chunks = require("colorrex.chunks")
local Compiler = require("colorrex.compiler")
local Config = require("colorrex.config")
local Report = require("colorrex.report")
local Terminal = require("colorrex.terminal")
local Theme = require("colorrex.theme")

local App = {}
App.__index = App

-- A new Rex block answers before its theme lands, usually under 150ms later.
local RETRY_MS = { 250, 1000, 3000 }

-- How long after a silent query to say so. A query times out long before this, and
-- a slow link can still answer, so this is what keeps SSH from a false alarm.
local NOTICE_MS = 2000

-- Lets the burst of filesystem events from one write settle into a single check.
local BROADCAST_MS = 30

-- Short on purpose. A startup message longer than v:echospace, which is 68 in an
-- 80-column window, stops Neovim at a hit-enter prompt on every launch.
local NO_COLORS = "no colors reported; it needs Ghostty or Rex"

function App.new(host, config)
  return setmetatable({
    host = host,
    config = config,
    colorscheme = nil,
    source = nil, -- default | cache | terminal
    terminal = nil, -- present exactly while this colorscheme is attached: active, and listening
    retries = 0,
    cancel_retry = nil,
    cancel_notice = nil,
    cancel_saved_check = nil,
    answered = false, -- the terminal has reported at least one color
    noticed = false, -- the user has been told it has not
    announce = false, -- the next query's result is reported to the user
    applying = false, -- this Neovim is the one running :colorscheme
    last = {}, -- the last sync: reason, completeness, outcome
  }, App)
end

local function stop(self, cancel_field)
  if self[cancel_field] then
    self[cancel_field]()
    self[cancel_field] = nil
  end
end

--- The first colorscheme: the theme last saved on this machine, else neutral grey.
--- So the first frame is the real theme, before the terminal has been asked.
function App:seed()
  if self.colorscheme then
    return
  end
  local theme = Theme.parse(self.host.saved_theme() or "")
  local complete = Theme.completeness(theme) == "full"
  self.source = complete and "cache" or "default"
  self.colorscheme = Compiler.compile(complete and theme or { ansi = {} }, self.config, self.host.background())
end

--- Called by colors/colorrex.lua, which Neovim also re-sources on its own whenever
--- 'background' changes.
function App:load()
  self:seed()
  local flipped = self.terminal and not self.applying and self.host.background() ~= self.colorscheme.background
  if flipped then
    -- Something flipped 'background' and Neovim reloaded us with colors that are now
    -- the wrong way round. Usually that is a terminal reply, so fetch the real theme.
    -- With auto off only :ColorRex may change colors, and with no terminal nothing
    -- can answer, so restore these instead. That has to wait: we are inside Neovim's
    -- option handler, and setting the option back from here makes Neovim abandon the
    -- colorscheme.
    if self.config.auto and self.host.ui_ready() then
      self:sync("background")
    else
      self:repaint()
    end
    return
  end
  self.host.render(self.colorscheme)
  self:attach()
end

function App:attach()
  if self.terminal then
    return
  end
  self.terminal = Terminal.new({
    send = self.host.send,
    after = self.host.after,
    on_settle = function(theme, outcome)
      self:settled(theme, outcome)
    end,
    on_change = function()
      self:auto_sync("mode")
    end,
  })
  self.host.subscribe({
    response = function(sequence)
      self.terminal.feed(sequence)
    end,
    focus = function()
      self:auto_sync("focus")
    end,
    resume = function()
      self:auto_sync("resume")
    end,
    ui_enter = function()
      self:sync("launch")
    end,
    theme_saved = function()
      if self.terminal and self.config.auto then
        self:check_saved_theme()
      end
    end,
    colorscheme_changed = function(name)
      if name ~= Config.NAME then
        self:detach()
      end
    end,
    leaving = function()
      self:detach()
    end,
  })
  self:shape()
  if self.host.ui_ready() then
    self:sync("launch")
  elseif self.announce then
    self:sync("manual") -- someone asked, and there is no terminal to answer them
  end
end

function App:detach()
  if not self.terminal then
    return
  end
  self.announce = false
  stop(self, "cancel_retry")
  stop(self, "cancel_notice")
  stop(self, "cancel_saved_check")
  self.terminal.close()
  self.terminal = nil
  self.host.unsubscribe()
  self.host.undecorate()
end

--- Draw chunk landmarks, or stop, to match the options.
function App:shape()
  if self.config.chunks then
    self.host.decorate(Chunks.landmarks)
  else
    self.host.undecorate()
  end
end

--- Say once that this terminal gave us nothing, so that grey never goes unexplained.
function App:notice_no_colors()
  if not self.noticed then
    self.noticed = true
    self.host.notify(NO_COLORS, "warn")
  end
end

--- Another Neovim saved a new theme. That file is only a nudge: this Neovim asks its
--- own terminal rather than copying the colors, because each Rex block can show a
--- different theme. A file that already says what this Neovim is showing is its own
--- write, or nothing new, so that costs no query at all.
function App:check_saved_theme()
  if self.cancel_saved_check then
    return
  end
  self.cancel_saved_check = self.host.after(BROADCAST_MS, function()
    self.cancel_saved_check = nil
    if self.host.saved_theme() ~= Theme.serialize(self.colorscheme.theme) then
      self:sync("broadcast")
    end
  end)
end

function App:auto_sync(reason)
  if self.config.auto then
    self:sync(reason)
  end
end

--- Re-read the terminal. "manual" is the guaranteed path: it is what a keybind and
--- `:ColorRex` both run, and the only reason that reports back.
function App:sync(reason)
  if reason == "manual" then
    self.announce = true
  end
  if not self.terminal then
    self:repaint() -- another colorscheme is active: loading ours attaches and syncs
    return
  end
  if not self.host.ui_ready() then
    if reason == "launch" then
      self:notice_no_colors() -- a UI with no terminal, such as a GUI
    elseif self.announce then
      self.announce = false
      self.host.notify("no terminal is attached, so there is nothing to sync from", "warn")
    end
    return
  end
  if reason == "launch" then
    self.retries = 0
  end
  self.last = { reason = reason }
  self.terminal.query()
end

--- A query finished, complete or not.
function App:settled(theme, outcome)
  local completeness = Theme.completeness(theme)
  self.last.completeness, self.last.outcome = completeness, outcome
  self:track_silence(completeness)
  local changed = self:accept(theme, completeness)
  self:schedule_retry(completeness)
  self:announce_result(completeness, changed)
end

--- A terminal that never answers gets one notice. This looks at answers rather than
--- at what started the query: terminals send a focus event the moment reporting is
--- enabled, so a launch query is often not the one that settles.
function App:track_silence(completeness)
  stop(self, "cancel_notice")
  if completeness ~= "none" then
    self.answered = true
  elseif not self.answered then
    self.cancel_notice = self.host.after(NOTICE_MS, function()
      self.cancel_notice = nil
      self:notice_no_colors()
    end)
  end
end

--- Show a theme if it deserves to be, and keep 'background' honest either way.
--- A reply never replaces a complete theme with an incomplete one: an unthemed Rex
--- block answers with built-in ANSI colors and no fg or bg, and the theme we already
--- hold is the better guess until the real one lands. Returns true if colors changed.
function App:accept(theme, completeness)
  local better = completeness == "full" or (completeness == "partial" and self.colorscheme.completeness ~= "full")
  local changed = better and self:adopt(theme) or false
  if not changed and self.host.background() ~= self.colorscheme.background then
    self:repaint()
  end
  return changed
end

--- Compile a theme and show it if it differs. Returns true if it did.
function App:adopt(theme)
  local colorscheme = Compiler.compile(theme, self.config, self.host.background())
  self.source = "terminal"
  if colorscheme.signature == self.colorscheme.signature then
    return false
  end
  self.colorscheme = colorscheme
  if colorscheme.completeness == "full" then
    self:save_theme(theme)
  end
  self:repaint()
  return true
end

--- Write a theme this Neovim saw for itself. Skipping identical text is what ends
--- the chain when several Neovims follow one another.
function App:save_theme(theme)
  local text = Theme.serialize(theme)
  if self.host.saved_theme() ~= text then
    self.host.save_theme(text)
  end
end

--- An incomplete answer means a Rex block whose theme has not landed yet.
function App:schedule_retry(completeness)
  if completeness == "full" then
    stop(self, "cancel_retry")
  elseif completeness == "partial" and self.retries < #RETRY_MS then
    self.retries = self.retries + 1
    stop(self, "cancel_retry")
    self.cancel_retry = self.host.after(RETRY_MS[self.retries], function()
      self.cancel_retry = nil
      self:sync("retry")
    end)
  end
end

function App:announce_result(completeness, changed)
  if not self.announce then
    return
  end
  self.announce = false
  if completeness == "none" then
    self.host.notify("the terminal did not answer, so the colors stay as they are", "warn")
  elseif completeness == "partial" then
    self.host.notify("the terminal sent only part of its theme", "warn")
  else
    self.host.notify(changed and "synced to the terminal's theme" or "already in sync")
  end
end

--- Go through `:colorscheme`, so ColorScheme fires and lualine and every other plugin
--- that derives from highlights follows along.
function App:repaint()
  self.host.defer(function()
    self.applying = true
    local ok, err = pcall(self.host.apply)
    self.applying = false
    if not ok then
      self.host.notify("could not apply the theme: " .. tostring(err), "error")
    end
  end)
end

--- Compile the current theme again, for example after setup() changes options.
function App:configure(config)
  self.config = config
  if self.colorscheme then
    self.colorscheme = Compiler.compile(self.colorscheme.theme, config, self.host.background())
  end
  if self.terminal then
    self:shape()
  end
end

-- Reports ---------------------------------------------------------------------------

function App:current()
  self:seed()
  return self.colorscheme
end

function App:status()
  local colorscheme = self:current()
  return {
    source = self.source,
    completeness = colorscheme.completeness,
    background = colorscheme.background,
    fg = colorscheme.filled.fg,
    bg = colorscheme.filled.bg,
    accent = colorscheme.roles.accent.hex,
    id = colorscheme.id,
    casting = colorscheme.casting,
    voice = colorscheme.voice,
    adjustments = #colorscheme.notes,
    last = self.last,
    auto = self.config.auto,
  }
end

function App:report_status()
  self.host.notify(Report.status(self:status()))
end

function App:explain(group)
  local candidates = group and { group } or self.host.groups_under_cursor()
  self.host.notify(Report.explain(self:current(), candidates))
end

function App:check()
  local colorscheme = self:current()
  self.host.notify(Report.check(colorscheme, Compiler.check(colorscheme, self.config)))
end

--- Write the current theme as a standalone colorscheme.
function App:compile_to(name, force)
  name = name or Config.NAME .. "-static"
  if not name:match("^[%w_%-]+$") or name == Config.NAME then
    self.host.notify(("%q is not a usable colorscheme name"):format(name), "error")
    return
  end
  local path = self.host.colors_path(name)
  if self.host.exists(path) and not force then
    self.host.notify(("%s already exists; use :ColorRex! compile %s to replace it"):format(path, name), "warn")
    return
  end
  local ok, err = self.host.write(path, Compiler.standalone(self:current(), name))
  if ok then
    self.host.notify(("wrote %s; load it with :colorscheme %s"):format(path, name))
  else
    self.host.notify(("could not write %s: %s"):format(path, tostring(err)), "error")
  end
end

return App
