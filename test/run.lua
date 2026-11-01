-- Run the pure suites:        luajit test/run.lua [suite] [name-pattern]
-- Run the Neovim suites:      nvim --headless --clean -l test/run.lua integration
--
-- Tests are grouped by INTENT, because that decides how you read a failure:
--   unit          a logic bug
--   conformance   a promise broken for a real theme
--   fault         hostile input broke an invariant
--   architecture  a boundary was crossed
--   integration   the wiring into real Neovim broke
-- Everything but integration runs under plain LuaJIT, which is itself the proof
-- that all of this but the host has no dependency on Neovim.
local script = (debug.getinfo(1, "S").source:sub(2))
local root = script:match("^(.*)/test/run%.lua$") or "."
package.path = root .. "/lua/?.lua;" .. root .. "/test/support/?.lua;" .. package.path

local T = require("harness")
T.root = root

local args = _G.arg or {}
local suite, pattern = args[1], args[2]
local inside_nvim = _G.vim ~= nil
local PURE = { "unit", "conformance", "fault", "architecture" }

local suites = suite and suite ~= "" and { suite } or (inside_nvim and { "integration" } or PURE)
for _, name in ipairs(suites) do
  local dir = root .. "/test/" .. name
  local listing = io.popen(('find "%s" -name "test_*.lua" | sort'):format(dir))
  for path in listing:lines() do
    T.current_file = path:sub(#root + 2)
    assert(loadfile(path))()
  end
  listing:close()
end

local failed = T.run(pattern)
if inside_nvim then
  vim.cmd(failed > 0 and "cquit 1" or "qall!")
else
  os.exit(failed > 0 and 1 or 0)
end
