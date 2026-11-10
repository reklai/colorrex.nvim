-- The structure, as tests. If this file and a document disagree, this is right.
local T = require("harness")

-- Every module, and exactly what it may require. Adding an edge here is a design
-- decision, so it has to be made on purpose. The graph is acyclic and reads
-- bottom-up: nothing requires anything listed after it.
local GRAPH = {
  ["colorrex.color"] = {},
  ["colorrex.meanings"] = {},
  ["colorrex.chunks"] = {},
  ["colorrex.config"] = {},
  ["colorrex.commands"] = {},
  ["colorrex.terminal.protocol"] = {},
  ["colorrex.terminal"] = { "colorrex.terminal.protocol" },
  ["colorrex.theme"] = { "colorrex.color" },
  ["colorrex.groups.editor"] = {},
  ["colorrex.groups.syntax"] = {},
  ["colorrex.groups.treesitter"] = { "colorrex.meanings" },
  ["colorrex.groups.lsp"] = { "colorrex.meanings" },
  ["colorrex.groups.diagnostics"] = {},
  ["colorrex.groups.plugins"] = {},
  ["colorrex.groups"] = {
    "colorrex.meanings", "colorrex.groups.diagnostics", "colorrex.groups.editor", "colorrex.groups.lsp",
    "colorrex.groups.plugins", "colorrex.groups.syntax", "colorrex.groups.treesitter",
  },
  ["colorrex.lualine"] = {},
  ["colorrex.roles.casting"] = { "colorrex.color" },
  ["colorrex.roles"] = { "colorrex.color", "colorrex.roles.casting" },
  ["colorrex.compiler.standalone"] = {},
  ["colorrex.compiler.promises"] = { "colorrex.color", "colorrex.roles" },
  ["colorrex.compiler"] = {
    "colorrex.compiler.promises", "colorrex.compiler.standalone", "colorrex.groups", "colorrex.lualine",
    "colorrex.roles", "colorrex.theme",
  },
  ["colorrex.report"] = {},
  ["colorrex.app"] = {
    "colorrex.chunks", "colorrex.compiler", "colorrex.config", "colorrex.meanings", "colorrex.report", "colorrex.terminal",
    "colorrex.theme",
  },
  ["colorrex.neovim"] = { "colorrex.config" },
  ["colorrex.health"] = { "colorrex", "colorrex.config" },
  ["colorrex"] = { "colorrex.app", "colorrex.commands", "colorrex.config", "colorrex.neovim" },
}

-- The only modules allowed to touch Neovim or the machine.
local EFFECTFUL = { ["colorrex"] = true, ["colorrex.neovim"] = true, ["colorrex.health"] = true }

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
    local parent = name:match("^(colorrex%.[%w_]+)%.[%w_]+$")
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
        T.ok(name == "colorrex" or name:match("^colorrex%."), ("%s requires %s"):format(path, name))
      end
    end
  end
end)

T.test("architecture: one name everywhere", function()
  T.eq(require("colorrex.config").NAME, "colorrex")
  for _, path in ipairs({ "colors/colorrex.lua", "plugin/colorrex.lua", "lua/colorrex.lua",
    "lua/lualine/themes/colorrex.lua", "doc/colorrex.txt", "lazy.lua" }) do
    T.ok(io.open(T.root .. "/" .. path), path .. " is missing")
  end
end)

T.test("architecture: groups and lualine name roles, there is not one color literal", function()
  local paths = files("lua/colorrex/groups")
  paths[#paths + 1] = T.root .. "/lua/colorrex/groups.lua"
  paths[#paths + 1] = T.root .. "/lua/colorrex/lualine.lua"
  T.ok(#paths == 8, "every area must be scanned")
  for _, path in ipairs(paths) do
    T.ok(not read(path):match("#%x%x%x%x%x%x"), path)
  end
end)
