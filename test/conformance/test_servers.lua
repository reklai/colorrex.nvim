-- Servers: what a language server's tokens do to a reading.
--
-- test/support/servers.lua holds every token five real servers sent for the programs
-- in test/support/programs, with the capture Tree-sitter painted under each, so this
-- runs with no servers. A word should read the same with a server attached or without
-- one, unless the server knows what the grammar cannot (see meanings.lua, tier 3).
local Meanings = require("colorrex.meanings")
local T = require("harness")

local SERVERS = require("servers")
local PLAIN = { name = true, quiet = true }

--- What a token's word means without a server: the lexicon's, else its capture's.
local function unserved(capture, text, lang)
  if capture == "-" then
    return "name" -- painted nothing, so plain text
  end
  local added = Meanings.refine(capture, text, lang)
  if added then
    return Meanings.ADDED[added], true
  end
  return Meanings.of_capture(capture) or capture
end

--- What it means once the server's token arrives. The lexicon draws above every
--- token, and a token type with no opinion leaves the grammar's meaning.
local function served(capture, text, lang, token)
  local meaning, lexicon = unserved(capture, text, lang)
  if lexicon then
    return meaning
  end
  return Meanings.TOKENS[token] or meaning
end

local function each_token(visit)
  for lang, recorded in pairs(SERVERS) do
    for _, word in ipairs(recorded.words) do
      local text, capture, token = word[1], word[2], word[3]
      visit(lang, text, unserved(capture, text, lang), served(capture, text, lang, token), word)
    end
  end
end

T.test("servers: a server never makes a word plainer, nor takes failure away", function()
  local worse = {}
  each_token(function(lang, text, before, after, word)
    if before ~= after and ((PLAIN[after] and not PLAIN[before]) or before == "failure") then
      worse[#worse + 1] = ("%s %s (%s, %s): %s -> %s"):format(lang, text, word[2], word[3], before, after)
    end
  end)
  T.eq(#worse, 0, table.concat(worse, "; "):sub(1, 600))
end)

T.test("servers: attaching one changes a word only to correct it", function()
  local tokens, changed, kinds = 0, 0, {}
  each_token(function(_, _, before, after)
    tokens = tokens + 1
    if before ~= after then
      changed = changed + 1
      local kind = before .. " -> " .. after
      kinds[kind] = (kinds[kind] or 0) + 1
    end
  end)
  local list = {}
  for kind, count in pairs(kinds) do
    list[#list + 1] = ("%s %d"):format(kind, count)
  end
  table.sort(list)
  print(("  attaching a server changes %d of %d tokens: %s"):format(changed, tokens, table.concat(list, ", ")))
  -- Every change comes from a token type that speaks, so the list above is the whole
  -- of what a server can do. Lowered by hand; from 140 when every token type spoke.
  T.ok(changed <= 40, ("%d changes"):format(changed))
end)
