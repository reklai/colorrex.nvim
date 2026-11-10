-- Servers: what a language server's tokens do to a reading.
--
-- test/support/servers.lua holds every token five real servers sent for the programs
-- in test/support/programs, with the capture Tree-sitter painted under each and the
-- nodes the lexicon reads there, so this runs with no servers. A word should read the
-- same with a server attached or without one, unless the server knows what the grammar
-- cannot (see meanings.lua, tier 3).
local Captures = require("captures")
local Meanings = require("colorrex.meanings")
local T = require("harness")

local SERVERS = require("servers")
local PLAIN = { name = true, quiet = true }
local INACTIVE = "inactive" -- code an `#if` turned off, which reads as a comment

--- What a token's word means without a server: what the lexicon adds, read as the host
--- reads it, else its capture's.
local function unserved(word, lang)
  local capture = word[2]
  if capture == "-" then
    return "name" -- painted nothing, so plain text
  end
  local added = Captures.added(word.nodes, lang, Meanings.refine)
  if added then
    return Meanings.ADDED[added], true
  end
  return Meanings.of_capture(capture) or capture
end

--- What it means once the server's token arrives. The lexicon draws above every
--- token, and a token type with no opinion leaves the grammar's meaning.
local function served(word, lang)
  local meaning, lexicon = unserved(word, lang)
  if lexicon then
    return meaning
  end
  local token = word[3]
  if token == Meanings.INACTIVE.token and Meanings.INACTIVE.langs[lang] then
    return INACTIVE
  end
  return Meanings.TOKENS[token] or meaning
end

local function each_token(visit)
  for lang, recorded in pairs(SERVERS) do
    for _, word in ipairs(recorded.words) do
      visit(lang, word[1], unserved(word, lang), served(word, lang), word)
    end
  end
end

T.test("servers: a server never makes a word plainer, nor takes failure away", function()
  local worse = {}
  each_token(function(lang, text, before, after, word)
    if before ~= after and after ~= INACTIVE and ((PLAIN[after] and not PLAIN[before]) or before == "failure") then
      worse[#worse + 1] = ("%s %s (%s, %s): %s -> %s"):format(lang, text, word[2], word[3], before, after)
    end
  end)
  T.eq(#worse, 0, table.concat(worse, "; "):sub(1, 600))
end)

T.test("servers: code an `#if` turned off reads as a comment", function()
  local inactive = 0
  each_token(function(lang, _, _, after)
    if after == INACTIVE then
      inactive = inactive + 1
      T.ok(Meanings.INACTIVE.langs[lang], lang)
    end
  end)
  T.ok(inactive > 0, "the C program has code an `#if` turns off")
end)

T.test("servers: attaching one changes a word only to correct it", function()
  local tokens, changed, kinds = 0, 0, {}
  each_token(function(_, _, before, after)
    tokens = tokens + 1
    if before ~= after and after ~= INACTIVE then
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
  -- Raised from 40 when the programs grew by 97 tokens, among them a called parameter in
  -- each: the four new changes are packages, a method inside a macro and a callable
  -- parameter, which only a server can know. It is still one token in 28.
  T.ok(changed <= 44, ("%d changes"):format(changed))
end)
