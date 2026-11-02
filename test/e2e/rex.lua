-- Real Neovim, in real Rex blocks, with real theme changes.
--
--   nvim -l test/e2e/rex.lua        (run it from inside Rex; `make e2e`)
--
-- It creates one throwaway session and removes it, whatever happens. Rex only
-- honors set_theme on a block nothing owns, so every block here comes from
-- `rex window new`, never `rex new`. Each step reads the color back from the
-- terminal first: a test that did not actually change the theme proves nothing.
-- The binary running this script is the one under test.
local root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(arg[0], ":p"))))
package.path = root .. "/test/e2e/?.lua;" .. package.path
local work = vim.fn.tempname()
vim.fn.mkdir(work, "p")

local passed, failed = 0, 0
local function check(name, ok, detail)
  if ok then
    passed = passed + 1
    print("ok    " .. name)
  else
    failed = failed + 1
    print("FAIL  " .. name .. (detail and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local function rex(...)
  local result = vim.system({ "rex", ... }, { text = true }):wait()
  if result.code ~= 0 then
    error(("rex %s: %s"):format(table.concat({ ... }, " "), result.stderr))
  end
  return result.stdout
end

local function wait(ms)
  vim.wait(ms, function() return false end)
end

local function rex_theme(theme)
  local palette = {}
  for index, hex in ipairs(theme.ansi) do
    palette[index] = ("%d=%s"):format(index - 1, hex)
  end
  return { foreground = theme.fg, background = theme.bg, cursor = theme.cursor, palette = palette }
end

local THEMES = {}
for name, theme in pairs(require("themes")) do
  THEMES[name] = rex_theme(theme)
end

local session = vim.json.decode(rex("new", "colorrex-e2e", "--json", "--shell=none", "--", "/bin/sleep", "600")).session_id

local function nvim_tab(name, delay, env, extra)
  local parts = { ("sleep %s;"):format(delay), "COLORREX_ROOT=" .. root, "XDG_STATE_HOME=" .. (env or work) }
  parts[#parts + 1] = extra
  parts[#parts + 1] = ("exec %s -n -u %s/test/e2e/init.lua %s/test/e2e/sample.lua"):format(vim.v.progpath, root, root)
  local tab = vim.json.decode(rex("window", "new", "-s", session, name, "--focus=false", "--json", "--shell=none",
    "--", "/bin/sh", "-c", table.concat(parts, " ")))
  return { block = tab.block_ids[1], window = tab.window_id, name = name }
end

local function theme(tab, name)
  rex("do", "-s", session, "-b", tab.block, "com.superlogical.terminal.set_theme", "--args",
    vim.json.encode(THEMES[name]))
  local out = rex("do", "-s", session, "-b", tab.block, "com.superlogical.terminal.format",
    "extra_palette=true", "format=vt", "max_bytes=12000")
  local r, g, b = vim.json.decode(out).content:match("\027%]4;1;rgb:(%x+)/(%x+)/(%x+)")
  local want = THEMES[name].palette[2]:match("=(.*)")
  assert(("#%s%s%s"):format(r, g, b) == want, "the terminal did not take theme " .. name)
end

local function send(tab, text)
  rex("send", "-s", session, "-b", tab.block, text)
end

local dumps = 0
local function dump(tab)
  dumps = dumps + 1
  local path = ("%s/dump-%d.json"):format(work, dumps)
  send(tab, "\027:E2EDump " .. path .. "\r")
  vim.wait(2000, function() return vim.uv.fs_stat(path) ~= nil end, 20)
  wait(30)
  local file = assert(io.open(path))
  local state = vim.json.decode(file:read("*a"))
  file:close()
  return state
end

local function focus(tab)
  rex("window", "focus", "-s", session, tab.window)
end

local function suite()
  local tab = nvim_tab("lifecycle", "0.3")
  wait(1800)
  local state = dump(tab)
  check("a block with no theme shows its built-in ANSI colors, marked partial",
    state.completeness == "partial" and state.terminal1 == "#cc6666", vim.inspect(state))
  check("a block with no theme is retried after launch", state.reason == "retry", state.reason)

  theme(tab, "dracula")
  send(tab, "gS")
  wait(400)
  state = dump(tab)
  check("the keybind syncs a first theme", state.bg == "#282a36" and state.string ~= vim.NIL, vim.inspect(state))
  check("a live sync reports a full theme from the terminal", state.completeness == "full" and state.source == "terminal")
  check("transparent: the terminal keeps painting the background", state.normal_bg == vim.NIL)
  check("colorscheme stays colorrex", state.colors_name == "colorrex")

  theme(tab, "gruvbox")
  wait(600)
  state = dump(tab)
  check("dark to dark changes nothing until asked (no signal exists)", state.bg == "#282a36", state.bg)
  send(tab, "\027:ColorRex\r")
  wait(400)
  state = dump(tab)
  check(":ColorRex catches a dark-to-dark change", state.bg == "#282828", state.bg)

  theme(tab, "onelight")
  wait(600)
  state = dump(tab)
  check("dark to light is automatic", state.bg == "#fafafa" and state.background == "light", vim.inspect(state))

  theme(tab, "dracula")
  wait(600)
  state = dump(tab)
  check("light to dark is automatic", state.bg == "#282a36" and state.background == "dark", vim.inspect(state))

  theme(tab, "gruvbox")
  wait(300)
  focus(tab)
  wait(500)
  state = dump(tab)
  check("a focus change catches a dark-to-dark change", state.bg == "#282828", state.bg)

  send(tab, "\027:qa!\r")
  wait(300)

  local cached = nvim_tab("cache", "0.1")
  wait(120)
  wait(900)
  state = dump(cached)
  check("the next launch starts on the last theme, not on built-in colors",
    state.bg == "#282828" and state.source == "cache", vim.inspect(state))
  send(cached, "\027:qa!\r")
  wait(300)

  local explicit = nvim_tab("explicit", "0.3", nil, "COLORREX_E2E_BACKGROUND=dark")
  wait(900)
  theme(explicit, "dracula")
  send(explicit, "gS")
  wait(400)
  theme(explicit, "onelight")
  wait(600)
  state = dump(explicit)
  check("dark to light is automatic even when the user set 'background' themselves",
    state.bg == "#fafafa" and state.background == "light", vim.inspect(state))
  send(explicit, "\027:qa!\r")
  wait(300)

  -- Two Neovims and one keypress. Every other test here has one Neovim, so this
  -- is the only proof that the broadcast crosses between real processes.
  local shared = vim.fn.tempname()
  vim.fn.mkdir(shared, "p")
  local first = nvim_tab("broadcast-a", "0.3", shared)
  local second = nvim_tab("broadcast-b", "0.3", shared)
  local manual = nvim_tab("broadcast-c", "0.3", shared, "COLORREX_E2E_MANUAL=1")
  wait(5500) -- launch retries finish, so nothing but the broadcast can act
  for _, tab in ipairs({ first, second, manual }) do
    theme(tab, "dracula")
    send(tab, "gS")
  end
  wait(500)
  for _, tab in ipairs({ first, second, manual }) do
    theme(tab, "gruvbox")
  end
  wait(500)
  check("broadcast: nothing happens before the keypress", dump(second).bg == "#282a36")
  send(first, "gS")
  wait(500)
  state = dump(first)
  check("broadcast: the Neovim that was asked updates", state.bg == "#282828", state.bg)
  state = dump(second)
  check("broadcast: a Neovim nobody touched follows", state.bg == "#282828" and state.reason == "broadcast", vim.inspect(state))
  state = dump(manual)
  check("broadcast: auto = false stays put", state.bg == "#282a36", state.bg)

  theme(second, "dracula") -- this block now shows a theme of its own
  send(first, "gS")
  send(second, "gS")
  wait(400)
  theme(first, "onelight")
  wait(800)
  state = dump(first)
  local other = dump(second)
  check("broadcast: each block keeps the theme its own terminal shows",
    state.bg == "#fafafa" and other.bg == "#282a36", vim.inspect({ state.bg, other.bg }))
  for _, tab in ipairs({ first, second, manual }) do
    send(tab, "\027:qa!\r")
  end
  wait(300)

  -- Decorations only run during a real redraw, so only a terminal can show them.
  local chunky = work .. "/chunky.lua"
  local file = assert(io.open(chunky, "w"))
  file:write("function long_name()\n  a()\n  b()\n  c()\n  d()\nend\n")
  file:close()
  local shape = nvim_tab("shape", "0.2")
  wait(900)
  theme(shape, "dracula")
  send(shape, "\027:lua require('colorrex').setup({ chunks = true })\r")
  wait(200)
  send(shape, (":edit %s\r:lua vim.treesitter.start()\r"):format(chunky))
  wait(500)
  local function name_style()
    local out = rex("do", "-s", session, "-b", shape.block, "com.superlogical.terminal.format",
      "extra_style=true", "format=vt", "max_bytes=20000")
    local content = vim.json.decode(out).content
    local before = content:sub(1, assert(content:find("long_name", 1, true)) - 1)
    local codes = {} -- a terminal can write one style as several sequences in a row
    local sequence = before:match("(\027%[[%d;:]*m)$")
    while sequence do
      table.insert(codes, 1, sequence:sub(3, -2))
      before = before:sub(1, -#sequence - 1)
      sequence = before:match("(\027%[[%d;:]*m)$")
    end
    return table.concat(codes, ";")
  end
  local function bold(style)
    return (";" .. style .. ";"):find(";1;", 1, true) ~= nil
  end
  local on = name_style()
  check("chunks: a landmark is drawn in the terminal", bold(on), tostring(on))
  send(shape, "\027:lua require('colorrex').setup({ chunks = false })\r")
  wait(400)
  local off = name_style()
  check("chunks: and is gone when turned off", not bold(off), tostring(off))
  send(shape, "\027:qa!\r")

  local fresh = vim.fn.tempname()
  vim.fn.mkdir(fresh, "p")
  local race = nvim_tab("race", "0", fresh)
  wait(120) -- Neovim has already asked, and heard only built-in colors
  theme(race, "dracula")
  wait(1500)
  state = dump(race)
  check("a theme landing just after launch is picked up by the retry, with no key pressed",
    state.bg == "#282a36" and state.completeness == "full" and state.reason == "retry", vim.inspect(state))
  send(race, "\027:qa!\r")
end

local ok, err = xpcall(suite, debug.traceback)
pcall(rex, "kill", session)
vim.fn.delete(work, "rf")
if not ok then
  print("ERROR " .. tostring(err))
  failed = failed + 1
end
print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed > 0 and 1 or 0)
