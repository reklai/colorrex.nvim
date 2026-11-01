-- color-rex: compiles the theme a libghostty terminal is showing into a native
-- Neovim colorscheme, with no dependencies. `:help color-rex`
local App = require("color-rex.app")
local Commands = require("color-rex.commands")
local Config = require("color-rex.config")

local M = {}

local config = Config.resolve()
local app, warned

local function get()
  if not app then
    app = App.new(require("color-rex.neovim").new(), config)
  end
  return app
end

--- The floor, asserted rather than assumed: nvim_ui_send arrived in Neovim 0.12.
local function supported()
  if vim.fn.has("nvim-0.12") == 1 then
    return true
  end
  if not warned then
    warned = true
    vim.notify("color-rex requires Neovim 0.12 or newer", vim.log.levels.ERROR)
  end
  return false
end

--- Turn the colorscheme on, with options if there are any. This is what lazy.nvim
--- calls for `opts = {}`, so installing the plugin is all it takes.
function M.setup(opts)
  config = Config.resolve(opts)
  if app then
    app:configure(config)
  end
  vim.cmd.colorscheme(Config.NAME)
end

--- Called by `:colorscheme color-rex`.
function M.load()
  if supported() then
    get():load()
  end
end

--- The current state, as a table.
function M.status()
  return get():status()
end

--- The current lualine theme. Used by lua/lualine/themes/color-rex.lua.
function M.lualine()
  return get():current().lualine
end

--- Entry point for `:ColorRex`.
function M.command(fargs, bang)
  local problem = Commands.run(get(), fargs, bang)
  if problem then
    vim.notify("color-rex: " .. problem, vim.log.levels.ERROR)
  end
end

return M
