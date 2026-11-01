-- The lifecycle: seed, render, sync, repaint.
--
-- App holds every decision about WHEN colors change and owns no effects:
-- everything it does to the world goes through an injected host, and neovim.lua
-- is the one real host. So all of this runs, and is tested, under plain LuaJIT
-- with a fake one. Ghostty keeps its core and its apprt apart the same way.
local Compiler = require("color-rex.compiler")
local Config = require("color-rex.config")
local Terminal = require("color-rex.terminal")
local Theme = require("color-rex.theme")

local App = {}
App.__index = App

-- A new Rex block answers before its theme lands, usually under 150ms later.
local RETRY_MS = { 250, 1000, 3000 }

-- How long after a silent launch to say so. A query times out long before this,
-- and a slow link can still answer, so this is what keeps SSH from a false alarm.
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
    source = "none", -- default | cache | terminal
    attached = false,
    terminal = nil,
    retries = 0,
    cancel_retry = nil,
    cancel_notice = nil,
    broadcast_pending = false,
    heard = false, -- the terminal has answered at least once
    noticed = false, -- the user has been told it has not
    announce = false,
    applying = false,
    last = { reason = nil, completeness = nil, outcome = nil },
  }, App)
end

--- The first colorscheme: the theme this terminal last showed, else neutral grey.
--- One read and one compile, so even the first frame is the real theme.
function App:seed()
  if self.colorscheme then
    return
  end
  local text = self.host.cache_read()
  local theme = text and Theme.parse(text) or nil
  if theme and Theme.completeness(theme) == "full" then
    self.source = "cache"
  else
    theme, self.source = {}, "default"
  end
  self.colorscheme = Compiler.compile(theme, self.config, self.host.background())
end

