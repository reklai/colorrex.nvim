-- The promises, by name. The README, the help file and every code that
-- `:ColorRex check` prints must agree on the same three, so a rename cannot leave
-- one place behind.
local T = require("harness")

local PROMISES = { "faithful", "practical", "voice" }
local KNOWN = { faithful = true, practical = true, voice = true }

local function read(path)
  local file = assert(io.open(T.root .. "/" .. path))
  local text = file:read("*a")
  file:close()
  return text
end

local function lua_files()
  local out = {}
  local listing = io.popen(('cd "%s" && find lua -name "*.lua" | sort'):format(T.root))
  for path in listing:lines() do
    out[#out + 1] = path
  end
  listing:close()
  return out
end

--- Every note and failure code in the source, with the file it is in.
local function codes()
  local out = {}
  for _, path in ipairs(lua_files()) do
    local text = read(path)
    for _, pattern in ipairs({ 'code = "([%w_]+%.[%w_]+)"', 'fail%("([%w_]+%.[%w_]+)"' }) do
      for code in text:gmatch(pattern) do
        out[#out + 1] = { code = code, path = path }
      end
    end
  end
  return out
end

T.test("promises: every code names one of the three", function()
  local seen, found = {}, codes()
  T.ok(#found >= 15,("only %d codes found, so the scan is broken"):format(#found))
  for _, item in ipairs(found) do
    local promise = item.code:match("^([%w_]+)%.")
    T.ok(KNOWN[promise], ("%s in %s"):format(item.code, item.path))
    seen[promise] = true
  end
  for _, promise in ipairs(PROMISES) do
    T.ok(seen[promise], promise .. " has no code at all")
  end
end)

T.test("promises: the README names the same three, in order", function()
  local section = read("README.md"):match("\n## The promises\n(.-)\n## ")
  T.ok(section, "README has no promises section")
  local names = {}
  for name in section:gmatch("\n%*%*(%a+)%.%*%*") do
    names[#names + 1] = name:lower()
  end
  T.eq(table.concat(names, " "), table.concat(PROMISES, " "))
end)

T.test("promises: the help file names the same three, in order", function()
  local section = read("doc/colorrex.txt"):match("%*colorrex%-promises%*\n(.-)\n%u+ +%*")
  T.ok(section, "help has no promises section")
  local names = {}
  for name in section:gmatch("\n(%l+) +%u") do
    names[#names + 1] = name
  end
  T.eq(table.concat(names, " "), table.concat(PROMISES, " "))
end)

T.test("promises: retired names appear only where a rename is explained", function()
  local allowed = { ["lua/colorrex/config.lua"] = true, ["doc/colorrex.txt"] = true }
  local paths = { "README.md", "doc/colorrex.txt", "docs/architecture.md", "docs/sync.md" }
  for _, path in ipairs(lua_files()) do
    paths[#paths + 1] = path
  end
  for _, path in ipairs(paths) do
    local text = read(path)
    T.ok(not text:find("unique%.%a"), path .. " still uses a unique.* code")
    for _, old in ipairs({ "Useful", "Unique", "Dynamic" }) do
      T.ok(not text:find("%*%*" .. old .. "%.%*%*"), ("%s still lists %s as a promise"):format(path, old))
      T.ok(not text:find("%-%- " .. old:upper() .. "[ :]"), ("%s still names %s"):format(path, old:upper()))
    end
    T.ok(allowed[path] or not text:find("force_unique", 1, true), path .. " still mentions force_unique")
  end
end)
