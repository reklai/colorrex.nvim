-- Config for the real-terminal suite. `nvim -u test/e2e/init.lua`.
vim.opt.runtimepath:prepend(vim.env.COLORREX_ROOT)
vim.opt.termguicolors = true
if vim.env.COLORREX_E2E_BACKGROUND then
  -- A user who sets 'background' makes Neovim delete its own detection, which
  -- leaves the session's reply handling as the only way to see a dark/light flip.
  vim.cmd("set background=" .. vim.env.COLORREX_E2E_BACKGROUND)
end
if vim.env.COLORREX_E2E_UPDATETIME then
  vim.o.updatetime = tonumber(vim.env.COLORREX_E2E_UPDATETIME) -- how soon a pause counts
end
vim.cmd("runtime plugin/colorrex.lua")

-- A config written in roles, as a user with a statusline or a plugin of their own would:
-- one group through `groups`, and one set by hand whenever the colorscheme changes.
if vim.env.COLORREX_E2E_ROLES then
  vim.api.nvim_create_autocmd("ColorScheme", {
    pattern = "colorrex",
    callback = function()
      local roles = require("colorrex").roles()
      vim.api.nvim_set_hl(0, "E2ERole", { fg = roles.accent, bg = roles.base })
      vim.g.e2e_role_events = (vim.g.e2e_role_events or 0) + 1
    end,
  })
end

if vim.env.COLORREX_E2E_MANUAL then
  require("colorrex").setup({ auto = false }) -- setup also turns it on
elseif vim.env.COLORREX_E2E_ROLES then
  require("colorrex").setup({
    groups = { E2EGroup = { fg = "on_accent", bg = "accent", bold = true } },
    icons = vim.env.COLORREX_E2E_ICONS ~= "off",
    transparent = vim.env.COLORREX_E2E_OPAQUE == nil,
  })
else
  vim.cmd.colorscheme("colorrex")
end

-- Real plugins, from wherever a plugin manager left them, set up after the colorscheme
-- as a manager would. Each is optional: the suite checks what it finds.
local plugins = vim.env.COLORREX_E2E_PLUGINS
local function plugin(name, setup)
  local path = plugins and vim.fs.joinpath(plugins, name)
  if not (path and vim.uv.fs_stat(path)) then
    return
  end
  vim.opt.runtimepath:append(path)
  vim.g.e2e_plugins = vim.list_extend(vim.g.e2e_plugins or {}, { name })
  if setup then
    local ok, err = pcall(setup)
    if not ok then
      vim.g.e2e_plugin_errors = vim.list_extend(vim.g.e2e_plugin_errors or {}, { name .. ": " .. tostring(err) })
    end
  end
end
if plugins then
  plugin("plenary.nvim")
  plugin("nvim-web-devicons") -- nothing sets it up: the first plugin to ask for an icon does
  plugin("lualine.nvim", function()
    require("lualine").setup({
      options = { theme = "colorrex" },
      sections = { lualine_x = { "encoding", "fileformat", "filetype" } },
    })
  end)
  plugin("telescope.nvim", function() require("telescope").setup({}) end)
  plugin("oil.nvim", function() require("oil").setup({}) end)
  plugin("which-key.nvim", function() require("which-key").setup({}) end)
  plugin("trouble.nvim", function() require("trouble").setup({}) end)
  plugin("fidget.nvim", function() require("fidget").setup({}) end)
  plugin("mini.indentscope", function() require("mini.indentscope").setup({}) end)
  plugin("harpoon", function() require("harpoon"):setup({}) end)
  plugin("mason.nvim", function() require("mason").setup({}) end)
  plugin("blink.cmp", function()
    require("blink.cmp").setup({ fuzzy = { implementation = "lua" } }) -- nothing to download
  end)
  plugin("undotree")
  for _, name in ipairs(vim.split(vim.env.COLORREX_E2E_EXTRA or "", ",", { trimempty = true })) do
    plugin(name) -- anything else to look at, by directory name, with its defaults
  end
end
-- The keybind path, mapped the way a user would.
vim.keymap.set("n", "gS", "<Plug>(colorrex)")

-- A Neovim that is never focused and never asked: the case the broadcast exists for.
vim.api.nvim_create_user_command("E2EDump", function(opts)
  local function hl(name, key)
    local value = vim.api.nvim_get_hl(0, { name = name, link = false })[key]
    return value and ("#%06x"):format(value) or vim.NIL
  end
  local status = require("colorrex").status()
  -- What :ColorRex check says, read where it is said.
  local notify, said = vim.notify, {}
  vim.notify = function(message) said[#said + 1] = message end
  pcall(vim.cmd, "ColorRex check")
  vim.notify = notify
  local icons = {} -- every group a file icon wears, lualine's copies included
  for name, spec in pairs(vim.api.nvim_get_hl(0, {})) do
    if name:find("DevIcon", 1, true) and spec.fg then
      icons[name] = ("#%06x"):format(spec.fg)
    end
  end
  local file = assert(io.open(opts.args, "w"))
  file:write(vim.json.encode({
    roles = require("colorrex").roles(),
    role_fg = hl("E2ERole", "fg"),
    role_bg = hl("E2ERole", "bg"),
    role_events = vim.g.e2e_role_events or 0,
    group_fg = hl("E2EGroup", "fg"),
    group_bg = hl("E2EGroup", "bg"),
    icons = next(icons) and icons or vim.empty_dict(),
    check = table.concat(said, "\n"),
    plugins = vim.g.e2e_plugins or {},
    plugin_errors = vim.g.e2e_plugin_errors or {},
    source = status.source,
    completeness = status.completeness,
    fg = status.fg,
    bg = status.bg,
    reason = status.last.reason or vim.NIL,
    outcome = status.last.outcome or vim.NIL,
    background = vim.o.background,
    colors_name = vim.g.colors_name,
    string = hl("String", "fg"),
    terminal1 = vim.g.terminal_color_1,
    normal_bg = hl("Normal", "bg"),
    failure = hl("ColorRexFailure", "fg"),
    negation = hl("ColorRexNegation", "fg"),
    value = hl("@number", "fg"),
    route = status.route or vim.NIL,
    borrowed = status.borrowed,
    voice = status.voice or vim.NIL,
    tmux = status.tmux,
  }))
  file:close()
end, { nargs = 1 })
