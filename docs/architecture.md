# Architecture

The contributor's map. `test/architecture/test_boundaries.lua` pins the exact
dependency graph; where this file and that test disagree, the test wins.

## Scope

color-rex is for libghostty terminals, such as Ghostty and Rex. It relies on how
they behave and carries no code for any other terminal. A terminal that does not
behave this way is simply not supported.

## The map

```text
lazy.lua                    what lazy.nvim needs to install it in one line
colors/color-rex.lua        :colorscheme color-rex
plugin/color-rex.lua        :ColorRex and its <Plug> mappings
lua/lualine/themes/         found by lualine, by name
lua/color-rex.lua           the public API; owns one App
lua/color-rex/
  app.lua                   when colors change
  commands.lua              the catalog behind :ColorRex and <Plug>
  config.lua                options, and the one name
  neovim.lua                every side effect
  health.lua                :checkhealth
  terminal.lua              asks the terminal for its colors
  terminal/protocol.lua       what those bytes mean
  theme.lua                 the theme format, read and written
  compiler.lua              a theme to a colorscheme
  compiler/solver.lua         colors to roles
  compiler/casting.lua        which color plays which role
  compiler/groups.lua         roles to highlight groups
  compiler/lualine.lua        roles to a lualine theme
  compiler/promises.lua       the promises, as checks
  compiler/standalone.lua     a colorscheme to a Lua file
  color.lua                 color math
```

One rule explains the shape: **`x.lua` is the public face of `x/`.** Nothing
outside `compiler/` may require a module inside it. Everything else is a single
file because it is a single thing.

## The rules

1. **Only `neovim.lua` has effects.** It and the two thin Neovim entry points
   (`color-rex.lua`, `health.lua`) are the only modules that mention `vim`, `io`
   or `os`. Everything else runs under plain LuaJIT.
2. **`App` reaches the world through an injected host.** That host is
   `neovim.lua`, or a fake with a hand-cranked clock in tests. This is Ghostty's
   separation of its core from its apprt.
3. **Every edge is on the map.** A new `require` between modules must be added to
   the graph in `test_boundaries.lua`, on purpose.
4. **Zero dependencies.** No `require` leaves the plugin. Lualine support is a
   file lualine finds by name; nothing here requires lualine.
5. **`compiler/groups.lua` and `compiler/lualine.lua` hold no colors.** They name
   roles, so no group can drift from the theme.

## Vocabulary

Use these words, in code and in prose.

| Word | Means |
| --- | --- |
| theme | What a source can say about colors. May be incomplete. |
| filled theme | A theme with every gap filled in. |
| completeness | How much of a theme is present: `full`, `partial` or `none`. |
| role | What a color means in an editor: `keyword`, `error`, `accent`. |
| fingerprint | A number computed from a theme. The id is its short form. |
| casting | Which of a theme's colors plays which role. |
| group spec | A highlight group written in roles. |
| colorscheme | The compiler's output, everything needed to paint. |
| query | One request to the terminal. `terminal.query()` starts one. |
| settle | A query ends: with the reply, or at the timeout. |
| outcome | How a query settled: `reply`, `timeout`, `late reply`. |
| reason | What started a sync: `launch`, `focus`, `manual`, `retry`, `broadcast`. |
| broadcast | Another Neovim saving a theme, heard through the state file. |
| sync | Run a query and repaint if the theme changed. |
| repaint | Apply a colorscheme through `:colorscheme`. |
| render | The host setting the highlights. |
| note | A record of an adjustment the solver made. |
| message | Text shown to the user through the host. |
| host | The object `App` does everything through. |

## Decisions worth knowing

**Nothing caches compiled output.** Compiling is fast enough that a cache of it
would save nothing worth a second code path. The cache is just the last theme,
as a Ghostty theme file, so it is never executed.

**One request, one reply.** OSC 21 returns all 19 colors in a single sequence,
so a read is atomic and a theme cannot change halfway through one. A color with
no value comes back empty, which is how Rex says a block has no theme yet. This
is the kitty color protocol, and depending on it is what scoping to libghostty
buys: it replaced 19 separate queries, a sentinel and a grace timer. It is a
contract, not an accident: Ghostty lists it among its [external protocols] and
treats any deviation from the spec as a bug.

[external protocols]: https://ghostty.org/docs/vt/external

**Every theme gets its own casting.** A faithful compiler turns nearly identical
palettes into nearly identical colors, so no amount of color work can separate
them: 155 of Ghostty's 819 themes read as a twin of another in code, and most of
those differ only in their background. No terminal theme says which color is a
keyword, so that is where themes can differ. A fingerprint picks one of 60
arrangements, at least 3 roles apart, and only moves colors between roles. Each
compile sees one theme, so two themes can still draw the same arrangement: this
cuts lookalikes, it cannot eliminate them, and the conformance suite bounds them.
The cost is that editing one color of a theme can reshuffle its casting.

**The state file doubles as a signal.** This idea is from `tinted-osc-colors.nvim`.
One Neovim noticing a change is enough for all of them to check, and because the
watcher is an event, it costs nothing idle. Unlike that plugin, a Neovim here
treats the file as a nudge and asks its own terminal, since Rex blocks can differ.

**Partial answers are kept.** This is from OpenTUI's palette detector: settle
with what arrived rather than all or nothing.

**Repainting goes through `:colorscheme`,** deferred out of `TermResponse`, where
autocommands do not nest. That is what makes ColorScheme fire, and so what makes
lualine and every plugin that derives from highlights follow along.

**No polling, and no data connection.** Polling would run forever to catch
something rare. Rex's data connection does push theme changes, but it is the
wrong trade for a colorscheme; see "Current Gaps" in `docs/sync.md`. `:ColorRex`
is honest and costs nothing idle.

## Tests, by what a failure means

| Suite | Runs under | A failure means |
| --- | --- | --- |
| `unit` | LuaJIT | A logic bug |
| `conformance` | LuaJIT | A promise broke for a real theme |
| `fault` | LuaJIT | Hostile input broke an invariant |
| `architecture` | LuaJIT | A boundary was crossed |
| `integration` | Neovim | The wiring into Neovim broke |
| `e2e` | Neovim in Rex and Ghostty | It does not work on a real terminal |

`make matrix` runs the Neovim suites against every supported version, plus one
below the floor, which has to refuse cleanly.

The Rex suite verifies each theme change took effect before judging Neovim. A
test that never changed the theme proves nothing.
