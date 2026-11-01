-- The Neovim host: the one module that touches the outside world. Each function
-- is a single effect and makes no decisions; those belong to App, where they can
-- be tested.
local Config = require("color-rex.config")

local M = {}

local PREFIX = "color-rex: "
local GROUP = "color-rex"

local function state_path()
  return vim.fs.joinpath(vim.fn.stdpath("state"), "color-rex", "theme")
end

function M.new()
  local host = {}
  local watcher

  function host.ui_ready()
    if vim.v.vim_did_enter ~= 1 then
      return false
    end
    for _, ui in ipairs(vim.api.nvim_list_uis()) do
      if ui.stdout_tty then
        return true
      end
    end
    return false
  end

  function host.background()
    return vim.o.background
  end

  function host.send(text)
    vim.api.nvim_ui_send(text)
  end

  function host.after(ms, fn)
    local timer = assert(vim.uv.new_timer())
    local cancelled = false
    local function close()
      if not timer:is_closing() then
        timer:stop()
        timer:close()
      end
    end
    timer:start(ms, 0, function()
      close()
      vim.schedule(function()
        if not cancelled then
          fn()
        end
      end)
    end)
    return function()
      cancelled = true
      close()
    end
  end

  function host.defer(fn)
    -- Never repaint from inside TermResponse: autocommands do not nest there,
    -- so ColorScheme would not fire and plugins would keep the old colors.
    vim.schedule(fn)
  end

  function host.render(colorscheme)
    if vim.g.colors_name then
      vim.cmd.highlight("clear") -- this also unsets g:colors_name
    end
    vim.g.colors_name = Config.NAME
    vim.o.termguicolors = true
    if vim.o.background ~= colorscheme.background then
      vim.o.background = colorscheme.background
    end
    local set = vim.api.nvim_set_hl
    for group, spec in pairs(colorscheme.groups) do
      set(0, group, spec)
    end
    for slot = 0, 15 do
      vim.g["terminal_color_" .. slot] = colorscheme.terminal_colors[slot]
    end
  end

  function host.apply()
    vim.cmd.colorscheme(Config.NAME)
  end

  function host.subscribe(handlers)
    local group = vim.api.nvim_create_augroup(GROUP, { clear = true })
    local autocmd = vim.api.nvim_create_autocmd
    autocmd("TermResponse", {
      group = group,
      callback = function(ev)
        if ev.data then
          handlers.response(ev.data.sequence)
        end
      end,
    })
    autocmd("FocusGained", { group = group, callback = function() handlers.focus() end })
    autocmd("VimResume", { group = group, callback = function() handlers.resume() end })
    autocmd("UIEnter", { group = group, callback = function() handlers.ui_enter() end })
    autocmd("VimLeavePre", { group = group, callback = function() handlers.leaving() end })
    autocmd("ColorScheme", {
      group = group,
      callback = function(ev)
        handlers.colorscheme_changed(ev.match)
      end,
    })
    -- Best effort, like the cache it watches: without it, a Neovim just waits for
    -- its own focus event or sync. It is event-driven, so it costs nothing idle.
    local directory = vim.fs.dirname(state_path())
    pcall(vim.fn.mkdir, directory, "p")
    watcher = vim.uv.new_fs_event()
    if watcher then
      watcher:start(directory, {}, function(err, name)
        if not err and name == vim.fs.basename(state_path()) then
          vim.schedule(handlers.cache_changed)
        end
      end)
    end
  end

  function host.unsubscribe()
    pcall(vim.api.nvim_del_augroup_by_name, GROUP)
    if watcher then
      watcher:close()
      watcher = nil
    end
  end

  function host.notify(message, level)
    local levels = { warn = vim.log.levels.WARN, error = vim.log.levels.ERROR }
    vim.notify(PREFIX .. message, levels[level] or vim.log.levels.INFO)
  end

  function host.cache_read()
    local file = io.open(state_path(), "r")
    if not file then
      return nil
    end
    local text = file:read("*a")
    file:close()
    return text
  end

  --- Best effort, and atomic: another Neovim may be reading this file, and a
  --- lost cache only costs one first frame.
  function host.cache_write(text)
    local path = state_path()
    pcall(vim.fn.mkdir, vim.fs.dirname(path), "p")
    local temp = ("%s.%d"):format(path, vim.uv.os_getpid())
    local file = io.open(temp, "w")
    if not file then
      return
    end
    file:write(text)
    file:close()
    if not os.rename(temp, path) then
      os.remove(temp)
    end
  end

  --- Every highlight on the cursor, most specific first.
  function host.groups_under_cursor()
    local info = vim.inspect_pos()
    local names = {}
    for _, list in ipairs({ info.semantic_tokens, info.treesitter, info.syntax }) do
      for index = #list, 1, -1 do
        local item = list[index]
        names[#names + 1] = item.opts and item.opts.hl_group or item.hl_group
      end
    end
    return names
  end

  function host.colors_path(name)
    return vim.fs.joinpath(vim.fn.stdpath("config"), "colors", name .. ".lua")
  end

  function host.exists(path)
    return vim.uv.fs_stat(path) ~= nil
  end

  function host.write(path, text)
    pcall(vim.fn.mkdir, vim.fs.dirname(path), "p")
    local file, err = io.open(path, "w")
    if not file then
      return false, err
    end
    file:write(text)
    file:close()
    return true
  end

  return host
end

return M
