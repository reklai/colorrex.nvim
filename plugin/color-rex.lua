-- Below the floor there is nothing to register. Saying so is lua/color-rex.lua's
-- job, once, when the colorscheme is asked for.
if vim.fn.has("nvim-0.12") == 0 then
  return
end

if vim.g.loaded_color_rex then
  return
end
vim.g.loaded_color_rex = true

local Commands = require("color-rex.commands")

vim.api.nvim_create_user_command("ColorRex", function(opts)
  require("color-rex").command(opts.fargs, opts.bang)
end, {
  nargs = "*", -- "*" so that arity errors come from us, with a real message
  bang = true,
  desc = "color-rex: sync with the terminal, or " .. table.concat(Commands.names(), ", "),
  complete = function(arglead, cmdline)
    return Commands.complete(arglead, cmdline)
  end,
})

-- <Plug> mappings bind no key themselves; a user maps one to any key they like.
vim.keymap.set("n", "<Plug>(color-rex)", function()
  require("color-rex").command({}, false)
end, { desc = "color-rex: " .. Commands.default.desc })

for _, command in ipairs(Commands.catalog) do
  if command.plug then
    vim.keymap.set("n", ("<Plug>(color-rex-%s)"):format(command.name), function()
      require("color-rex").command({ command.name }, false)
    end, { desc = "color-rex: " .. command.desc })
  end
end
