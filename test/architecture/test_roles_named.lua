-- The roles, by name. They are public: a user's `groups` and everything written from
-- roles() names them, so one that is renamed or dropped breaks a config somewhere. This
-- pins the list, and holds the help file to it.
local T = require("harness")
local Compiler = require("colorrex.compiler")
local Config = require("colorrex.config")

-- Adding a name here is adding to the contract. Taking one away is breaking it.
local ROLES = {
  "accent", "accent_soft", "base", "border", "border_strong", "comment", "cursorline", "diff_add", "diff_change",
  "diff_delete", "diff_deleted", "diff_text", "element", "error", "failure", "fg", "float_accent", "float_error",
  "float_hint", "float_info", "float_ok", "float_warn", "func", "hint", "info", "keyword", "landmark", "muted", "number",
  "ok", "on_accent", "on_diff_text", "on_error", "on_hint", "on_info", "on_keyword", "on_ok", "on_search", "on_warn",
  "operator", "predicted", "preproc", "property", "reference", "search", "select_accent", "special", "statusline",
  "stopped", "string", "subtle", "type", "visual", "warn",
}

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

T.test("roles: the help file lists every one", function()
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
