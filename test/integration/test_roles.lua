-- Roles, a user's own groups and the look at the screen, through real Neovim: the
-- public functions, the real highlight table, and the events a plugin's colors arrive on.
-- Headless, so no terminal answers; test/e2e covers a theme that changes.
local T = require("harness")

local RT = vim.fs.normalize(T.root)
if not vim.startswith(RT, "/") then
  RT = vim.fn.fnamemodify(RT, ":p"):gsub("/$", "")
end
vim.opt.runtimepath:prepend(RT)
vim.env.XDG_STATE_HOME = vim.fn.tempname()
vim.cmd("runtime plugin/colorrex.lua")

local function hl(name, key)
  local value = vim.api.nvim_get_hl(0, { name = name, link = false })[key]
  return value and ("#%06x"):format(value) or nil
end

--- What `:ColorRex check` says.
local function check()
  local said, notify = {}, vim.notify
  vim.notify = function(message) said[#said + 1] = message end
  vim.cmd("ColorRex check")
  vim.notify = notify
  return table.concat(said, "\n")
end

--- Run `fn` with the plugin set up fresh, and put it back as it was found.
local function with_setup(options, fn)
  local colorrex = require("colorrex")
  colorrex.setup(options)
  local ok, err = pcall(fn, colorrex)
  colorrex.setup({})
  if not ok then
    error(err, 0)
  end
end

T.test("roles: the public roles() is every color the groups are written in", function()
  with_setup({}, function(colorrex)
    local roles = colorrex.roles()
    T.eq(hl("Normal", "fg"), roles.fg)
    T.eq(hl("Comment", "fg"), roles.comment)
    T.eq(hl("NormalFloat", "bg"), roles.element)
    T.eq(hl("DiagnosticError", "fg"), roles.error)
    T.eq(hl("Normal", "bg"), nil, "transparent by default")
    T.ok(roles.base:match("^#%x%x%x%x%x%x$"), "and base is still there to hand to a plugin")
  end)
end)

T.test("roles: inside ColorScheme they are the colors that were just applied", function()
  local seen
  local id = vim.api.nvim_create_autocmd("ColorScheme", {
    pattern = "colorrex",
    callback = function()
      local roles = require("colorrex").roles()
      vim.api.nvim_set_hl(0, "MineFromRoles", { fg = roles.accent, bg = roles.base })
      seen = roles
    end,
  })
  with_setup({}, function(colorrex)
    T.ok(seen, "ColorScheme fired for colorrex")
    T.eq(hl("MineFromRoles", "fg"), colorrex.roles().accent)
    T.ok(not check():find("MineFromRoles", 1, true), "a group written from roles() is not a stray")
  end)
  vim.api.nvim_del_autocmd(id)
  vim.cmd("hi clear MineFromRoles")
end)

T.test("groups: setup defines yours in real highlights, links and styles included", function()
  with_setup({
    groups = {
      MineLabel = { fg = "on_accent", bg = "accent", bold = true },
      MineLinked = { link = "Comment" },
      MineLine = { sp = "error", undercurl = true },
      ["@mine.capture"] = { fg = "keyword", italic = true },
      Comment = { fg = "muted" },
    },
  }, function(colorrex)
    local roles = colorrex.roles()
    T.eq(hl("MineLabel", "fg"), roles.on_accent)
    T.eq(hl("MineLabel", "bg"), roles.accent)
    T.ok(vim.api.nvim_get_hl(0, { name = "MineLabel" }).bold)
    T.eq(vim.api.nvim_get_hl(0, { name = "MineLinked" }).link, "Comment")
    T.eq(hl("MineLine", "sp"), roles.error)
    T.ok(vim.api.nvim_get_hl(0, { name = "MineLine" }).undercurl)
    T.eq(hl("@mine.capture", "fg"), roles.keyword)
    T.eq(hl("Comment", "fg"), roles.muted, "one of ours, replaced")
    T.ok(not vim.api.nvim_get_hl(0, { name = "Comment" }).italic, "whole, not merged")
  end)
  T.eq(next(vim.api.nvim_get_hl(0, { name = "MineLabel" })), nil, "and setup without them takes them away")
  T.ok(vim.api.nvim_get_hl(0, { name = "Comment" }).italic)
end)

T.test("groups: a mistake in setup is refused whole, and what was showing stays", function()
  with_setup({ groups = { MineKept = { fg = "accent" } } }, function(colorrex)
    local before = hl("MineKept", "fg")
    for _, bad in ipairs({
      { groups = { MineKept = { fg = "acent" } } },
      { groups = { MineKept = { fg = "#ff0000" } } },
      { groups = { MineKept = { fg = "accent", shiny = true } } },
      { groops = {} },
    }) do
      local ok, err = pcall(colorrex.setup, bad)
      T.ok(not ok, vim.inspect(bad))
      T.ok(tostring(err):find("colorrex:", 1, true), tostring(err))
    end
    T.eq(vim.g.colors_name, "colorrex")
    T.eq(hl("MineKept", "fg"), before, "the last good setup is still the one showing")
    vim.cmd.colorscheme("colorrex")
    T.eq(hl("MineKept", "fg"), before, "and still is after a reload")
  end)
end)

T.test("check: a clean Neovim has nothing on screen that is not the theme's", function()
  for _, options in ipairs({ {}, { transparent = false }, { voice = false } }) do
    with_setup(options, function()
      local text = check()
      T.ok(text:find("every highlight on screen wears this theme's colors", 1, true), text)
    end)
  end
end)

T.test("check: both backgrounds are clean, as Neovim's own defaults differ between them", function()
  local was = vim.o.background
  for _, background in ipairs({ "light", "dark" }) do
    vim.o.background = background
    vim.cmd.colorscheme("colorrex")
    local text = check()
    T.ok(text:find("every highlight on screen wears this theme's colors", 1, true), background .. ": " .. text)
  end
  vim.o.background = was
  vim.cmd.colorscheme("colorrex")
end)

T.test("check: a plugin's fixed color is found in the real table, and the fix it shows works", function()
  with_setup({}, function(colorrex)
    vim.api.nvim_set_hl(0, "PluginFixed", { fg = "#123456" })
    vim.api.nvim_set_hl(0, "PluginLinked", { link = "PluginFixed" })
    local text = check()
    T.ok(text:find("1 highlight from elsewhere wears colors that are not this theme's", 1, true), text)
    T.ok(text:find("PluginFixed  fg #123456 (nearest role: ", 1, true), text)
    T.ok(not text:find("PluginLinked", 1, true), "a link is judged where it leads")
    local groups = assert(loadstring("return { " .. text:match("\n  (groups = %b{})") .. " }"))().groups
    colorrex.setup({ groups = groups })
    T.ok(check():find("every highlight on screen wears this theme's colors", 1, true), check())
    T.ok(hl("PluginFixed", "fg") ~= "#123456")
  end)
  vim.cmd("hi clear PluginFixed")
  vim.cmd("hi clear PluginLinked")
end)

T.test("check: another colorscheme's highlights are not judged", function()
  with_setup({}, function()
    vim.cmd.colorscheme("habamax")
    T.ok(not check():find("from elsewhere", 1, true))
    T.ok(not check():find("every highlight on screen", 1, true))
  end)
end)

--- Stand in for a plugin that ships a color per file type and puts them all back on
--- every ColorScheme, as nvim-web-devicons does.
local SHIPPED = { DevIconDefault = "#6d8086", DevIconLua = "#51a0cf", DevIconRs = "#dea584", DevIconVim = "#019833" }
local function icon_plugin()
  local function define()
    for name, color in pairs(SHIPPED) do
      vim.api.nvim_set_hl(0, name, { fg = color, ctermfg = 67 })
    end
  end
  define()
  local id = vim.api.nvim_create_autocmd("ColorScheme", { callback = define })
  return define, function()
    vim.api.nvim_del_autocmd(id)
    for name in pairs(SHIPPED) do
      vim.cmd("hi clear " .. name)
    end
  end
end

local function settle()
  vim.api.nvim_exec_autocmds("SafeState", {})
end

T.test("icons: with no option set, a plugin's icon colors are the theme's once Neovim settles", function()
  with_setup({}, function(colorrex)
    local define, remove = icon_plugin()
    settle()
    T.eq(hl("DevIconDefault", "fg"), colorrex.roles().muted)
    for name, shipped in pairs(SHIPPED) do
      T.ok(hl(name, "fg") ~= shipped, name)
    end
    T.eq(vim.api.nvim_get_hl(0, { name = "DevIconLua" }).ctermfg, 67, "only the color moved")
    T.ok(check():find("every highlight on screen wears this theme's colors", 1, true), check())

    define() -- put back with no colorscheme in between, as on a change of 'background'
    T.eq(hl("DevIconLua", "fg"), "#51a0cf")
    settle()
    T.ok(hl("DevIconLua", "fg") ~= "#51a0cf")

    vim.cmd.colorscheme("colorrex") -- the plugin repaints on ColorScheme, after ours
    vim.wait(50, function() return false end) -- the look that follows a render is deferred
    T.ok(hl("DevIconLua", "fg") ~= "#51a0cf", "caught after a colorscheme with no key pressed")
    remove()
  end)
end)

T.test("icons: off leaves them as shipped, and check says how many", function()
  with_setup({ icons = false }, function()
    local _, remove = icon_plugin()
    settle()
    T.eq(hl("DevIconLua", "fg"), "#51a0cf")
    local text = check()
    T.ok(text:find("4 highlights from elsewhere", 1, true), text)
    T.ok(text:find("DevIcon* (4 groups)", 1, true), text)
    remove()
  end)
end)

T.test("icons: another colorscheme's icons are left alone", function()
  with_setup({ icons = true }, function()
    vim.cmd.colorscheme("habamax")
    local _, remove = icon_plugin()
    settle()
    T.eq(hl("DevIconLua", "fg"), "#51a0cf")
    remove()
  end)
end)
