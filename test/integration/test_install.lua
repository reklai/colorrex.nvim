-- The install, for real: a fresh Neovim with a fresh lazy.nvim, resolving the plugin
-- by the exact name in the README. lazy's `dev` mode points that name at this
-- checkout, so no network is involved. Skips where lazy.nvim is not installed.
local T = require("harness")

local LAZY = vim.env.COLORREX_LAZY or vim.fs.joinpath(vim.fn.stdpath("data"), "lazy", "lazy.nvim")

local function root()
  return vim.fn.fnamemodify(T.root, ":p"):gsub("/$", "")
end

--- Start Neovim with `spec` as the only plugin and report what happened.
local function install(spec)
  if not vim.uv.fs_stat(LAZY) then
    T.skip("lazy.nvim is not installed at " .. LAZY)
  end
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local init = dir .. "/init.lua"
  local plugin_parent = vim.fs.dirname(root())
  local file = assert(io.open(init, "w"))
  file:write(([[
vim.opt.rtp:prepend(%q)
require("lazy").setup({ spec = { %s }, dev = { path = %q, patterns = { "reklai" }, fallback = false },
  install = { missing = false }, rocks = { enabled = false }, change_detection = { enabled = false } })
vim.schedule(function()
  local plugin = require("lazy.core.config").plugins["colorrex.nvim"]
  local Config = require("colorrex.config")
  io.stdout:write(vim.json.encode({
    colors_name = vim.g.colors_name or "",
    loaded = plugin ~= nil and plugin._.loaded ~= nil,
    is_lazy = plugin ~= nil and plugin.lazy == true,
    priority = plugin ~= nil and plugin.priority or 0,
    command = vim.fn.exists(":ColorRex"),
    mapped = next(vim.fn.maparg("<Plug>(colorrex)", "n", false, true)) ~= nil,
    transparent = vim.api.nvim_get_hl(0, { name = "Normal" }).bg == nil,
    lualine = #vim.api.nvim_get_runtime_file("lua/lualine/themes/colorrex.lua", false),
  }))
  vim.cmd("qa!")
end)
]]):format(LAZY, spec, plugin_parent))
  file:close()
  local result = vim.system({ vim.v.progpath, "--headless", "-n", "-u", init }, {
    text = true,
    env = {
      XDG_STATE_HOME = dir .. "/state", XDG_DATA_HOME = dir .. "/data", XDG_CACHE_HOME = dir .. "/cache",
      XDG_CONFIG_HOME = dir .. "/config",
    },
  }):wait(20000)
  local json = (result.stdout or ""):match("{.*}")
  T.ok(json, "no result: " .. tostring(result.stderr))
  return vim.json.decode(json)
end

T.test("install: the one-line lazy.nvim spec is a complete install", function()
  local state = install([["reklai/colorrex.nvim"]])
  T.eq(state.colors_name, "colorrex")
  T.ok(state.loaded, "loaded at startup")
  T.ok(not state.is_lazy, "not lazy-loaded")
  T.eq(state.priority, 1000)
  T.eq(state.command, 2)
  T.ok(state.mapped, "<Plug>(colorrex)")
  T.eq(state.lualine, 1)
end)

T.test("install: a canvasdiff-style explicit spec works the same", function()
  local state = install([[{ "reklai/colorrex.nvim", lazy = false, priority = 1000, opts = {} }]])
  T.eq(state.colors_name, "colorrex")
  T.eq(state.priority, 1000)
end)

T.test("install: a user's opts reach setup", function()
  T.ok(install([["reklai/colorrex.nvim"]]).transparent)
  T.ok(not install([[{ "reklai/colorrex.nvim", opts = { transparent = false } }]]).transparent)
end)

T.test("install: a bad option fails loudly, it does not vanish", function()
  if not vim.uv.fs_stat(LAZY) then
    T.skip("lazy.nvim is not installed at " .. LAZY)
  end
  local ok = pcall(function()
    require("colorrex").setup({ transparant = true })
  end)
  T.ok(not ok)
end)
