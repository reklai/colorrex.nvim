-- What Neovim's highlighter would paint on each word of some code, without a window.
--
-- It runs a language's highlights query, and colorrex's own meanings query if the
-- language has one, over a string, and keeps for each character the capture that wins
-- there: highest priority first, then the later pattern, as the highlighter decides.
-- Injected languages are left out: a snippet here is one language.
local M = {}

local DEFAULT_PRIORITY = 100
M.MEANINGS_PRIORITY = 126 -- what lua/colorrex/neovim.lua draws meanings at

local function winners(text, lang, query, priority, out)
  local parser = vim.treesitter.get_string_parser(text, lang)
  local tree = parser:parse()[1]
  for id, node, metadata, match in query:iter_captures(tree:root(), text, 0, -1) do
    local name = query.captures[id]
    if not name:match("^_") and name ~= "spell" and name ~= "nospell" and name ~= "conceal" then
      local rank = tonumber(metadata.priority or (metadata[id] and metadata[id].priority)) or priority
      local pattern = match and match:info() or 0
      local sr, sc, er, ec = node:range()
      if sr == er then -- words never span lines
        for col = sc, ec - 1 do
          local key = sr * 100000 + col
          local held = out[key]
          if not held or rank > held.rank or (rank == held.rank and pattern >= held.pattern) then
            out[key] = { capture = name, rank = rank, pattern = pattern }
          end
        end
      end
    end
  end
end

--- The capture that wins at each word, as { { text, capture, row, col } ... }.
--- Returns nil when this Neovim has no parser or highlights query for `lang`.
function M.words(text, lang)
  local ok, highlights = pcall(vim.treesitter.query.get, lang, "highlights")
  if not ok or not highlights or not pcall(vim.treesitter.language.add, lang) then
    return nil
  end
  local out = {}
  winners(text, lang, highlights, DEFAULT_PRIORITY, out)
  local has, meanings = pcall(vim.treesitter.query.get, lang, "colorrex")
  if has and meanings then
    winners(text, lang, meanings, M.MEANINGS_PRIORITY, out)
  end
  local words, row = {}, 0
  for line in (text .. "\n"):gmatch("(.-)\n") do
    for start, word in line:gmatch("()([%a_@'%?!:]?[%w_%?!']*)") do
      if #word > 0 and word:match("[%w_?!]") then
        local col = start - 1
        -- The first character of a word that is not punctuation decides it.
        local lead = word:find("[%w_]") or 1
        local held = out[row * 100000 + col + lead - 1]
        words[#words + 1] = { text = word, capture = held and held.capture or nil, row = row, col = col }
      end
    end
    row = row + 1
  end
  return words
end

return M
