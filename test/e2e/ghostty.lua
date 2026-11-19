-- Real Neovim, in real Ghostty windows, with real config reloads.
--
--   nvim -l test/e2e/ghostty.lua     (needs a desktop session; `make e2e-ghostty`)
--
-- Every window gets its own config and never reads yours. Windows open on your
-- desktop for a few seconds and close themselves. The binary running this script
-- is the one under test. Only processes this script started are ever signalled.
local root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(arg[0], ":p"))))
package.path = root .. "/test/e2e/?.lua;" .. package.path
local THEMES = require("themes")
local work = vim.fn.tempname()
vim.fn.mkdir(work, "p")

if vim.fn.executable("ghostty") == 0 or not (vim.env.WAYLAND_DISPLAY or vim.env.DISPLAY) then
  print("SKIP  this needs Ghostty and a desktop session")
  os.exit(0)
end

local passed, failed = 0, 0
local function check(name, ok, detail)
  if ok then
    passed = passed + 1
    print("ok    " .. name)
  else
    failed = failed + 1
    print("FAIL  " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local BASE = [[
gtk-single-instance = false
confirm-close-surface = false
quit-after-last-window-closed = true
quit-after-last-window-closed-delay =
wait-after-command = false
shell-integration = none
window-save-state = never
window-width = 80
window-height = 24
]]

local function config_text(theme, extra)
  local lines = { BASE, "foreground = " .. theme.fg, "background = " .. theme.bg, "cursor-color = " .. theme.cursor }
  for index, hex in ipairs(theme.ansi) do
    lines[#lines + 1] = ("palette = %d=%s"):format(index - 1, hex)
  end
  lines[#lines + 1] = extra or ""
  return table.concat(lines, "\n") .. "\n"
end

local function write(path, text)
  local file = assert(io.open(path, "w"))
  file:write(text)
  file:close()
end

local windows = {}
local count = 0

--- `env` adds to what the window's Neovim is started with, such as a setup to load.
local function open(theme, extra, manual, env)
  count = count + 1
  local dir = ("%s/%d"):format(work, count)
  vim.fn.mkdir(dir, "p")
  local window = { conf = dir .. "/ghostty.conf", socket = dir .. "/nvim.sock", extra = extra }
  write(window.conf, config_text(theme, extra))
  local started_with = {
    HOME = vim.env.HOME,
    PATH = vim.env.PATH,
    WAYLAND_DISPLAY = vim.env.WAYLAND_DISPLAY,
    DISPLAY = vim.env.DISPLAY,
    XDG_RUNTIME_DIR = vim.env.XDG_RUNTIME_DIR,
    DBUS_SESSION_BUS_ADDRESS = vim.env.DBUS_SESSION_BUS_ADDRESS,
    XDG_STATE_HOME = dir .. "/state",
    COLORREX_ROOT = root,
    COLORREX_E2E_MANUAL = manual and "1" or nil,
  }
  for key, value in pairs(env or {}) do
    started_with[key] = value
  end
  window.process = vim.system({
    "ghostty", "--config-default-files=false", "--config-file=" .. window.conf, "-e",
    vim.v.progpath, "-n", "--listen", window.socket, "-u", root .. "/test/e2e/init.lua", root .. "/test/e2e/sample.lua",
  }, { clear_env = true, env = started_with })
  windows[#windows + 1] = window
  assert(vim.wait(8000, function() return vim.uv.fs_stat(window.socket) ~= nil end, 20), "Neovim never started")
  window.channel = vim.fn.sockconnect("pipe", window.socket, { rpc = true })
  -- Neovim opens this socket before it runs init.lua, so wait for the plugin too.
  local ready = vim.wait(8000, function()
    local ok, loaded = pcall(vim.rpcrequest, window.channel, "nvim_exec_lua",
      [[return package.loaded["colorrex"] ~= nil]], {})
    return ok and loaded
  end, 20)
  assert(ready, "the plugin never loaded")
  return window
end

local STATUS = [[
  local status = require("colorrex").status()
  local function hl(name, key)
    local value = vim.api.nvim_get_hl(0, { name = name, link = false })[key]
    return value and ("#%06x"):format(value) or ""
  end
  return {
    fg = status.fg, bg = status.bg, source = status.source, completeness = status.completeness,
    background = vim.o.background, colors_name = vim.g.colors_name or "",
    string = hl("String", "fg"), keyword = hl("Keyword", "fg"), func = hl("Function", "fg"),
    type = hl("Type", "fg"), id = status.id, term1 = vim.g.terminal_color_1 or "", env = vim.env.TERM_PROGRAM or "",
  }
]]

local function state(window)
  return vim.rpcrequest(window.channel, "nvim_exec_lua", STATUS, {})
end

--- Wait for a condition on the status; a failed check reports the last status.
local function settles(window, test, ms)
  local last
  vim.wait(ms or 2500, function()
    last = state(window)
    return test(last)
  end, 30)
  return test(last), vim.inspect(last)
end

local function matches(theme)
  return function(status)
    return status.fg == theme.fg and status.bg == theme.bg and status.term1 == theme.ansi[2]
  end
end

local function reload(window, theme)
  write(window.conf, config_text(theme, window.extra))
  window.process:kill("sigusr2")
end

local function close(window)
  pcall(vim.rpcnotify, window.channel, "nvim_command", "qa!")
  local exited = vim.wait(3000, function() return window.process:is_closing() end, 20)
  if not exited then
    window.process:kill("sigterm")
  end
end

local function suite()
  local window = open(THEMES.dracula)
  check("launch: the live theme arrives", settles(window, function(s)
    return matches(THEMES.dracula)(s) and s.completeness == "full" and s.source == "terminal"
  end))
  local status = state(window)
  check("the terminal is what it says", status.env == "ghostty", status.env)
  check("colorscheme is colorrex", status.colors_name == "colorrex", status.colors_name)

  for _, step in ipairs({
    { "dark to dark", THEMES.gruvbox },
    { "dark to light", THEMES.onelight },
    { "light to dark", THEMES.dracula },
    { "same background, new palette", THEMES.same_background },
  }) do
    reload(window, step[2])
    check("reload, no key pressed: " .. step[1], settles(window, matches(step[2])))
  end

  for _, name in ipairs({ "dracula", "gruvbox", "onelight", "dracula", "gruvbox" }) do
    reload(window, THEMES[name])
    vim.wait(25, function() return false end)
  end
  check("a reload storm ends on the final theme", settles(window, matches(THEMES.gruvbox)))
  check("and Neovim is healthy after it", state(window).colors_name == "colorrex")
  close(window)

  -- A tint changes the theme, and nothing about how its code reads: the same colors
  -- are the same colorscheme.
  local tinted = open(THEMES.dracula)
  check("tint: launch", settles(tinted, matches(THEMES.dracula)))
  local before = state(tinted)
  reload(tinted, THEMES.dracula_tint)
  check("tint: only the background changed in the theme", settles(tinted, matches(THEMES.dracula_tint)))
  local after = state(tinted)
  check("tint: the theme has a different id", before.id ~= after.id, before.id)
  check("tint: the code reads the same",
    before.keyword == after.keyword and before.func == after.func and before.type == after.type
      and before.string == after.string, vim.inspect({ before, after }))
  close(tinted)

  local quiet = open(THEMES.dracula, "osc-color-report-format = none")
  check("osc-color-report-format = none: launch still works", settles(quiet, matches(THEMES.dracula)))
  close(quiet)

  -- With auto off only the keybind can change colors, so this is deterministic
  -- whatever focus events the desktop happens to deliver.
  local manual = open(THEMES.dracula, nil, true)
  check("auto = false: setup turns it on, and launch still syncs", settles(manual, matches(THEMES.dracula)))
  reload(manual, THEMES.gruvbox)
  vim.wait(700, function() return false end)
  check("auto = false: a reported reload changes nothing", matches(THEMES.dracula)(state(manual)))
  vim.rpcrequest(manual.channel, "nvim_input", "gS")
  check("auto = false: the keybind syncs", settles(manual, matches(THEMES.gruvbox)))
  close(manual)
end

-- A setup written in roles, with real plugins where a plugin manager has left some.
-- Ghostty reports every reload, so all of it has to follow with no key pressed.
local PLUGINS = vim.env.COLORREX_PLUGINS or vim.fs.joinpath(vim.fn.stdpath("data"), "lazy")

local WRITTEN_IN_ROLES = [=[
  local function hl(name, key)
    local value = vim.api.nvim_get_hl(0, { name = name, link = false })[key]
    return value and ("#%06x"):format(value) or ""
  end
  local roles = require("colorrex").roles()
  local said, notify = {}, vim.notify
  vim.notify = function(message) said[#said + 1] = message end
  pcall(vim.cmd, "ColorRex check")
  vim.notify = notify
  local own = {} -- the theme's colors: every role's, and the sixteen it came with
  for _, hex in pairs(roles) do
    own[hex] = true
  end
  for slot = 0, 15 do
    own[vim.g["terminal_color_" .. slot] or ""] = true
  end
  local icons, astray = 0, 0
  for name, spec in pairs(vim.api.nvim_get_hl(0, {})) do
    if name:find("DevIcon", 1, true) and spec.fg then
      icons = icons + 1
      astray = astray + (own[("#%06x"):format(spec.fg)] and 0 or 1)
    end
  end
  return {
    base = roles.base, accent = roles.accent, on_accent = roles.on_accent, term1 = vim.g.terminal_color_1 or "",
    role_fg = hl("E2ERole", "fg"), role_bg = hl("E2ERole", "bg"), group_fg = hl("E2EGroup", "fg"),
    group_bg = hl("E2EGroup", "bg"), normal_bg = hl("Normal", "bg"), events = vim.g.e2e_role_events or 0,
    icons = icons, astray = astray, lua_icon = hl("DevIconLua", "fg"), check = table.concat(said, "\n"),
    plugins = vim.g.e2e_plugins or {}, plugin_errors = vim.g.e2e_plugin_errors or {},
  }
]=]

local function roles_suite()
  local window = open(THEMES.dracula, nil, false, { COLORREX_E2E_ROLES = "1", COLORREX_E2E_PLUGINS = PLUGINS })
  local function written(channel)
    return vim.rpcrequest(channel or window.channel, "nvim_exec_lua", WRITTEN_IN_ROLES, {})
  end
  local function strays_in(text)
    return text:match("%d+ highlights? from elsewhere.*") or "clean"
  end
  --- Whether everything a setup wrote in roles shows `theme`, and no icon is left out.
  local function follows(theme)
    return function(now)
      return now.base == theme.bg and now.term1 == theme.ansi[2] and now.role_bg == theme.bg
        and now.role_fg == now.accent and now.group_bg == now.accent and now.group_fg == now.on_accent
        and now.astray == 0
    end
  end
  local function settled(test, ms)
    local last
    vim.wait(ms or 3000, function()
      last = written()
      return test(last)
    end, 40)
    last.check = strays_in(last.check)
    return test(last), vim.inspect(last)
  end

  check("roles: at launch, a group in `groups` and one set from roles() wear Ghostty's theme",
    settled(follows(THEMES.dracula)))
  local now = written()
  check("roles: the accent is the cursor color, and base the background though Normal has none",
    now.accent == THEMES.dracula.cursor and now.base == THEMES.dracula.bg and now.normal_bg == "", vim.inspect(now.accent))
  check("roles: the plugins loaded without an error", #now.plugin_errors == 0, vim.inspect(now.plugin_errors))

  for _, step in ipairs({
    { "dark to dark", THEMES.gruvbox },
    { "dark to light", THEMES.onelight },
    { "light to dark", THEMES.dracula },
    { "same background, new palette", THEMES.same_background },
  }) do
    reload(window, step[2])
    check("roles: reload, no key pressed: " .. step[1], settled(follows(step[2])))
  end

  local before = written().events
  for _, name in ipairs({ "dracula", "onelight", "gruvbox", "onelight", "dracula_tint", "onelight", "gruvbox", "dracula" }) do
    reload(window, THEMES[name])
    vim.wait(25, function() return false end)
  end
  check("roles: a storm of eight reloads, dark and light, ends with everything on the last theme",
    settled(follows(THEMES.dracula)))
  check("roles: and the ColorScheme a setup listens for ran through it", written().events > before)

  now = written()
  check("check: nothing on Ghostty's screen is left in a color that is not the theme's",
    now.check:find("every highlight on screen wears this theme's colors", 1, true) ~= nil, strays_in(now.check))
  vim.rpcrequest(window.channel, "nvim_command", "hi E2EStray guifg=#123456")
  now = written()
  check("check: a color from nowhere is found, with the role nearest it",
    now.check:find("E2EStray  fg #123456 (nearest role: ", 1, true) ~= nil, strays_in(now.check))
  vim.rpcrequest(window.channel, "nvim_command", "hi clear E2EStray")

  if not vim.uv.fs_stat(vim.fs.joinpath(PLUGINS, "nvim-web-devicons")) then
    print("skip  icons: nvim-web-devicons is not installed in " .. PLUGINS)
    close(window)
    return
  end
  check("icons: the plugin's hundreds of icons are all the theme's",
    now.icons > 100 and now.astray == 0 and now.lua_icon ~= "#51a0cf", vim.inspect({ now.icons, now.astray, now.lua_icon }))
  reload(window, THEMES.onelight)
  check("icons: and stay so through a dark to light reload, when the plugin puts its own back",
    settled(function(state)
      return follows(THEMES.onelight)(state) and state.icons > 100
    end))
  close(window)

  local fixed = open(THEMES.dracula, nil, false,
    { COLORREX_E2E_ROLES = "1", COLORREX_E2E_PLUGINS = PLUGINS, COLORREX_E2E_ICONS = "off" })
  local shipped
  vim.wait(3000, function()
    shipped = written(fixed.channel)
    return shipped.base == THEMES.dracula.bg and shipped.icons > 100
  end, 40)
  check("icons: off leaves them as the plugin shipped them", shipped.lua_icon == "#51a0cf" and shipped.astray > 100,
    vim.inspect({ shipped.lua_icon, shipped.astray }))
  check("icons: and check counts them as one family", shipped.check:find("DevIcon%* %(%d+ groups%)") ~= nil,
    strays_in(shipped.check))
  close(fixed)
end

-- COLORREX_E2E_ONLY names one part to run alone, such as `roles`.
local ok, err = xpcall(function()
  local only = vim.env.COLORREX_E2E_ONLY
  if not only or only == "lifecycle" then
    suite()
  end
  if not only or only == "roles" then
    roles_suite()
  end
end, debug.traceback)
for _, window in ipairs(windows) do
  close(window)
end
vim.fn.delete(work, "rf")
if not ok then
  print("ERROR " .. tostring(err))
  failed = failed + 1
end
print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed > 0 and 1 or 0)
