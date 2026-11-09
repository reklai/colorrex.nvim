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

--- Neovim inside tmux inside a Rex block. tmux runs with no config of its own,
--- as a fresh install does, unless `conf` names settings for it.
local function nvim_tmux_tab(name, env, conf)
  local socket = "colorrex-e2e-" .. name
  local parts = { "COLORREX_ROOT=" .. root, "XDG_STATE_HOME=" .. (env or work), "COLORREX_E2E_UPDATETIME=300" }
  local listen = ("%s/%s.sock"):format(work, name)
  parts[#parts + 1] = ("exec %s -n --listen %s -u %s/test/e2e/init.lua %s/test/e2e/sample.lua"):format(
    vim.v.progpath, listen, root, root)
  local conf_path = ("%s/%s.tmux.conf"):format(work, name)
  local file = assert(io.open(conf_path, "w"))
  for _, setting in ipairs(conf or {}) do
    file:write(("set -g %s %s\n"):format(setting[1], setting[2]))
  end
  file:close()
  local command = { "tmux", "-L", socket, "-f", conf_path, "new-session", table.concat(parts, " ") }
  local tab = vim.json.decode(rex("window", "new", "-s", session, name, "--focus=false", "--json", "--shell=none",
    "--", unpack(command)))
  return { block = tab.block_ids[1], window = tab.window_id, name = name, socket = socket, listen = listen }
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

