-- lazy.nvim reads this from inside the plugin, so `{ "reklai/colorrex.nvim" }` is a
-- complete install: a colorscheme has to load first and at startup, and `opts`
-- is what turns it on. Anything in a user's own spec overrides these.
return {
  {
    "reklai/colorrex.nvim",
    lazy = false,
    priority = 1000,
    opts = {},
  },
}
