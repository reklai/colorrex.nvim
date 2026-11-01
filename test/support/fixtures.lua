-- Shared test data: a theme, its replies, and a stand-in for the Neovim host.
local F = {}

--- A complete theme, for tests that need one. `overrides` replace fields.
function F.theme(overrides)
  local theme = {
    fg = "#d8dee9", bg = "#1b1f27", cursor = "#ff4fd8",
    ansi = {
      [0] = "#2e3440", [1] = "#e06c75", [2] = "#98c379", [3] = "#e5c07b",
      [4] = "#61afef", [5] = "#c678dd", [6] = "#56b6c2", [7] = "#abb2bf",
      [8] = "#6c7686", [9] = "#ef7f88", [10] = "#a9d48c", [11] = "#efcf8e",
      [12] = "#79bdf3", [13] = "#d28fe6", [14] = "#6cc4cf", [15] = "#eceff4",
    },
  }
  for key, value in pairs(overrides or {}) do
    theme[key] = value
  end
  return theme
end

--- A stand-in for the Neovim host: records effects, and runs time by hand.
function F.fake_host(overrides)
  local host = {
    sent = {}, messages = {}, renders = 0, applies = 0, bg = "dark", ready = true, cache = nil,
    now = 0, timers = {}, handlers = nil,
  }
  function host.ui_ready() return host.ready end
  function host.background() return host.bg end
  function host.send(text) host.sent[#host.sent + 1] = text end
  function host.after(ms, fn)
    local timer = { at = host.now + ms, fn = fn }
    host.timers[#host.timers + 1] = timer
    return function() timer.fn = nil end
  end
  function host.advance(ms)
    host.now = host.now + ms
    for _, timer in ipairs(host.timers) do
      if timer.fn and timer.at <= host.now then
        local fn = timer.fn
        timer.fn = nil
        fn()
      end
    end
  end
  function host.defer(fn) fn() end
  function host.render(colorscheme)
    host.renders = host.renders + 1
    host.shown = colorscheme
    host.bg = colorscheme.background
  end
  host.on_apply = nil
  function host.apply()
    host.applies = host.applies + 1
    if host.on_apply then host.on_apply() end
  end
  function host.subscribe(handlers) host.handlers = handlers end
  function host.unsubscribe() host.handlers = nil end
  function host.notify(message, level) host.messages[#host.messages + 1] = { message = message, level = level } end
  function host.cache_read() return host.cache end
  function host.cache_write(text) host.cache = text end
  function host.groups_under_cursor() return host.cursor_groups or {} end
  function host.colors_path(name) return "/colors/" .. name .. ".lua" end
  function host.exists(path) return host.files ~= nil and host.files[path] ~= nil end
  function host.write(path, text)
    host.files = host.files or {}
    host.files[path] = text
    return true
  end
  for key, value in pairs(overrides or {}) do
    host[key] = value
  end
  return host
end

--- The terminal's reply to a query for `theme`, as Neovim delivers it: one
--- sequence, terminator stripped, with an empty value for any color it lacks.
function F.reply(theme)
  local function rgb(hex)
    if not hex then
      return ""
    end
    return "rgb:" .. hex:gsub("#(%x%x)(%x%x)(%x%x)", "%1/%2/%3")
  end
  local parts = {
    "foreground=" .. rgb(theme.fg),
    "background=" .. rgb(theme.bg),
    "cursor=" .. rgb(theme.cursor),
  }
  for slot = 0, 15 do
    parts[#parts + 1] = ("%d=%s"):format(slot, rgb(theme.ansi and theme.ansi[slot]))
  end
  return "\027]21;" .. table.concat(parts, ";")
end

return F
