-- The Neovim host: the one module that touches the outside world. Each function
-- is a single effect and makes no decisions; those belong to App, where they can
-- be tested.
local Config = require("colorrex.config")

local M = {}

local LANDMARK_GROUP = "ColorRexLandmark"
local LANDMARK_PRIORITY = 130 -- above Treesitter and LSP tokens, below diagnostics

function M.new()
  local host = {}
  local state_path = vim.fs.joinpath(vim.fn.stdpath("state"), Config.NAME, "theme")
  local watcher

  --- Whether a terminal is there to ask. Until VimEnter a query could race startup.
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
    vim.cmd.highlight("clear") -- this also unsets g:colors_name
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
      vim.g["terminal_color_" .. slot] = colorscheme.filled.ansi[slot]
    end
  end

  function host.apply()
    vim.cmd.colorscheme(Config.NAME)
  end

  function host.subscribe(handlers)
    local group = vim.api.nvim_create_augroup(Config.NAME, { clear = true })
    local function on(event, handler)
      vim.api.nvim_create_autocmd(event, {
        group = group,
        callback = function(ev)
          handler(ev) -- a truthy return would delete the autocommand
        end,
      })
    end
    on("TermResponse", function(ev)
      handlers.response(ev.data.sequence)
    end)
    on("FocusGained", handlers.focus)
    on("VimResume", handlers.resume)
    on("UIEnter", handlers.ui_enter)
    on("VimLeavePre", handlers.leaving)
    on("ColorScheme", function(ev)
      handlers.colorscheme_changed(ev.match)
    end)
    -- Best effort, like the file it watches: without it, a Neovim just waits for its
    -- own focus event or sync. It is event-driven, so it costs nothing idle.
    local directory = vim.fs.dirname(state_path)
    pcall(vim.fn.mkdir, directory, "p")
    watcher = vim.uv.new_fs_event()
    if watcher then
      watcher:start(directory, {}, function(err, name)
        if not err and name == vim.fs.basename(state_path) then
          vim.schedule(handlers.theme_saved)
        end
      end)
    end
  end

  function host.unsubscribe()
    pcall(vim.api.nvim_del_augroup_by_name, Config.NAME)
    if watcher then
      watcher:close()
      watcher = nil
    end
  end

  --- Draw landmarks on every window as it redraws. Marks are ephemeral, so nothing is
  --- stored in a buffer, and only the rows on screen are looked at. A buffer without
  --- Treesitter highlighting is left alone, and nothing here ever starts a parse.
  function host.decorate(landmarks)
    local namespace = vim.api.nvim_create_namespace(Config.NAME .. ".chunks")
    local marks = {}
    vim.api.nvim_set_decoration_provider(namespace, {
      on_win = function(_, _, buffer, top, bottom)
        local highlighter = vim.treesitter.highlighter.active[buffer]
        local _, tree = next(highlighter and highlighter.tree:trees() or {})
        if not tree then
          return false
        end
        marks = landmarks(tree:root(), top, bottom, function(row)
          return vim.api.nvim_buf_get_lines(buffer, row, row + 1, false)[1]
        end)
        return next(marks) ~= nil
      end,
      on_line = function(_, _, buffer, row)
        local mark = marks[row]
        if mark then
          vim.api.nvim_buf_set_extmark(buffer, namespace, row, mark[1], {
            end_row = mark[2],
            end_col = mark[3],
            hl_group = LANDMARK_GROUP,
            priority = LANDMARK_PRIORITY,
            ephemeral = true,
            strict = false,
          })
        end
      end,
    })
  end

  function host.undecorate()
    vim.api.nvim_set_decoration_provider(vim.api.nvim_create_namespace(Config.NAME .. ".chunks"), {})
  end

  function host.notify(message, level)
    local levels = { warn = vim.log.levels.WARN, error = vim.log.levels.ERROR }
    vim.notify(Config.NAME .. ": " .. message, levels[level] or vim.log.levels.INFO)
  end

  function host.saved_theme()
    local file = io.open(state_path, "r")
    if not file then
      return nil
    end
    local text = file:read("*a")
    file:close()
    return text
  end

  --- Best effort, and atomic: another Neovim may be reading this file, and losing
  --- it only costs one first frame.
  function host.save_theme(text)
    pcall(vim.fn.mkdir, vim.fs.dirname(state_path), "p")
    local temp = ("%s.%d"):format(state_path, vim.uv.os_getpid())
    local file = io.open(temp, "w")
    if not file then
      return
    end
    file:write(text)
    file:close()
    if not os.rename(temp, state_path) then
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
        names[#names + 1] = item.hl_group_link -- a syntax file's own name links to ours
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
