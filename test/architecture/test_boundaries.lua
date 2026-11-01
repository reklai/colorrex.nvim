-- The structure, as tests. If this file and a document disagree, this is right.
local T = require("harness")

-- Every module, and exactly what it may require. Adding an edge here is a design
-- decision, so it has to be made on purpose. The graph is acyclic and reads
-- bottom-up: nothing requires anything listed after it.
local GRAPH = {
  ["color-rex.color"] = {},
  ["color-rex.config"] = {},
  ["color-rex.commands"] = {},
  ["color-rex.terminal.protocol"] = {},
  ["color-rex.terminal"] = { "color-rex.terminal.protocol" },
  ["color-rex.theme"] = { "color-rex.color" },
  ["color-rex.compiler.groups"] = {},
  ["color-rex.compiler.lualine"] = {},
  ["color-rex.compiler.standalone"] = {},
  ["color-rex.compiler.casting"] = {},
  ["color-rex.compiler.solver"] = { "color-rex.color", "color-rex.compiler.casting" },
  ["color-rex.compiler.promises"] = { "color-rex.color", "color-rex.compiler.solver" },
  ["color-rex.compiler"] = {
    "color-rex.compiler.casting", "color-rex.compiler.groups", "color-rex.compiler.lualine", "color-rex.compiler.promises",
    "color-rex.compiler.solver", "color-rex.compiler.standalone", "color-rex.theme",
  },
  ["color-rex.app"] = { "color-rex.compiler", "color-rex.config", "color-rex.terminal", "color-rex.theme" },
  ["color-rex.neovim"] = { "color-rex.config" },
  ["color-rex.health"] = { "color-rex" },
  ["color-rex"] = { "color-rex.app", "color-rex.commands", "color-rex.config", "color-rex.neovim" },
}

-- The only modules allowed to touch Neovim or the machine.
local EFFECTFUL = { ["color-rex"] = true, ["color-rex.neovim"] = true, ["color-rex.health"] = true }

local function files(dir)
  local out = {}
  local listing = io.popen(('find "%s/%s" -name "*.lua" | sort'):format(T.root, dir))
  for path in listing:lines() do
    out[#out + 1] = path
  end
  listing:close()
  return out
end

local function read(path)
  local file = assert(io.open(path))
  local text = file:read("*a")
  file:close()
  return text
end

--- Source with comments and strings removed, so prose cannot trip a scan.
local function code(path)
  return (read(path):gsub("%-%-[^\n]*", ""):gsub('"[^"\n]*"', '""'):gsub("'[^'\n]*'", "''"))
end

local function requires(path)
  local out = {}
  for name in read(path):gmatch('require%("([^"]+)"%)') do
    out[#out + 1] = name
  end
  return out
end

local function module_name(path)
  return path:sub(#T.root + 2):gsub("^lua/", ""):gsub("%.lua$", ""):gsub("/", ".")
end

local function modules()
  local out = {}
  for _, path in ipairs(files("lua")) do
    if not path:match("/lualine/themes/") then
      out[module_name(path)] = path
    end
  end
  return out
end

T.test("architecture: every module is on the map", function()
  for name in pairs(modules()) do
    T.ok(GRAPH[name], name .. " is not in GRAPH: give it a place")
  end
  for name in pairs(GRAPH) do
    T.ok(modules()[name], name .. " is in GRAPH but does not exist")
  end
end)

T.test("architecture: modules require exactly what the map says, no more and no less", function()
  for name, path in pairs(modules()) do
    local actual, allowed = {}, {}
    for _, edge in ipairs(requires(path)) do
      actual[edge] = true
    end
    for _, edge in ipairs(GRAPH[name]) do
      allowed[edge] = true
      T.ok(actual[edge], ("the map says %s requires %s, and it does not"):format(name, edge))
    end
    for edge in pairs(actual) do
      T.ok(allowed[edge], ("%s requires %s, which the map does not allow"):format(name, edge))
    end
  end
end)

T.test("architecture: the dependency graph has no cycles", function()
  local state = {}
  local function visit(name)
    T.ok(state[name] ~= "open", "cycle through " .. name)
    if state[name] == "done" then
      return
    end
    state[name] = "open"
    for _, edge in ipairs(GRAPH[name]) do
      visit(edge)
    end
    state[name] = "done"
  end
  for name in pairs(GRAPH) do
    visit(name)
  end
end)

T.test("architecture: only the host touches Neovim or the machine", function()
  for name, path in pairs(modules()) do
    if not EFFECTFUL[name] then
      local source = code(path)
      T.ok(not source:match("%f[%w_]vim%f[^%w_]"), name .. " mentions vim")
      T.ok(not source:match("%f[%w_]io%."), name .. " does I/O")
      T.ok(not source:match("%f[%w_]os%."), name .. " uses the OS")
    end
  end
end)

T.test("architecture: x.lua is the public face of x/", function()
  for name, path in pairs(modules()) do
    local parent = name:match("^(color%-rex%.[%w_]+)%.[%w_]+$")
    if parent then
      T.ok(modules()[parent], ("%s has no public module %s"):format(path, parent))
      for other in pairs(GRAPH) do
        if other ~= parent and not other:match("^" .. parent:gsub("%-", "%%-") .. "%.") then
          for _, edge in ipairs(GRAPH[other]) do
            T.ok(edge ~= name, ("%s reaches inside %s: %s"):format(other, parent, name))
          end
        end
      end
    end
  end
end)

T.test("architecture: zero dependencies, not one require leaves this plugin", function()
  for _, dir in ipairs({ "lua", "colors", "plugin" }) do
    for _, path in ipairs(files(dir)) do
      for _, name in ipairs(requires(path)) do
        T.ok(name == "color-rex" or name:match("^color%-rex%."), ("%s requires %s"):format(path, name))
      end
    end
  end
end)

T.test("architecture: one name everywhere", function()
  T.eq(require("color-rex.config").NAME, "color-rex")
  for _, path in ipairs({ "colors/color-rex.lua", "plugin/color-rex.lua", "lua/color-rex.lua",
    "lua/lualine/themes/color-rex.lua", "doc/color-rex.txt", "lazy.lua" }) do
    T.ok(io.open(T.root .. "/" .. path), path .. " is missing")
  end
end)

T.test("architecture: group modules name roles, there is not one color literal", function()
  for _, name in ipairs({ "groups", "lualine" }) do
    T.ok(not read(("%s/lua/color-rex/compiler/%s.lua"):format(T.root, name)):match("#%x%x%x%x%x%x"), name)
  end
end)
