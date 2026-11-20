-- The public roles, by name. A user's `groups` and everything written from roles()
-- names them, so one that is renamed or dropped breaks a config somewhere. This pins the
-- list, and holds the help file to it. The roles not listed here are the compiler's own:
-- nothing outside can name them, so they can change.
local T = require("harness")
local Compiler = require("colorrex.compiler")
local Config = require("colorrex.config")

-- Adding a name here is adding to the contract. Taking one away is breaking it.
local ROLES = {
  "accent", "accent_soft", "base", "border", "border_strong", "comment", "cursorline", "diff_add", "diff_change",
  "diff_delete", "element", "error", "failure", "fg", "func", "hint", "info", "keyword", "muted", "number", "ok",
  "on_accent", "on_error", "on_hint", "on_info", "on_ok", "on_search", "on_warn", "operator", "preproc", "property",
  "search", "special", "statusline", "string", "subtle", "type", "visual", "warn",
}

--- The roles a compile holds that are not public, sorted.
local function internal()
  local public, out = {}, {}
  for _, name in ipairs(ROLES) do
    public[name] = true
  end
  for name in pairs(Compiler.compile({ ansi = {} }, Config.resolve(), "dark").roles) do
    if not public[name] then
      out[#out + 1] = name
    end
  end
  table.sort(out)
  return out
end

local function names(theme, opts)
  local out = {}
  for name in pairs(Compiler.palette(Compiler.compile(theme, Config.resolve(opts), "dark"))) do
    out[#out + 1] = name
  end
  table.sort(out)
  return table.concat(out, " ")
end

T.test("roles: the names handed out are exactly the pinned ones, whatever the theme or options", function()
  local F = require("fixtures")
  local want = table.concat(ROLES, " ")
  T.eq(names({ ansi = {} }), want)
  T.eq(names(F.theme()), want)
  T.eq(names(F.theme({ cursor = false })), want)
  T.eq(names(F.theme({ fg = "#383a42", bg = "#fafafa" }), { voice = false, transparent = false, contrast = 4.5 }), want)
end)

T.test("roles: one of the compiler's own is refused in a group, as a role that does not exist is", function()
  local own = internal()
  T.ok(#own > 0, "the compiler has roles of its own")
  for _, name in ipairs(own) do
    local ok, err = pcall(Compiler.validate, Config.resolve({ groups = { Mine = { fg = name } } }))
    T.ok(not ok and tostring(err):find(("group 'Mine' names an unknown role '%s'"):format(name), 1, true),
      name .. " was accepted: " .. tostring(err))
  end
end)

T.test("roles: every role check suggests for a stray is one a group can name", function()
  local colorscheme = Compiler.compile(require("fixtures").theme(), Config.resolve(), "dark")
  local public = {}
  for _, name in ipairs(ROLES) do
    public[name] = true
  end
  local rng = T.rng(11)
  for _ = 1, 300 do
    local hex = ("#%02x%02x%02x"):format(rng(256), rng(256), rng(256))
    for _, stray in ipairs(Compiler.strays(colorscheme, { X = { fg = hex, bg = hex, sp = hex } })) do
      T.ok(public[stray.nearest], ("check suggests %s for %s, which no group can name"):format(stray.nearest, stray.key))
    end
  end
end)

T.test("roles: the help file lists every public one, and none of the compiler's own", function()
  local file = assert(io.open(T.root .. "/doc/colorrex.txt"))
  local text = file:read("*a")
  file:close()
  local section = text:match("%*colorrex%-roles%*\n(.-)\n%u+ +%*")
  T.ok(section, "help has no roles section")
  local listed = {}
  for word in section:gmatch("[%l_]+") do
    listed[word] = true
  end
  for _, name in ipairs(ROLES) do
    T.ok(listed[name], name .. " is a role the help file does not list")
  end
  for _, name in ipairs(internal()) do
    T.ok(not listed[name], name .. " is the compiler's own, and the help file lists it")
  end
end)

T.test("roles: every option the code has is in the README and the help file", function()
  for _, path in ipairs({ "README.md", "doc/colorrex.txt" }) do
    local file = assert(io.open(T.root .. "/" .. path))
    local text = file:read("*a")
    file:close()
    for option in pairs(Config.defaults) do
      T.ok(text:find("\n +" .. option .. " = "), ("%s does not show the option %s"):format(path, option))
    end
  end
end)
