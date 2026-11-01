-- lazy.nvim reads this from inside the plugin, so `{ "reklai/color-rex.lua" }` is a
-- complete install: a colorscheme has to load first and at startup, and `opts`
-- is what turns it on. Anything in a user's own spec overrides these.
return {
  {
    "reklai/color-rex.lua",
    lazy = false,
    priority = 1000,
    opts = {},
  },
}
