-- The Neovim host: the one module that touches the outside world. Each function
-- is a single effect and makes no decisions; those belong to App, where they can
-- be tested.
local Config = require("colorrex.config")

local M = {}

local LANDMARK_GROUP = "ColorRexLandmark"
local LANDMARK_PRIORITY = 130 -- above Treesitter and LSP tokens, below diagnostics
local MEANING_PRIORITY = 126 -- above Treesitter (100) and LSP tokens (125), so `err` stays failure
local CAPTURE_PRIORITY = 100 -- Treesitter's, unless a query sets its own
local UNDRAWN = { spell = true, nospell = true, conceal = true } -- captures Neovim reads but never paints
local MAX_WORD = 40 -- the lexicon never reads anything longer

function M.new()
  local host = {}
  local state_path = vim.fs.joinpath(vim.fn.stdpath("state"), Config.NAME, "theme")
  -- Each decorate and undecorate starts a new generation. Buffer listeners from an
  -- older one detach the next time they fire, so switching colorschemes leaks nothing.
  local generation = 0
  local watcher
  local drawn_at -- while decorating: the group the lexicon drew at a buffer position

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
  --- meanings the lexicon adds, such as `nil` and `err` reading as failure and `!` as
  --- negation. Marks are ephemeral, so nothing is stored in a buffer, and only the rows
  --- on screen are looked at. A buffer without Treesitter highlighting is left alone,
  --- and nothing here ever starts a parse: it reads the trees the highlighter already has.
  ---
  --- spec: landmarks(root, top, bottom, line) -> marks, or nil;
  ---       refine(capture, text, lang, parent, previous) -> group|nil;
  ---       can_refine(capture, lang) -> boolean.
  function host.decorate(spec)
    generation = generation + 1
    local mine = generation
    local namespace = vim.api.nvim_create_namespace(Config.NAME .. ".chunks")
    local queries = {}
    --- A language's highlights query, if any of its captures is one the lexicon reads.
    --- An injected `comment` or `regex` tree never is, and a Go file has one per comment.
    local function highlights(lang)
      if queries[lang] == nil then
        local ok, query = pcall(vim.treesitter.query.get, lang, "highlights")
        local useful = false
        for _, name in ipairs(ok and query and query.captures or {}) do
          useful = useful or spec.can_refine("@" .. name, lang)
        end
        queries[lang] = useful and query or false
      end
      return queries[lang] or nil
    end

    local broken = {} -- languages whose query failed here once; they lose only this
    -- The lexicon asks about a node's neighbors only for the few words that need it, such
    -- as `!`. One function each, pointed at the node being read, so asking costs nothing.
    local reading, reading_buffer
    local function parent_type()
      local parent = reading:parent()
      return parent and parent:type()
    end
    local function previous_text()
      local before = reading:prev_sibling()
      if not before then
        return nil
      end
      local start_row, start_col, end_row, end_col = before:range()
      if start_row ~= end_row or end_col - start_col > MAX_WORD then
        return nil -- longer than any word the lexicon knows
      end
      return vim.treesitter.get_node_text(before, reading_buffer)
    end
    --- The lexicon reads each word as it is drawn: by the one capture the highlighter
    --- paints on its node, the highest priority and of those the last read. `ErrLog` in
    --- `ErrLog("x")` is a variable to Go's query too, and drawn as the call it is.
    local function refine_row(tstree, query, lang, buffer, row, found)
      local drawn, order = {}, {}
      for id, node, metadata in query:iter_captures(tstree:root(), buffer, row, row + 1) do
        local name = query.captures[id]
        if name:sub(1, 1) ~= "_" and not UNDRAWN[name] then -- `@_name` is the query's own
          local start_row, start_col, end_row, end_col = node:range()
          if start_row == row and end_row == row and end_col - start_col <= MAX_WORD then
            local rank = tonumber(metadata.priority or (metadata[id] and metadata[id].priority)) or CAPTURE_PRIORITY
            local key = node:id()
            local held = drawn[key]
            if not held then
              order[#order + 1] = key
              drawn[key] = { node = node, name = name, rank = rank }
            elseif rank >= held.rank then
              held.name, held.rank = name, rank
            end
          end
        end
      end
      reading_buffer = buffer
      for _, key in ipairs(order) do
        local held = drawn[key]
        local capture = "@" .. held.name
        if spec.can_refine(capture, lang) then
          reading = held.node
          local group = spec.refine(capture, vim.treesitter.get_node_text(held.node, buffer), lang, parent_type, previous_text)
          if group then
            local _, start_col, _, end_col = held.node:range()
            found[#found + 1] = { start_col, row, end_col, group, MEANING_PRIORITY }
          end
        end
      end
    end

    -- What the lexicon found on each row, read as the row is drawn and kept until that
    -- row changes. Two signals say which rows did, the same two Neovim's highlighter
    -- uses: an edit's bytes, and the ranges whose syntax the parser says changed, as
    -- when an opened string turns the lines below it into string. So scrolling reads
    -- only rows coming into view, and typing only the line being typed on.
    local meanings = {} -- buffer -> { highlighter, rows = { [row] = marks } }
    --- Forget rows first..last, or every row from first on. A short range clears just
    --- its rows: on each keystroke in a comment, Neovim reports every comment tree in
    --- the file, and each is a line or two.
    local function forget(known, first, last)
      if last and last - first < 256 then
        for row = first, last do
          known.rows[row] = nil
        end
        return
      end
      for row in pairs(known.rows) do
        if row >= first and (not last or row <= last) then
          known.rows[row] = nil
        end
      end
    end
    local function watch(buffer, highlighter)
      local known = { highlighter = highlighter, rows = {} }
      meanings[buffer] = known
      vim.api.nvim_buf_attach(buffer, false, {
        on_bytes = function(_, _, _, start_row, _, _, old_end_row, _, _, new_end_row)
          if generation ~= mine or meanings[buffer] ~= known then
            return true -- replaced or undecorated: stop listening
          end
          -- An edit within its lines forgets those lines; one that adds or removes
          -- lines moves every row below it, so those go too.
          forget(known, start_row, old_end_row == new_end_row and start_row + new_end_row or nil)
        end,
        on_detach = function()
          if meanings[buffer] == known then
            meanings[buffer] = nil
          end
        end,
      })
      highlighter.tree:register_cbs({
        on_changedtree = function(ranges, tree)
          if generation ~= mine or meanings[buffer] ~= known then
            return -- a tree's callbacks cannot be removed, so an old one only returns
          end
          -- Node ranges: start row first, end row fourth. A new tree's first report
          -- runs to the end of the file; it can only have changed its own rows.
          local _, _, tree_end = tree and tree:root():range()
          for _, range in ipairs(ranges) do
            local last = range[4]
            if last == 2 ^ 32 - 1 then
              last = tree_end
            end
            forget(known, range[1], last)
          end
        end,
      }, true)
      return known
    end
    --- The trees on screen whose language the lexicon can read, once per window
    --- drawn. A Go file has a tree per comment, and only these few are worth a look.
    local function trees_on(highlighter, top, bottom)
      local out = {}
      highlighter.tree:for_each_tree(function(tstree, ltree)
        if tstree then
          local root_start, _, root_end = tstree:root():range()
          local lang = ltree:lang()
          local query = root_end >= top and root_start <= bottom and highlights(lang)
          if query then
            out[#out + 1] = { tree = tstree, lang = lang, query = query, first = root_start, last = root_end }
          end
        end
      end)
      return out
    end
    local function read_row(buffer, trees, row)
      local found = {}
      for _, entry in ipairs(trees) do
        if row >= entry.first and row <= entry.last and not broken[entry.lang] then
          -- Anything wrong here costs only the meanings this adds, for this language,
          -- once. It never reaches the redraw, which would repeat it on every frame.
          if not pcall(refine_row, entry.tree, entry.query, entry.lang, buffer, row, found) then
            broken[entry.lang] = true
          end
        end
      end
      return found
    end

    -- A row nobody has read yet is not read while Neovim draws: that would put the
    -- lexicon's work on the keystroke's own frame. It is drawn as the highlighter
    -- painted it, and read right after the frame, and only those rows are drawn again.
    -- So a keystroke costs what the highlighter costs, and a burst of typing is read
    -- once, not once per key.
    local pending = {} -- buffer -> { rows = { [row] = true }, trees, highlighter }
    local scheduled = false
    local function read_pending()
      scheduled = false
      for buffer, wanted in pairs(pending) do
        pending[buffer] = nil
        local known = meanings[buffer]
        if known and vim.api.nvim_buf_is_valid(buffer) and known.highlighter == wanted.highlighter then
          local first, last
          for row in pairs(wanted.rows) do
            if not known.rows[row] then
              known.rows[row] = read_row(buffer, wanted.trees, row)
              first, last = math.min(first or row, row), math.max(last or row, row)
            end
          end
          if first then
            pcall(vim.api.nvim__redraw, { buf = buffer, range = { first, last + 1 }, flush = false })
          end
        end
      end
    end
    local function meanings_on(buffer, highlighter, trees, row)
      local known = meanings[buffer]
      if not known or known.highlighter ~= highlighter then
        known = watch(buffer, highlighter)
      end
      local found = known.rows[row]
      if found then
        return found
      end
      local wanted = pending[buffer]
      if not wanted or wanted.highlighter ~= highlighter then
        wanted = { rows = {}, trees = trees, highlighter = highlighter }
        pending[buffer] = wanted
      end
      wanted.rows[row], wanted.trees = true, trees
      if not scheduled then
        scheduled = true
        vim.schedule(read_pending)
      end
      return {}
    end
    drawn_at = function(buffer, row, col)
      local known = meanings[buffer]
      for _, mark in ipairs(known and known.rows[row] or {}) do
        if col >= mark[1] and col < mark[3] then
          return mark[4]
        end
      end
      return nil
    end

    local landmarks, current, visible = {}, nil, {}
    local function draw(buffer, row, mark)
      vim.api.nvim_buf_set_extmark(buffer, namespace, row, mark[1], {
        end_row = mark[2],
        end_col = mark[3],
        hl_group = mark[4],
        priority = mark[5],
        ephemeral = true,
        strict = false,
      })
    end
    vim.api.nvim_set_decoration_provider(namespace, {
      on_win = function(_, _, buffer, top, bottom)
        local highlighter = vim.treesitter.highlighter.active[buffer]
        local _, tree = next(highlighter and highlighter.tree:trees() or {})
        if not tree then
          return false
        end
        current, landmarks = highlighter, {}
        visible = spec.refine and trees_on(highlighter, top, bottom) or {}
        if spec.landmarks then
          landmarks = spec.landmarks(tree:root(), top, bottom, function(row)
            return vim.api.nvim_buf_get_lines(buffer, row, row + 1, false)[1]
          end)
        end
        return spec.refine ~= nil or next(landmarks) ~= nil
      end,
      on_line = function(_, _, buffer, row)
        local mark = landmarks[row]
        if mark then
          draw(buffer, row, { mark[1], mark[2], mark[3], LANDMARK_GROUP, LANDMARK_PRIORITY })
        end
        if spec.refine and current then
          for _, found in ipairs(meanings_on(buffer, current, visible, row)) do
            draw(buffer, row, found)
          end
        end
      end,
    })
  end

  function host.undecorate()
    generation = generation + 1
    drawn_at = nil
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

  --- Every highlight on the cursor, most specific first. What the lexicon drew comes
  --- first: it sits above every server's token, and Neovim's own inspector cannot see it.
  function host.groups_under_cursor()
    local info = vim.inspect_pos()
    local names = {}
    local cursor = vim.api.nvim_win_get_cursor(0)
    local added = drawn_at and drawn_at(vim.api.nvim_get_current_buf(), cursor[1] - 1, cursor[2])
    if added then
      names[1] = added
    end
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
