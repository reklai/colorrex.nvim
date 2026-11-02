-- Below the floor there is nothing to register. Saying so is lua/colorrex.lua's
-- job, once, when the colorscheme is asked for.
if vim.fn.has("nvim-0.12") == 0 then
  return
end

if vim.g.loaded_colorrex then
  return
end
vim.g.loaded_colorrex = true

local Commands = require("colorrex.commands")

vim.api.nvim_create_user_command("ColorRex", function(opts)
  require("colorrex").command(opts.fargs, opts.bang)
end, {
  nargs = "*", -- "*" so that arity errors come from us, with a real message
  bang = true,
  desc = "colorrex: sync with the terminal, or " .. table.concat(Commands.names(), ", "),
  complete = function(arglead, cmdline)
    return Commands.complete(arglead, cmdline)
  end,
})

-- <Plug> mappings bind no key themselves; a user maps one to any key they like.
vim.keymap.set("n", "<Plug>(colorrex)", function()
  require("colorrex").command({}, false)
end, { desc = "colorrex: " .. Commands.default.desc })

for _, command in ipairs(Commands.catalog) do
  if command.plug then
    vim.keymap.set("n", ("<Plug>(colorrex-%s)"):format(command.name), function()
      require("colorrex").command({ command.name }, false)
    end, { desc = "colorrex: " .. command.desc })
  end
end
