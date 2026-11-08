-- The Neovim host: the one module that touches the outside world. Each function
-- is a single effect and makes no decisions; those belong to App, where they can
-- be tested.
local Config = require("colorrex.config")

local M = {}

local LANDMARK_GROUP = "ColorRexLandmark"
local LANDMARK_PRIORITY = 130 -- above Treesitter and LSP tokens, below diagnostics
local MEANING_GROUP = "ColorRexFailure"
local MEANING_PRIORITY = 126 -- above Treesitter (100) and LSP tokens (125), so `err` stays failure
local MAX_WORD = 40 -- the lexicon never reads anything longer

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

  --- Whether a tmux sits between Neovim and the terminal. tmux sets this in every
  --- pane it runs, so it is right even over SSH, when tmux runs on the far side.
  function host.tmux()
    return (vim.env.TMUX or "") ~= ""
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
    on("FocusLost", handlers.blur)
    on("VimResume", handlers.resume)
    on("CursorHold", handlers.pause)
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

  --- Draw what the highlighter cannot: chunk landmarks, when asked for, and the
  --- meanings the lexicon adds, such as `nil` and `err` reading as failure. Marks are
  --- ephemeral, so nothing is stored in a buffer, and only the rows on screen are looked
  --- at. A buffer without Treesitter highlighting is left alone, and nothing here ever
  --- starts a parse: it reads the trees the highlighter already has.
  ---
  --- spec: landmarks(root, top, bottom, line) -> marks, or nil;
  ---       refine(capture, text, lang) -> meaning|nil; can_refine(capture) -> boolean.
  function host.decorate(spec)
    local namespace = vim.api.nvim_create_namespace(Config.NAME .. ".chunks")
    local queries = {}
    local function highlights(lang)
      if queries[lang] == nil then
        local ok, query = pcall(vim.treesitter.query.get, lang, "highlights")
        queries[lang] = ok and query or false
      end
      return queries[lang] or nil
    end
    local marks, broken = {}, {}
    local function add(row, mark)
      marks[row] = marks[row] or {}
      table.insert(marks[row], mark)
    end
    local function refine_tree(tstree, query, lang, buffer, top, bottom)
      for id, node in query:iter_captures(tstree:root(), buffer, top, bottom + 1) do
        local capture = "@" .. query.captures[id]
        if spec.can_refine(capture) then
          local start_row, start_col, end_row, end_col = node:range()
          if start_row == end_row and end_col - start_col <= MAX_WORD then
            local text = vim.treesitter.get_node_text(node, buffer)
            if spec.refine(capture, text, lang) then
              add(start_row, { start_col, end_row, end_col, MEANING_GROUP, MEANING_PRIORITY })
            end
          end
        end
      end
    end
    vim.api.nvim_set_decoration_provider(namespace, {
      on_win = function(_, _, buffer, top, bottom)
        local highlighter = vim.treesitter.highlighter.active[buffer]
        local _, tree = next(highlighter and highlighter.tree:trees() or {})
        if not tree then
          return false
        end
        marks = {}
        if spec.landmarks then
          local found = spec.landmarks(tree:root(), top, bottom, function(row)
            return vim.api.nvim_buf_get_lines(buffer, row, row + 1, false)[1]
          end)
          for row, mark in pairs(found) do
            add(row, { mark[1], mark[2], mark[3], LANDMARK_GROUP, LANDMARK_PRIORITY })
          end
        end
        if spec.refine then
          highlighter.tree:for_each_tree(function(tstree, ltree)
            local lang = ltree:lang()
            local query = tstree and highlights(lang)
            if not query or broken[lang] then
              return
            end
            -- Anything wrong here costs only the meanings this adds, for this language,
            -- once. It never reaches the redraw, which would repeat it on every frame.
            local ok = pcall(refine_tree, tstree, query, lang, buffer, top, bottom)
            if not ok then
              broken[lang] = true
            end
          end)
        end
        return next(marks) ~= nil
      end,

      on_line = function(_, _, buffer, row)
        for _, mark in ipairs(marks[row] or {}) do
          vim.api.nvim_buf_set_extmark(buffer, namespace, row, mark[1], {
            end_row = mark[2],
            end_col = mark[3],
            hl_group = mark[4],
            priority = mark[5],
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
