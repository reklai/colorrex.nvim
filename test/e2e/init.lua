-- Config for the real-terminal suite. `nvim -u test/e2e/init.lua`.
vim.opt.runtimepath:prepend(vim.env.COLORREX_ROOT)
vim.opt.termguicolors = true
if vim.env.COLORREX_E2E_BACKGROUND then
  -- A user who sets 'background' makes Neovim delete its own detection, which
  -- leaves the session's reply handling as the only way to see a dark/light flip.
  vim.cmd("set background=" .. vim.env.COLORREX_E2E_BACKGROUND)
end
vim.cmd("runtime plugin/colorrex.lua")
if vim.env.COLORREX_E2E_MANUAL then
  require("colorrex").setup({ auto = false }) -- setup also turns it on
else
  vim.cmd.colorscheme("colorrex")
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
  local file = assert(io.open(opts.args, "w"))
  file:write(vim.json.encode({
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
  }))
  file:close()
end, { nargs = 1 })
