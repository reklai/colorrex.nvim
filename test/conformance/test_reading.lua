-- Reading: how real code looks in every theme, in every language.
--
-- The promises are checked on a palette elsewhere; this checks them where they are
-- meant to hold, on code. test/support/reading.lua holds snippets in 21 languages as
-- the highlighter and the lexicon see them, so this runs with no parsers, on every
-- theme in the corpus.
local Color = require("colorrex.color")
local Compiler = require("colorrex.compiler")
local Config = require("colorrex.config")
local Meanings = require("colorrex.meanings")
local T = require("harness")
local Theme = require("colorrex.theme")

local CORPUS = os.getenv("COLORREX_THEMES") or "/usr/share/ghostty/themes"
local READING = require("reading")
local OPTS = Config.resolve()

-- Lowered by hand as the compiler improves. Raising one means code reads worse.
--
-- Raised once, on purpose, from 0.0050 and 0.0050/0.0051, when the samples grew to read
-- every capture colorrex colors: the old compiler read 0.82% on them. The rest is fields
-- read beside the values they hold. Ruby's `{ retries: 3 }` and Elixir's `message: "bad"`
-- now read as the fields they are, as `{ retries: 3 }` does in JavaScript, and in about
-- one theme in five a field sits near a value's color. In return nothing but failure
-- wears failure's color in any theme, where 278 had something else in it.
--
-- Raised again, from 0.0098 and 0.0101/0.0087, when the samples came to be read as the
-- host reads them. Ruby's `mode: :fast` had been read as two keys, though the host draws
-- `:fast` as the value it is; with that one word read right the old limits fail on the
-- same compiler, so nothing reads worse than it did.
local LOOK_ALIKE_LIMIT = 0.0101 -- neighbors that mean different things but look the same
local LOOK_ALIKE_BY_SIDE = { dark = 0.0104, light = 0.0090 } -- each mode on its own, so neither hides in the other

local function corpus()
  local themes = {}
  local listing = io.popen(('ls "%s" 2>/dev/null'):format(CORPUS))
  for name in listing:lines() do
    local file = io.open(CORPUS .. "/" .. name)
    if file then
      local theme = Theme.parse(file:read("*a"))
      file:close()
      if Theme.completeness(theme) == "full" then
        themes[name] = theme
      end
    end
  end
  listing:close()
  return themes
end

--- The group colorrex defines for a capture, as Neovim finds it: @a.b.lang, then
--- @a.b, then @a, following links. A meaning the lexicon added draws over it.
local function look(compiled, capture, lang, added)
  if added then
    local group = Meanings.GROUP[added] -- what the lexicon adds, as the host draws it
    local spec = compiled.group_specs[group]
    return compiled.groups[group].fg, spec, spec.fg
  end
  local specs = compiled.group_specs
  local name = capture ~= "-" and (capture .. "." .. lang) or nil
  while name and not specs[name] do
    name = name:match("^(.+)%.[^.]+$")
  end
  local spec = name and specs[name] or { fg = "fg" }
  for _ = 1, 10 do
    if not spec.link then
      break
    end
    spec = specs[spec.link] or { fg = "fg" }
  end
  local role = spec.fg or "fg"
  return compiled.roles[role].hex, spec, role
end

local function same_look(a, b)
  return Color.distance(a.hex, b.hex) < Color.DISTINCT and not a.spec.bold == not b.spec.bold
    and not a.spec.italic == not b.spec.italic and not a.spec.underline == not b.spec.underline
end

local function each_word(compiled, visit)
  for lang, rows in pairs(READING) do
    for _, row in ipairs(rows) do
      local previous
      for _, word in ipairs(row) do
        local hex, spec, role = look(compiled, word[2], lang, word[3])
        local current = { text = word[1], hex = hex, spec = spec, role = role, failure = word[3] == "failure", lang = lang }
        visit(current, previous)
        previous = current
      end
    end
  end
end

-- Captures the samples cannot hold, and why. Everything else colorrex colors as code
-- is read in at least one of them, so no capture's color goes unchecked.
local UNREAD = {
  ["@comment.error"] = "the comment parser's, which no sample injects",
  ["@comment.warning"] = "the comment parser's",
  ["@comment.note"] = "the comment parser's",
  ["@comment.todo"] = "the comment parser's",
  ["@string.special.url"] = "a link, not code",
  ["@punctuation.delimiter"] = "punctuation is never a word",
  ["@punctuation.special"] = "punctuation is never a word",
  ["@tag.delimiter"] = "punctuation is never a word",
  ["@variable.parameter.builtin"] = "Lua's `...`, never a word",
}