--- Called by colors/color-rex.lua, which Neovim also re-sources on its own whenever
--- 'background' changes.
function App:load()
  self:seed()
  local flipped = self.attached and not self.applying and self.host.ui_ready()
    and self.host.background() ~= self.colorscheme.background
  if flipped then
    -- Neovim flipped 'background' from a terminal reply and reloaded us with
    -- colors that are now the wrong way round, so fetch the real theme. With
    -- auto off only :ColorRex may change colors, so restore these instead. That
    -- has to wait: we are inside Neovim's option handler, and setting the option
    -- back from here makes Neovim abandon the colorscheme.
    if self.config.auto then
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
  if self.attached then
    return
  end
  self.attached = true
  self.terminal = Terminal.new({
    send = self.host.send,
    after = self.host.after,
    on_settle = function(theme, outcome)
      self:settled(theme, outcome)
    end,
    on_change = function()
      if self.config.auto then
        self:sync("mode")
      end
    end,
  })
  self.host.subscribe({
    response = function(sequence)
      if self.terminal then
        self.terminal.feed(sequence)
      end
    end,
    focus = function()
      if self.config.auto then
        self:sync("focus")
      end
    end,
    ui_enter = function()
      self:sync("launch")
    end,
    resume = function()
      if self.config.auto then
        self:sync("resume")
      end
    end,
    cache_changed = function()
      if self.config.auto then
        self:heard_broadcast()
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
  if self.host.ui_ready() then
    self:sync("launch")
  end
end

function App:detach()
  if not self.attached then
    return
  end
  self.attached = false
  self.announce, self.pending_manual = false, false
  self:stop_retrying()
  self:stop_notice()
  self.terminal.close()
  self.terminal = nil
  self.host.unsubscribe()
end

function App:stop_notice()
  if self.cancel_notice then
    self.cancel_notice()
    self.cancel_notice = nil
  end
end

--- Say once that this terminal gave us nothing, so that grey never goes unexplained.
function App:notice_no_colors()
  if not self.noticed then
    self.noticed = true
    self.host.notify(NO_COLORS, "warn")
  end
end

function App:stop_retrying()
  if self.cancel_retry then
    self.cancel_retry()
    self.cancel_retry = nil
  end
end

--- Another Neovim saved a new theme. That file is only a nudge: this Neovim asks
--- its own terminal rather than copying the colors, because each Rex block can
--- show a different theme. A file that already says what this Neovim is showing is
--- its own write, or nothing new, so that costs no query at all.
function App:heard_broadcast()
  if self.broadcast_pending then
    return
  end
  self.broadcast_pending = true
  self.host.after(BROADCAST_MS, function()
    self.broadcast_pending = false
    if self.attached and self.host.cache_read() ~= Theme.serialize(self.colorscheme.theme) then
      self:sync("broadcast")
    end
  end)
end

--- Re-read the terminal. "manual" is the guaranteed path: it is what a keybind
--- and `:ColorRex` both run, and the only reason that reports back.
function App:sync(reason)
  if not self.attached then
    self.pending_manual = true
    self:repaint()
    return
  end
  if not self.host.ui_ready() then
    if reason == "manual" then
      self.host.notify("no terminal is attached, so there is nothing to sync from", "warn")
    elseif reason == "launch" then
      self:notice_no_colors() -- a UI with no terminal, such as a GUI
    end
    return
  end
  if reason == "manual" then
    self.announce = true
  end
  if reason == "launch" then
    self.retries = 0
  end
  self.last.reason = reason
  self.terminal.query()
end

--- A query finished, complete or not.
function App:settled(theme, outcome)
  local completeness = Theme.completeness(theme)
  local announce = self.announce
  self.announce = false
  self.last = { reason = self.last.reason, completeness = completeness, outcome = outcome }

  if completeness ~= "none" then
    self.heard = true
    self:stop_notice()
  elseif self.last.reason == "launch" and not self.heard and not self.cancel_notice then
    self.cancel_notice = self.host.after(NOTICE_MS, function()
      self.cancel_notice = nil
      self:notice_no_colors()
    end)
  end

  -- A reply never replaces a complete theme with an incomplete one. An unthemed
  -- Rex block answers with built-in ANSI colors and no fg or bg; the theme we
  -- already hold is the better guess until the real one lands.
  local changed = false
  if completeness == "full" or (completeness == "partial" and self.colorscheme.completeness ~= "full") then
    changed = self:adopt(theme, completeness)
  elseif self.host.ui_ready() and self.host.background() ~= self.colorscheme.background then
    self:repaint()
  end

  if completeness == "partial" and self.retries < #RETRY_MS then
    self.retries = self.retries + 1
    self:stop_retrying()
    self.cancel_retry = self.host.after(RETRY_MS[self.retries], function()
      self.cancel_retry = nil
      if self.attached then
        self:sync("retry")
      end
    end)
  elseif completeness == "full" then
    self:stop_retrying()
  end

  if announce then
    if completeness == "none" then
      self.host.notify("the terminal did not answer, so the colors stay as they are", "warn")
    elseif completeness == "partial" then
      self.host.notify("the terminal sent only part of its theme", "warn")
    else
      self.host.notify(changed and "synced to the terminal's theme" or "already in sync")
    end
  end
end

--- Compile and show a theme. Returns true only if anything changed.
function App:adopt(theme, completeness)
  local colorscheme = Compiler.compile(theme, self.config, self.host.background())
  local same = colorscheme.key == self.colorscheme.key
  if completeness == "full" then
    self.source = "terminal"
    -- Only a change this Neovim saw for itself, and never the same text twice.
    -- That is what ends the chain when several Neovims follow one another.
    local text = Theme.serialize(theme)
    if not same or self.colorscheme.completeness ~= "full" then
      if self.host.cache_read() ~= text then
        self.host.cache_write(text)
      end
    end
  end
  if same then
    if self.host.background() ~= colorscheme.background then
      self:repaint()
    end
    return false
  end
  self.colorscheme = colorscheme
  if completeness ~= "full" then
    self.source = "terminal"
  end
  self:repaint()
  return true
end

--- Go through `:colorscheme`, so ColorScheme fires and lualine and every other
--- plugin that derives from highlights follows along.
function App:repaint()
  self.host.defer(function()
    self.applying = true
    local ok, err = pcall(self.host.apply)
    self.applying = false
    if not ok then
      self.host.notify("could not apply the theme: " .. tostring(err), "error")
    end
    if self.pending_manual then
      self.pending_manual = false
      if self.attached then
        self:sync("manual")
      end
    end
  end)
end

--- Compile the current theme again, for example after setup() changes options.
function App:configure(config)
  self.config = config
  if self.colorscheme then
    self.colorscheme = Compiler.compile(self.colorscheme.theme, config, self.host.background())
    if self.attached then
      self:repaint()
    end
  end
end

-- Reports -----------------------------------------------------------------------

function App:current()
  self:seed()
  return self.colorscheme
end

function App:status()
  local colorscheme = self:current()
  return {
    attached = self.attached,
    source = self.source,
    completeness = colorscheme.completeness,
    background = colorscheme.background,
    fg = colorscheme.filled.fg,
    bg = colorscheme.filled.bg,
    accent = colorscheme.roles.accent.hex,
    id = colorscheme.id,
    casting = colorscheme.casting,
    adjustments = #colorscheme.notes,
    last = self.last,
    auto = self.config.auto,
  }
end

function App:report_status()
  local s = self:status()
  local last = s.last.reason
      and ("%s: %s (%s)"):format(s.last.reason, s.last.completeness, s.last.outcome)
    or "not yet"
  self.host.notify(table.concat({
    ("theme     %s, from %s (%s)"):format(s.background, s.source, s.completeness),
    ("id        %s, casting %d"):format(s.id, s.casting),
    ("colors    fg %s  bg %s  accent %s"):format(s.fg, s.bg, s.accent),
    ("last sync %s"):format(last),
    ("auto      %s"):format(s.auto and "on (focus and dark/light changes)" or "off (:ColorRex only)"),
    ("adjusted  %d (see :ColorRex check)"):format(s.adjustments),
  }, "\n"))
end

--- The group this plugin defines for a name, if any. Neovim reads @comment.lua
--- as @comment when no such group exists, so this does the same.
local function defined(colorscheme, name)
  while name do
    if colorscheme.group_specs[name] then
      return name
    end
    name = name:match("^(.+)%.[^.]+$")
  end
  return nil
end

--- Why one group is the color it is.
function App:explain(group)
  local candidates = group and { group } or self.host.groups_under_cursor()
  if #candidates == 0 then
    self.host.notify("nothing under the cursor; try :ColorRex explain Comment", "warn")
    return
  end
  local colorscheme = self:current()
  local name
  for _, candidate in ipairs(candidates) do
    name = name or defined(colorscheme, candidate)
  end
  if not name then
    self.host.notify(("%s is not a group color-rex defines"):format(candidates[1]), "warn")
    return
  end
  local lines, seen = {}, {}
  while colorscheme.group_specs[name].link and not seen[name] do
    seen[name] = true
    lines[#lines + 1] = ("%s links to %s"):format(name, colorscheme.group_specs[name].link)
    name = colorscheme.group_specs[name].link
  end
  local spec = colorscheme.group_specs[name]
  lines[#lines + 1] = name
  local described = false
  for _, key in ipairs({ "fg", "bg", "sp" }) do
    if spec[key] then
      described = true
      local role = colorscheme.roles[spec[key]]
      local origin = role.from and (", moved from %s to stay readable"):format(role.from) or ""
      lines[#lines + 1] = ("  %s %s  role %s, from %s%s"):format(key, role.hex, spec[key], role.source, origin)
    end
  end
  if not described then
    lines[#lines + 1] = "  sets no color of its own"
  end
  self.host.notify(table.concat(lines, "\n"))
end

--- Judge the theme on screen against the promises.
function App:check()
  local colorscheme = self:current()
  local failures = Compiler.check(colorscheme, self.config)
  local lines = {}
  if #failures == 0 then
    lines[1] = "promises kept for this theme"
  end
  for _, failure in ipairs(failures) do
    lines[#lines + 1] = ("BROKEN %s: %s"):format(failure.code, failure.message)
  end
  if colorscheme.completeness ~= "full" then
    lines[#lines + 1] = "not the terminal's full theme yet; run :ColorRex"
  end
  for _, note in ipairs(colorscheme.notes) do
    lines[#lines + 1] = ("  %s: %s"):format(note.code, note.message)
  end
  self.host.notify(table.concat(lines, "\n"), #failures > 0 and "error" or nil)
  return failures
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
