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

local function open(theme, extra, manual)
  count = count + 1
  local dir = ("%s/%d"):format(work, count)
  vim.fn.mkdir(dir, "p")
  local window = { conf = dir .. "/ghostty.conf", socket = dir .. "/nvim.sock", extra = extra }
  write(window.conf, config_text(theme, extra))
  window.process = vim.system({
    "ghostty", "--config-default-files=false", "--config-file=" .. window.conf, "-e",
    vim.v.progpath, "-n", "--listen", window.socket, "-u", root .. "/test/e2e/init.lua", root .. "/test/e2e/sample.lua",
  }, {
    clear_env = true,
    env = {
      HOME = vim.env.HOME,
      PATH = vim.env.PATH,
      WAYLAND_DISPLAY = vim.env.WAYLAND_DISPLAY,
      DISPLAY = vim.env.DISPLAY,
      XDG_RUNTIME_DIR = vim.env.XDG_RUNTIME_DIR,
      DBUS_SESSION_BUS_ADDRESS = vim.env.DBUS_SESSION_BUS_ADDRESS,
      XDG_STATE_HOME = dir .. "/state",
      COLORREX_ROOT = root,
      COLORREX_E2E_MANUAL = manual and "1" or nil,
    },
  })
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

local ok, err = xpcall(suite, debug.traceback)
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
