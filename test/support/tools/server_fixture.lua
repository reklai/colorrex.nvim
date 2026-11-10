-- Regenerates test/support/servers.lua: every semantic token a language server sends
-- for the programs in test/support/programs, with its type and modifiers and the
-- capture the highlighter would paint under it, so tests can ask what a server's
-- tokens would do to a reading without starting one.
--
--   COLORREX_PARSERS=<parser site> COLORREX_QUERIES=<queries runtime> \
--   COLORREX_RUST_SRC=<rust-src library, if rustc has none> \
--     nvim --headless --clean -l test/support/tools/server_fixture.lua
--
-- Servers come from PATH, else Mason. A language whose server or parser is missing
-- is left out, and says so. Nothing here applies the colorscheme: these are the
-- servers' own tokens, decoded with their own legends. Rows and columns are 0-based
-- bytes, as in captures.lua.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h:h")
package.path = root .. "/test/support/?.lua;" .. root .. "/lua/?.lua;" .. package.path
for _, path in ipairs({ vim.env.COLORREX_PARSERS, vim.env.COLORREX_QUERIES }) do
  if path and path ~= "" then
    vim.opt.runtimepath:prepend(path)
  end
end
vim.o.swapfile = false
vim.lsp.log.set_level(vim.log.levels.OFF)
local Captures = require("captures")

local MASON = vim.fn.expand("~/.local/share/nvim/mason/bin")
local RUST_SRC = (vim.env.COLORREX_RUST_SRC or "") ~= "" and vim.env.COLORREX_RUST_SRC or nil
local RUST = { ["rust-analyzer"] = { cargo = { sysrootSrc = RUST_SRC } } }

-- Each server, the project around its program, and how long its tokens must hold
-- still before they count: rust-analyzer keeps refining them while it indexes.
local SERVERS = {
  c = { bin = "clangd", main = "main.c", files = { ["compile_flags.txt"] = { "-std=c11" } } },
  go = {
    bin = "gopls", main = "main.go", files = { ["go.mod"] = { "module example.com/program", "", "go 1.22" } },
    settings = { gopls = { semanticTokens = true } }, -- gopls sends none unless asked
  },
  lua = { bin = "lua-language-server", main = "main.lua" },
  rust = {
    bin = "rust-analyzer", main = "src/main.rs", settle = 15000, timeout = 300000,
    files = { ["Cargo.toml"] = { "[package]", 'name = "program"', 'version = "0.1.0"', 'edition = "2021"' } },
    settings = RUST, init_options = RUST["rust-analyzer"],
  },
  typescript = {
    bin = "typescript-language-server", args = { "--stdio" }, main = "main.ts",
    files = {
      ["tsconfig.json"] = {
        '{ "compilerOptions": { "target": "ES2022", "module": "ES2022", "lib": ["ES2022", "DOM"],',
        '  "strict": true, "noEmit": true } }',
      },
    },
  },
}

-- One rule for which capture wins, shared with captures.lua, so both fixtures agree;
-- every word it reads is checked against it here.
local winners, DEFAULT_PRIORITY = Captures.winners, Captures.DEFAULT_PRIORITY

--- The capture that wins at each character, keyed as captures.lua keys them, or nil
--- without a parser and highlights query for `lang`.
local function painted(text, lang)
  local ok, highlights = pcall(vim.treesitter.query.get, lang, "highlights")
  if not ok or not highlights or not pcall(vim.treesitter.language.add, lang) then
    return nil
  end
  local out = {}
  winners(text, lang, highlights, DEFAULT_PRIORITY, out)
  local has, meanings = pcall(vim.treesitter.query.get, lang, "colorrex")
  if has and meanings then
    winners(text, lang, meanings, Captures.MEANINGS_PRIORITY, out)
  end
  for _, word in ipairs(Captures.words(text, lang)) do
    local held = out[word.row * 100000 + word.col + (word.text:find("[%w_]") or 1) - 1]
    assert((held and held.capture) == word.capture, ("%s %q: captures.lua reads it differently"):format(lang, word.text))
  end
  return out
end

--- A token's capture, decided as captures.lua decides a word's: at its first word
--- character, or its first character when it is all punctuation, like lua-ls's `:`.
local function capture_of(paint, text, row, col)
  local held = paint[row * 100000 + col + (text:find("[%w_]") or 1) - 1]
  return held and ("@" .. held.capture) or "-"
end

local function executable(bin)
  local found = vim.fn.exepath(bin)
  if found ~= "" then
    return found
  end
  local mason = MASON .. "/" .. bin
  return vim.fn.executable(mason) == 1 and mason or nil
end

--- "name version": the first version-looking part of what the server says it is.
local function server_name(spec, exe, client)
  local said = client.server_info and client.server_info.version
  if said and said:match("^%s*{") then
    local ok, decoded = pcall(vim.json.decode, said) -- gopls reports its build info
    said = ok and type(decoded) == "table" and decoded.Version or said
  end
  if not said or said == "" then
    said = vim.system({ exe, "--version" }, { text = true }):wait().stdout or ""
  end
  return spec.bin .. " " .. (said:match("v?%d+%.%d+[%w%.%-]*") or "unknown")
end