--- The SGR codes the terminal drew just before the first `word` on screen.
local function style_before(tab, word)
  local out = rex("do", "-s", session, "-b", tab.block, "com.superlogical.terminal.format",
    "extra_style=true", "format=vt", "max_bytes=20000")
  local content = vim.json.decode(out).content
  local at = content:find(word, 1, true)
  if not at then
    return nil
  end
  local before = content:sub(1, at - 1)
  local codes = {} -- a terminal can write one style as several sequences in a row
  local sequence = before:match("(\027%[[%d;:]*m)$")
  while sequence do
    table.insert(codes, 1, sequence:sub(3, -2))
    before = before:sub(1, -#sequence - 1)
    sequence = before:match("(\027%[[%d;:]*m)$")
  end
  return table.concat(codes, ";")
end

--- Whether SGR codes set the foreground to `hex`.
local function draws(style, hex)
  if not style or not hex or hex == vim.NIL then
    return false
  end
  local r, g, b = hex:match("#(%x%x)(%x%x)(%x%x)")
  local want = ("38;2;%d;%d;%d"):format(tonumber(r, 16), tonumber(g, 16), tonumber(b, 16))
  return (";" .. style .. ";"):find(";" .. want .. ";", 1, true) ~= nil
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

  -- Rex's picker takes focus and previews themes without telling the block. Another
  -- window taking focus is the same event, and set_theme the same silent change.
  local elsewhere = vim.json.decode(rex("window", "new", "-s", session, "elsewhere", "--focus=false", "--json",
    "--shell=none", "--", "/bin/sleep", "600"))
  rex("window", "focus", "-s", session, elsewhere.window_id)
  wait(300)
  theme(tab, "dracula")
  wait(250)
  state = dump(tab)
  check("unfocused, a dark-to-dark change shows with no key pressed", state.bg == "#282a36", state.bg)
  theme(tab, "dracula_tint")
  wait(250)
  state = dump(tab)
  check("and so does the next one, as a picker moves on", state.bg == "#2d2f3b", state.bg)
  theme(tab, "gruvbox") -- what the cache test below expects to find saved
  focus(tab)
  wait(500)

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

  -- Meanings are drawn on redraw, over what the highlighter paints, so only a terminal
  -- can show them. Lua's parser ships with Neovim, so this needs nothing installed.
  local failing = work .. "/failing.lua"
  file = assert(io.open(failing, "w"))
  file:write("local ok, err = pcall(load)\nif not ok then\n  return nil, err\nend\nlocal count = 40961\n")
  file:close()
  local reader = nvim_tab("meanings", "0.2")
  wait(900)
  theme(reader, "dracula")
  send(reader, "gS")
  wait(300)
  send(reader, (":edit %s\r:lua vim.treesitter.start()\r"):format(failing))
  wait(600)
  state = dump(reader)
  check("meanings: nil is drawn in failure's color, with no option set",
    draws(style_before(reader, "nil"), state.failure), vim.inspect({ style_before(reader, "nil"), state.failure }))
  check("meanings: so is err, which no grammar marks",
    draws(style_before(reader, "err"), state.failure), vim.inspect({ style_before(reader, "err"), state.failure }))
  check("meanings: and a number is a value, not failure",
    draws(style_before(reader, "40961"), state.value) and state.value ~= state.failure,
    vim.inspect({ style_before(reader, "40961"), state.value }))
  local negation = style_before(reader, "not")
  check("meanings: and `not` is negation, in control's color and bold",
    draws(negation, state.negation) and bold(negation), vim.inspect({ negation, state.negation }))
  send(reader, "\027:qa!\r")
  wait(300)

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

-- tmux in a libghostty terminal: the same Neovim, with tmux between it and Rex.
local function tmux_suite()
  if vim.fn.executable("tmux") == 0 then
    print("SKIP  tmux is not installed")
    return
  end
  -- A direct Neovim sees Dracula whole, cursor and all, and saves it.
  local shared = vim.fn.tempname()
  vim.fn.mkdir(shared, "p")
  local direct = nvim_tab("tmux-direct", "0.3", shared)
  wait(900)
  theme(direct, "dracula")
  send(direct, "gS")
  wait(500)
  local seen = dump(direct)
  send(direct, "\027:qa!\r")
  wait(300)

  local tab = nvim_tmux_tab("tmux-plain", shared)
  wait(300)
  theme(tab, "dracula")
  wait(2500) -- launch, its retries, and tmux learning the block's colors
  local state = dump(tab)
  check("tmux: with no tmux config, Neovim gets the terminal's whole palette",
    state.bg == "#282a36" and state.completeness == "full" and state.route == "xterm", vim.inspect(state))
  check("tmux: the cursor tmux hides comes from the last full read, so the theme reads the same",
    state.borrowed ~= false and state.voice == seen.voice, vim.inspect({ state.borrowed, state.voice, seen.voice }))

  theme(tab, "gruvbox")
  send(tab, "\027") -- a key, then a pause, as when someone stops typing
  wait(1200)
  state = dump(tab)
  -- tmux forwards every palette query to Rex, but keeps fg and bg from Rex's last
  -- report, and Rex reports only dark/light changes. Ghostty reports every change,
  -- and allow-passthrough carries fg and bg directly.
  check("tmux: a dark-to-dark palette change tmux never reports shows after a pause in typing",
    state.terminal1 == "#cc241d", vim.inspect(state))

  theme(tab, "onelight")
  wait(1200)
  state = dump(tab)
  check("tmux: dark to light is automatic, as tmux forwards that report",
    state.bg == "#fafafa" and state.background == "light", vim.inspect(state))
  send(tab, "\027:qa!\r")
  wait(300)
  vim.system({ "tmux", "-L", tab.socket, "kill-server" }):wait()

  local passing = nvim_tmux_tab("tmux-passthrough", nil, { { "allow-passthrough", "on" } })
  wait(300)
  theme(passing, "gruvbox")
  wait(2500)
  state = dump(passing)
  check("tmux: with allow-passthrough on, the whole theme comes through in one read",
    state.bg == "#282828" and state.route == "kitty" and state.completeness == "full", vim.inspect(state))
  send(passing, "\027:qa!\r")
  wait(300)
  vim.system({ "tmux", "-L", passing.socket, "kill-server" }):wait()
end

--- How long, in ms, until an unfocused Neovim in `tab` shows `want` as its red,
--- after the block's theme changes the way a picker preview does: silently, with
--- focus elsewhere. nil if it never does within `limit`.
local function preview_latency(tab, name, want, limit)
  theme(tab, name)
  local start = vim.uv.hrtime()
  -- Asked over RPC, never by typing: a keypress would start the check colorrex runs
  -- when typing pauses, and a real picker sends Neovim no keys at all.
  local channel = vim.fn.sockconnect("pipe", tab.listen, { rpc = true })
  while (vim.uv.hrtime() - start) / 1e6 < limit do
    local ok, red = pcall(vim.rpcrequest, channel, "nvim_exec_lua", "return vim.g.terminal_color_1", {})
    if ok and red == want then
      vim.fn.chanclose(channel)
      return math.floor((vim.uv.hrtime() - start) / 1e6)
    end
    wait(20)
  end
  vim.fn.chanclose(channel)
  return nil
end

-- A picker in Rex takes focus and previews themes without a word to the block. Inside
-- tmux, Neovim hears of focus only with focus-events on, and reaches Rex's own colors
-- only with allow-passthrough on.
local function picker_suite()
  if vim.fn.executable("tmux") == 0 then
    print("SKIP  tmux is not installed")
    return
  end
  local elsewhere = vim.json.decode(rex("window", "new", "-s", session, "picker-focus", "--focus=false", "--json",
    "--shell=none", "--", "/bin/sleep", "600"))
  local function run(label, conf)
    local fresh = vim.fn.tempname() -- nothing saved: what it shows, it heard
    vim.fn.mkdir(fresh, "p")
    local tab = nvim_tmux_tab("picker-" .. label, fresh, conf)
    wait(300)
    theme(tab, "dracula")
    focus(tab)
    wait(2500)
    rex("window", "focus", "-s", session, elsewhere.window_id) -- the picker opens
    wait(300)
    local first = preview_latency(tab, "gruvbox", "#cc241d", 3000)
    local second = preview_latency(tab, "dracula", "#ff5555", 3000)
    send(tab, "\027:qa!\r")
    wait(300)
    vim.system({ "tmux", "-L", tab.socket, "kill-server" }):wait()
    return first, second
  end
  local plain = { run("plain") }
  print(("info  tmux defaults: previews after %s and %s ms"):format(tostring(plain[1]), tostring(plain[2])))
  local tuned = { run("tuned", { { "focus-events", "on" }, { "allow-passthrough", "on" } }) }
  print(("info  focus-events and allow-passthrough on: previews after %s and %s ms"):format(
    tostring(tuned[1]), tostring(tuned[2])))
  check("tmux, tuned: a picker preview shows within half a second, as it does without tmux",
    tuned[1] and tuned[1] < 500 and tuned[2] and tuned[2] < 500, vim.inspect(tuned))
end

-- What the meanings cost a real redraw. A keystroke or a scroll must cost what it costs
-- without them, near enough, or the editor stops feeling like itself.
local function speed_suite()
  local listen = ("/run/user/%d/crx-e2e-speed.sock"):format(vim.uv.getuid()) -- short: sockets cap paths
  os.remove(listen)
  local command = ("COLORREX_ROOT=%s XDG_STATE_HOME=%s exec %s -n --listen %s -u %s/test/e2e/init.lua %s/lua/colorrex/roles.lua")
    :format(root, work, vim.v.progpath, listen, root, root)
  local tab = vim.json.decode(rex("window", "new", "-s", session, "speed", "--focus=false", "--json", "--shell=none",
    "--", "/bin/sh", "-c", command))
  vim.wait(8000, function() return vim.uv.fs_stat(listen) ~= nil end, 50)
  wait(1200)
  local channel = vim.fn.sockconnect("pipe", listen, { rpc = true })
  local function lua(code, ...) return vim.rpcrequest(channel, "nvim_exec_lua", code, { ... }) end
  lua("vim.treesitter.start() vim.wait(300)")
  local scroll = [[
    vim.cmd("normal! gg")
    local t = vim.uv.hrtime()
    for _ = 1, 300 do vim.cmd("normal! \5") vim.cmd("redraw") end
    return (vim.uv.hrtime() - t) / 1e6 / 300
  ]]
  local typing = [[
    local row
    for r = 40, 400 do
      if vim.api.nvim_buf_get_lines(0, r - 1, r, false)[1]:match("^%s+local [%a_]+ = ") then row = r - 1 break end
    end
    local col = vim.api.nvim_buf_get_lines(0, row, row + 1, false)[1]:find(" = ") - 1
    vim.api.nvim_win_set_cursor(0, { row + 1, 0 }) vim.cmd("normal! zz")
    local t = vim.uv.hrtime()
    for _ = 1, 200 do
      vim.api.nvim_buf_set_text(0, row, col, row, col, { "x" }) col = col + 1
      vim.cmd("redraw")
    end
    local per = (vim.uv.hrtime() - t) / 1e6 / 200
    vim.cmd("silent! undo 0")
    return per
  ]]
  lua(scroll) lua(typing) -- warm
  local on = { scroll = lua(scroll), typing = lua(typing) }
  lua("vim.api.nvim_set_decoration_provider(vim.api.nvim_create_namespace('colorrex.chunks'), {})")
  local off = { scroll = lua(scroll), typing = lua(typing) }
  print(("info  per frame with meanings / without: scroll %.2f / %.2f ms, typing %.2f / %.2f ms"):format(
    on.scroll, off.scroll, on.typing, off.typing))
  for _, kind in ipairs({ "scroll", "typing" }) do
    check(("speed: meanings cost a %s nothing a person could feel"):format(kind),
      on[kind] <= off[kind] * 1.5 + 0.3, vim.inspect({ on = on[kind], off = off[kind] }))
  end
  pcall(vim.rpcrequest, channel, "nvim_command", "qa!")
  os.remove(listen)
end

local function all()
  suite()
  tmux_suite()
  picker_suite()
  speed_suite()
end

local ok, err = xpcall(all, debug.traceback)
pcall(rex, "kill", session)
vim.fn.delete(work, "rf")
if not ok then
  print("ERROR " .. tostring(err))
  failed = failed + 1
end
print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed > 0 and 1 or 0)
