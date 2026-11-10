-- What Neovim's highlighter would paint on each word of some code, without a window.
--
-- It runs a language's highlights query, and colorrex's own meanings query if the
-- language has one, over a string, and keeps for each character the capture that wins
-- there: highest priority first, then the one read last, as the highlighter decides.
-- Injected languages are left out: a snippet here is one language.
local M = {}

M.DEFAULT_PRIORITY = 100
M.MEANINGS_PRIORITY = 126 -- what lua/colorrex/neovim.lua draws meanings at

--- Record in `out`, keyed by row * 100000 + col, the capture that wins each character.
--- At equal priority the highlighter draws captures in the order it reads them, so the
--- later one wins: the order of reading breaks the tie.
function M.winners(text, lang, query, priority, out)
  local parser = vim.treesitter.get_string_parser(text, lang)
  local tree = parser:parse()[1]
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
            -- The node's own text and its parent, which the lexicon reads as the host does.
            local parent = node:parent()
            out[key] = {
              capture = name, rank = rank, read = out.read,
              node_text = vim.treesitter.get_node_text(node, text), parent = parent and parent:type(),
            }
          end
        end
      end
    end
  end
end

--- The capture that wins at each word, as { { text, capture, row, col, node_text,
--- parent } ... }: the winning node's own text, and its parent's type.
--- Returns nil when this Neovim has no parser or highlights query for `lang`.
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
        local lead = word:find("[%w_]") or 1
        local held = out[row * 100000 + col + lead - 1]
        words[#words + 1] = {
          text = word, capture = held and held.capture or nil, row = row, col = col,
          node_text = held and held.node_text, parent = held and held.parent,
        }
      end
    end
    row = row + 1
  end
  return words
end

return M