T.test("reading: every capture colored as code is read in some sample", function()
  local read = {}
  for _, rows in pairs(READING) do
    for _, row in ipairs(rows) do
      for _, word in ipairs(row) do
        read[word[2]] = true
      end
    end
  end
  local unread = {}
  for name in pairs(Compiler.compile(require("fixtures").theme(), OPTS).group_specs) do
    local code = name:match("^@") and not name:match("^@markup") and not name:match("^@diff") and not name:match("^@lsp")
    if code and not read[name] and not UNREAD[name] then
      unread[#unread + 1] = name
    end
  end
  table.sort(unread)
  T.eq(#unread, 0, "no sample reads " .. table.concat(unread, ", "))
end)

T.test("reading: nothing but failure is drawn in failure's color, in any theme or language", function()
  local themes = corpus()
  if next(themes) == nil then
    T.skip("no theme corpus at " .. CORPUS)
  end
  -- Judged by the whole look, color, weight, slant and underline: a palette of one hue
  -- can only tell them apart by style, and does.
  local strays = {}
  for name, theme in pairs(themes) do
    local compiled = Compiler.compile(theme, OPTS)
    local failure = { hex = compiled.roles.failure.hex, spec = compiled.groups.ColorRexFailure }
    each_word(compiled, function(word)
      if not word.failure and word.role ~= "failure" and same_look(word, failure) then
        strays[#strays + 1] = ("%s: %s %s (%s)"):format(name, word.lang, word.text, word.role)
      end
    end)
  end
  T.eq(#strays, 0, table.concat(strays, "; "):sub(1, 600))
end)

T.test("reading: failure is one color in every language", function()
  local compiled = Compiler.compile(next(corpus()) and select(2, next(corpus())) or require("fixtures").theme(), OPTS)
  local colors = {}
  each_word(compiled, function(word)
    if word.failure or word.role == "failure" then
      colors[word.hex] = (colors[word.hex] or 0) + 1
    end
  end)
  local count = 0
  for _ in pairs(colors) do
    count = count + 1
  end
  T.eq(count, 1)
end)

T.test("reading: words side by side that mean different things look different", function()
  local themes = corpus()
  if next(themes) == nil then
    T.skip("no theme corpus at " .. CORPUS)
  end
  local pairs_seen, alike = 0, 0
  for _, theme in pairs(themes) do
    local compiled = Compiler.compile(theme, OPTS)
    each_word(compiled, function(word, previous)
      if previous and previous.role ~= word.role then
        pairs_seen = pairs_seen + 1
        alike = alike + (same_look(previous, word) and 1 or 0)
      end
    end)
  end
  local share = alike / pairs_seen
  print(("  reading: %.2f%% of %d neighbor pairs look alike"):format(share * 100, pairs_seen))
  T.ok(share <= LOOK_ALIKE_LIMIT, ("%.4f"):format(share))
end)

T.test("reading: light themes read as well as dark ones, word by word", function()
  local themes = corpus()
  if next(themes) == nil then
    T.skip("no theme corpus at " .. CORPUS)
  end
  local seen, alike = { light = 0, dark = 0 }, { light = 0, dark = 0 }
  for _, theme in pairs(themes) do
    local compiled = Compiler.compile(theme, OPTS)
    local side = compiled.background
    each_word(compiled, function(word, previous)
      if previous and previous.role ~= word.role then
        seen[side] = seen[side] + 1
        alike[side] = alike[side] + (same_look(previous, word) and 1 or 0)
      end
    end)
  end
  for _, side in ipairs({ "dark", "light" }) do
    local share = alike[side] / seen[side]
    print(("  reading, %s themes: %.2f%% look alike"):format(side, share * 100))
    T.ok(share <= LOOK_ALIKE_BY_SIDE[side], ("%s %.5f"):format(side, share))
  end
end)

T.test("reading: comments sit below the code they annotate, in light themes as in dark", function()
  -- A strong grey on white reads louder than colors that had to darken to be read,
  -- so in half of all light themes bright black outshouted the code.
  local themes = corpus()
  if next(themes) == nil then
    T.skip("no theme corpus at " .. CORPUS)
  end
  local LIMIT = { dark = 1, light = 0 } -- lowered by hand; from 169 and 95, then 35 and 13
  local loud = { dark = 0, light = 0 }
  for _, theme in pairs(themes) do
    local compiled = Compiler.compile(theme, OPTS)
    local bg, values = compiled.filled.bg, {}
    for _, name in ipairs({ "keyword", "func", "string", "type", "failure", "operator" }) do
      values[#values + 1] = Color.contrast(compiled.roles[name].hex, bg)
    end
    table.sort(values)
    if Color.contrast(compiled.roles.comment.hex, bg) >= values[3] then
      loud[compiled.background] = loud[compiled.background] + 1
    end
  end
  for _, side in ipairs({ "dark", "light" }) do
    print(("  %s themes with comments as loud as code: %d"):format(side, loud[side]))
    T.ok(loud[side] <= LIMIT[side], ("%s: %d themes"):format(side, loud[side]))
  end
end)
