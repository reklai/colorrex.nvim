-- What Neovim's highlighter would paint on each word of some code, without a window.
--
-- It runs a language's highlights query, and colorrex's own meanings query if the
-- language has one, over a string, and keeps for each character the capture that wins
-- there: highest priority first, then the one read last, as the highlighter decides.
-- It also keeps the nodes under each character, each with the one capture drawn on it,
-- which is what the lexicon reads (see lua/colorrex/neovim.lua). Injected languages
-- are left out: a snippet here is one language.
local M = {}

M.DEFAULT_PRIORITY = 100
M.MEANINGS_PRIORITY = 126 -- what lua/colorrex/neovim.lua draws meanings at

local MAX_WORD = 40 -- the host reads no longer node

--- Record in `out`, keyed by row * 100000 + col, the capture that wins each character,
--- and in `out.nodes`, by the same key, the nodes under it as { capture, text, parent,
--- previous }, outermost first. At equal priority the highlighter draws captures in the
--- order it reads them, so the later one wins: the order of reading breaks the tie.
function M.winners(text, lang, query, priority, out)
  local parser = vim.treesitter.get_string_parser(text, lang)
  local tree = parser:parse()[1]
  local drawn, order = {}, {}
  out.nodes = out.nodes or {}
  for id, node, metadata in query:iter_captures(tree:root(), text, 0, -1) do
    local name = query.captures[id]
    if not name:match("^_") and name ~= "spell" and name ~= "nospell" and name ~= "conceal" then
      local rank = tonumber(metadata.priority or (metadata[id] and metadata[id].priority)) or priority
      out.read = (out.read or 0) + 1
      local sr, sc, er, ec = node:range()
      if sr == er then -- words never span lines
        for col = sc, ec - 1 do
          local key = sr * 100000 + col
          local held = out[key]
          if not held or rank > held.rank or (rank == held.rank and out.read >= held.read) then
            out[key] = { capture = name, rank = rank, read = out.read }
          end
        end
        if ec - sc <= MAX_WORD then
          local held = drawn[node:id()]
          if not held then
            local parent, before = node:parent(), node:prev_sibling()
            local br, bc, ber, bec
            if before then
              br, bc, ber, bec = before:range()
            end
            held = {
              node_text = vim.treesitter.get_node_text(node, text), parent = parent and parent:type(),
              -- Only what the lexicon could read: one line, a word long.
              previous = before and br == ber and bec - bc <= MAX_WORD and vim.treesitter.get_node_text(before, text) or nil,
              row = sr, first = sc, last = ec - 1,
            }
            drawn[node:id()] = held
            order[#order + 1] = held
          end
          if not held.rank or rank >= held.rank then
            held.capture, held.rank = name, rank
          end
        end
      end
    end
  end
  out.list = out.list or {}
  for _, held in ipairs(order) do
    table.insert(out.list, held)
    for col = held.first, held.last do
      local key = held.row * 100000 + col
      out.nodes[key] = out.nodes[key] or {}
      table.insert(out.nodes[key], {
        capture = held.capture, node_text = held.node_text, parent = held.parent, previous = held.previous,
      })
    end
  end
end

--- The capture that wins at each word, as { { text, capture, row, col, nodes } ... }:
--- `nodes` are the ones under its first character that is not punctuation, as
--- winners() keeps them. Returns nil when this Neovim has no parser or highlights
--- query for `lang`.
function M.words(text, lang)
  local ok, highlights = pcall(vim.treesitter.query.get, lang, "highlights")
  if not ok or not highlights or not pcall(vim.treesitter.language.add, lang) then
    return nil
  end
  local out = {}
  M.winners(text, lang, highlights, M.DEFAULT_PRIORITY, out)
  local has, meanings = pcall(vim.treesitter.query.get, lang, "colorrex")
  if has and meanings then
    M.winners(text, lang, meanings, M.MEANINGS_PRIORITY, out)
  end
  local words, row = {}, 0
  for line in (text .. "\n"):gmatch("(.-)\n") do
    for start, word in line:gmatch("()([%a_@'%?!:]?[%w_%?!']*)") do
      if #word > 0 and word:match("[%w_?!]") then
        local col = start - 1
        -- The first character of a word that is not punctuation decides it.
        local key = row * 100000 + col + (word:find("[%w_]") or 1) - 1
        local held = out[key]
        words[#words + 1] = {
          text = word, capture = held and held.capture or nil, row = row, col = col, nodes = out.nodes[key] or {},
        }
      end
    end
    row = row + 1
  end
  return words
end

--- Every node the highlighter draws on, in reading order, as { capture, node_text,
--- parent, previous, row, first, last }, each with the one capture drawn on it. Nil
--- without a parser and highlights query for `lang`.
function M.nodes(text, lang)
  local ok, highlights = pcall(vim.treesitter.query.get, lang, "highlights")
  if not ok or not highlights or not pcall(vim.treesitter.language.add, lang) then
    return nil
  end
  local out = {}
  M.winners(text, lang, highlights, M.DEFAULT_PRIORITY, out)
  return out.list
end

--- What the lexicon adds to a word, as the host draws it: each node under it is read by
--- its own drawn capture, and a mark drawn later lies over one drawn before. `refine`
--- is Meanings.refine.
function M.added(nodes, lang, refine)
  local found
  for _, node in ipairs(nodes) do
    found = refine("@" .. node.capture, node.node_text, lang, function()
      return node.parent
    end, function()
      return node.previous
    end) or found
  end
  return found
end

return M