--- Decode a full semantic tokens result into rows of { text, type, modifiers, row, col }.
local function decode(data, legend, lines, encoding)
  local out, row, char = {}, 0, 0
  for index = 1, #data, 5 do
    local delta_row, delta_char, length, kind, bits = unpack(data, index, index + 4)
    row = row + delta_row
    char = (delta_row > 0 and 0 or char) + delta_char
    local line = lines[row + 1] or ""
    local first = vim.str_byteindex(line, encoding, char, false)
    local last = vim.str_byteindex(line, encoding, math.min(char + length, vim.str_utfindex(line, encoding)), false)
    local modifiers = {}
    for bit_index, name in ipairs(legend.tokenModifiers) do
      if bit.band(bits, bit.lshift(1, bit_index - 1)) ~= 0 then
        modifiers[#modifiers + 1] = name
      end
    end
    table.sort(modifiers)
    out[#out + 1] = { text = line:sub(first + 1, last), type = legend.tokenTypes[kind + 1], modifiers = modifiers,
      row = row, col = first }
  end
  return out
end

--- Ask for the whole file's tokens until they hold still, with no progress in flight.
local function settled_tokens(client, buffer, spec, busy)
  local method = "textDocument/semanticTokens/full"
  local params = { textDocument = vim.lsp.util.make_text_document_params(buffer) }
  local started, changed, last, data = vim.uv.now(), vim.uv.now(), nil, nil
  local hold, timeout = spec.settle or 4000, spec.timeout or 60000
  while vim.uv.now() - started < timeout do
    local reply = client:request_sync(method, params, 20000, buffer)
    local result = reply and not reply.err and reply.result
    if result and result.data then
      local signature = table.concat(result.data, ",")
      if signature ~= last then
        last, data, changed = signature, result.data, vim.uv.now()
      end
    end
    if data and #data > 0 and not next(busy) and vim.uv.now() - changed >= hold then
      return data, true
    end
    vim.wait(1000, function() return false end)
  end
  return data, false
end

local function project(spec, lines)
  local dir = vim.fn.tempname()
  for name, content in pairs(spec.files or {}) do
    vim.fn.mkdir(vim.fs.dirname(dir .. "/" .. name), "p")
    vim.fn.writefile(content, dir .. "/" .. name)
  end
  vim.fn.mkdir(vim.fs.dirname(dir .. "/" .. spec.main), "p")
  vim.fn.writefile(lines, dir .. "/" .. spec.main)
  return dir
end

local busy, current = {}, nil -- the server being read, and its progress begun and not yet ended
vim.api.nvim_create_autocmd("LspProgress", {
  callback = function(ev)
    if not ev.data or ev.data.client_id ~= current then
      return
    end
    local params = ev.data.params or {}
    local value = params.value or {}
    if value.kind == "begin" then
      busy[params.token] = true
    elseif value.kind == "end" then
      busy[params.token] = nil
    end
  end,
})

local out = { "-- Generated by test/support/tools/server_fixture.lua. Do not edit by hand.", "return {" }
local files = vim.fn.globpath(root .. "/test/support/programs", "*", false, true)
table.sort(files)
for _, path in ipairs(files) do
  local lang = vim.fn.fnamemodify(path, ":t:r")
  local spec = SERVERS[lang]
  local lines = vim.fn.readfile(path)
  local paint = spec and painted(table.concat(lines, "\n"), lang)
  local exe = spec and executable(spec.bin)
  if not spec then
    print(("%s: left out, no server is set up for it here"):format(lang))
  elseif not paint then
    print(("%s: left out, no parser and highlights query here"):format(lang))
  elseif not exe then
    print(("%s: left out, no %s on PATH or in Mason"):format(lang, spec.bin))
  else
    local dir = project(spec, lines)
    vim.cmd.edit(vim.fn.fnameescape(dir .. "/" .. spec.main))
    local buffer = vim.api.nvim_get_current_buf()
    vim.bo[buffer].filetype = lang
    busy = {}
    local id = vim.lsp.start({
      name = spec.bin, cmd = vim.list_extend({ exe }, spec.args or {}), root_dir = dir,
      settings = spec.settings, init_options = spec.init_options,
      workspace_folders = { { uri = vim.uri_from_fname(dir), name = dir } },
    }, { bufnr = buffer })
    current = id
    local client
    vim.wait(30000, function()
      client = id and vim.lsp.get_client_by_id(id)
      return client ~= nil and client.initialized == true
    end, 100)
    local provider = client and client.server_capabilities.semanticTokensProvider
    if not client or not client.initialized then
      print(("%s: left out, %s did not start"):format(lang, spec.bin))
    elseif not (provider and provider.legend and provider.full) then
      print(("%s: left out, %s sends no full semantic tokens"):format(lang, spec.bin))
    else
      local data, still = settled_tokens(client, buffer, spec, busy)
      local name = server_name(spec, exe, client)
      local tokens = decode(data or {}, provider.legend, lines, client.offset_encoding)
      out[#out + 1] = ("  %s = {"):format(lang)
      out[#out + 1] = ("    server = %q,"):format(name)
      out[#out + 1] = "    words = {"
      for _, token in ipairs(tokens) do
        local modifiers = vim.tbl_map(function(m) return ("%q"):format(m) end, token.modifiers)
        out[#out + 1] = ("      { %q, %q, %q, %s, %d, %d },"):format(token.text,
          capture_of(paint, token.text, token.row, token.col), token.type,
          #modifiers > 0 and ("{ " .. table.concat(modifiers, ", ") .. " }") or "{}", token.row, token.col)
      end
      out[#out + 1] = "    },"
      out[#out + 1] = "  },"
      print(("%s: %d tokens from %s%s"):format(lang, #tokens, name, still and "" or ", which never held still"))
    end
    if client then
      client:stop()
      if not vim.wait(5000, function() return client:is_stopped() end, 100) then
        client:stop(true)
      end
    end
    vim.cmd("bwipeout!")
    vim.fn.delete(dir, "rf")
  end
end
out[#out + 1] = "}"
vim.fn.writefile(out, root .. "/test/support/servers.lua")
print(("wrote %d languages"):format(#vim.tbl_filter(function(l) return l:match("^  %w+ = {$") end, out)))
