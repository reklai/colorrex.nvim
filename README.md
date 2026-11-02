# colorrex.nvim

Compiles the theme your terminal is showing into a native Neovim colorscheme.
No dependencies, no configuration, no theme files.

The target is for libghostty-based terminal ecosystem. Currently other terminals are not supported.

```lua
vim.cmd.colorscheme("colorrex")
```

That is the whole setup. It asks your terminal for its 19 colors, in one request,
and compiles them into over 300 highlight groups.

## The promises

**Faithful.** Your foreground and background are never altered. Every syntax
color is one of your theme's ANSI colors, unchanged unless it is unreadable. A
color below 3:1 contrast moves in lightness only, the minimum needed, so it
keeps its hue. Text also stays readable on whatever is behind it: a selection eases
off until comments can be read through it, and colored text in a float is lifted
against the float. `:ColorRex explain` shows where any color came from.

**Unique.** Every theme looks like itself. Each of the twelve chromatic ANSI colors
has a job on screen, and your cursor color is the accent. Roles follow the ANSI
convention, the closest thing a terminal theme has to its author's intent, and move
only as far as it takes to keep code readable. So a difference you can see always
shows, a difference you cannot see never does, and a family of themes stays a family.
Two themes with the same colors read the same in code, because they are. Roles the
palette cannot separate by color differ by weight or slant, and `:ColorRex status`
shows every theme's exact id.

**Dynamic.** Ghostty reports every config reload, so theme changes apply by
themselves. Rex reports dark and light changes; a change to a theme of the same
brightness sends no signal to a block, so those apply on the next focus change,
or the moment you run `:ColorRex`. Run it in one Neovim and every other Neovim on
the machine checks its own terminal too.

These are not just claims. `test/conformance` holds them against all 819 themes
Ghostty ships, and `test/fault` against 20,000 random palettes.

## Commands

| Command | What it does |
| --- | --- |
| `:ColorRex` | Read the terminal's theme and repaint if it changed |
| `:ColorRex status` | Show the active theme and the last sync |
| `:ColorRex explain [group]` | Show where a group's color came from |
| `:ColorRex check` | Judge the current theme against the promises |
| `:ColorRex compile [name]` | Write a standalone colorscheme that needs no plugin |

Bind any of them. `<Plug>(colorrex)` runs `:ColorRex`, and `status`, `explain`
and `check` have mappings of their own, all running the same code as the command:

```lua
vim.keymap.set("n", "<leader>ts", "<Plug>(colorrex)")
```

## Install

You need Neovim 0.12 or newer and a libghostty terminal. With
[lazy.nvim](https://github.com/folke/lazy.nvim), this one line is the whole install:

```lua
{ "reklai/colorrex.nvim" }
```

It loads first, at startup, and turns itself on. Nothing else is required. If you
prefer to spell it out, this is the same thing:

```lua
{ "reklai/colorrex.nvim", lazy = false, priority = 1000, opts = {} }
```

With [LazyVim](https://github.com/LazyVim/LazyVim), also tell it which colorscheme
to use, or it applies its own afterwards:

```lua
-- lua/plugins/colorrex.lua
return {
  { "reklai/colorrex.nvim" },
  { "LazyVim/LazyVim", opts = { colorscheme = "colorrex" } },
}
```

With Neovim's built-in plugin manager:

```lua
vim.pack.add({ "https://github.com/reklai/colorrex.nvim" })
vim.cmd.colorscheme("colorrex")
```

Lualine follows along with `theme = "colorrex"`.

Run `:checkhealth colorrex` to confirm it. In a terminal that does not report its
colors, colorrex stays grey and says so once at startup.

## Options

All optional. In a lazy.nvim spec, pass them as `opts`. Otherwise call `setup`,
which also turns the colorscheme on:

```lua
require("colorrex").setup({
  transparent = true, -- leave the background to the terminal
  contrast = 3.0,     -- minimum contrast for code, up to 4.5
  force_unique = false, -- make nearly identical themes look different
  auto = true,        -- also sync on focus and dark/light changes
})
```

With `force_unique = true`, each theme speaks in its own voice. If the theme gave its
cursor a color of its own, that color takes the keywords, and the other roles follow
one of six arrangements modeled on themes people recognize. It is colorrex's own rule,
not what the theme's author meant, so a theme with a known look elsewhere loses it.
Themes whose palettes and cursors nearly match stay alike. `:ColorRex status` names
the voice, and `:ColorRex check` says why it was chosen.

## How it works

Like libghostty, the part that does the work knows nothing about its host. Only
`lua/colorrex/neovim.lua` has side effects; the compiler and the terminal
protocol run under plain LuaJIT. See [docs/architecture.md](docs/architecture.md)
for the map and the vocabulary, and [docs/sync.md](docs/sync.md) for the exact
sequence and its known gaps.

```sh
make test     # everything but real terminals
make e2e      # real Neovim in real Rex blocks and Ghostty windows
make matrix   # all of it, against Neovim 0.11.7, 0.12.0, stable and nightly
```
