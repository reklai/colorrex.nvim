# Architecture

The contributor's map. `test/architecture/test_boundaries.lua` pins the exact
dependency graph; where this file and that test disagree, the test wins.

## Scope

colorrex is for libghostty terminals, such as Ghostty and Rex. It relies on how
they behave and carries no code for any other terminal. A terminal that does not
behave this way is simply not supported.

## The map

```text
lazy.lua                    what lazy.nvim needs to install it in one line
colors/colorrex.lua        :colorscheme colorrex
plugin/colorrex.lua        :ColorRex and its <Plug> mappings
lua/lualine/themes/         found by lualine, by name
lua/colorrex.lua           the public API; owns one App
lua/colorrex/
  app.lua                   when colors change
  commands.lua              the catalog behind :ColorRex and <Plug>
  report.lua                what the commands say
  config.lua                options, and the one name
  neovim.lua                every side effect
  health.lua                :checkhealth
  terminal.lua              asks the terminal for its colors
  terminal/protocol.lua       what those bytes mean
  theme.lua                 the theme format, read and written
  roles.lua                 colors to meanings
  roles/casting.lua           which color plays which role
  groups.lua                meanings to highlight groups
  groups/                     one file per area of the editor
  lualine.lua               meanings to a lualine theme
  compiler.lua              runs the pipeline, theme to colorscheme
  compiler/promises.lua       the promises, as checks
  compiler/standalone.lua     a colorscheme to a Lua file
  color.lua                 color math
```

The pipeline reads in order: `theme`, `roles`, `groups`. One rule explains the
shape: **`x.lua` is the public face of `x/`.** Nothing outside `roles/` may require
a module inside it, and the same goes for `groups/`, `compiler/` and `terminal/`.
Everything else is a single file because it is a single thing.

To support a plugin, add its groups to `groups/plugins.lua`. A group defined in two
areas is refused at compile time.

## The rules

1. **Only `neovim.lua` has effects.** It and the two thin Neovim entry points
   (`colorrex.lua`, `health.lua`) are the only modules that mention `vim`, `io`
   or `os`. Everything else runs under plain LuaJIT.
2. **`App` reaches the world through an injected host.** That host is
   `neovim.lua`, or a fake with a hand-cranked clock in tests. This is Ghostty's
   separation of its core from its apprt.
3. **Every edge is on the map.** A new `require` between modules must be added to
   the graph in `test_boundaries.lua`, on purpose.
4. **Zero dependencies.** No `require` leaves the plugin. Lualine support is a
   file lualine finds by name; nothing here requires lualine.
5. **`groups/` and `lualine.lua` hold no colors.** They name roles, so no group
   can drift from the theme.

## Vocabulary

Use these words, in code and in prose.

| Word | Means |
| --- | --- |
| theme | What a source can say about colors. May be incomplete. |
| filled theme | A theme with every gap filled in. |
| completeness | How much of a theme is present: `full`, `partial` or `none`. |
| role | What a color means in an editor: `keyword`, `error`, `accent`. |
| fingerprint | A number computed from a theme. The id is its short form. |
| arrangement | One assignment of colors to roles. |
| casting | The arrangement a theme uses, by number. 1 is the ANSI convention. |
| voice | One of six named arrangements. `force_unique` picks one by the cursor's hue. |
| chunk | A node that starts its own line and runs five lines or more. |
| landmark | The name that opens a chunk in the outer two levels. Also the role it wears. |
| group spec | A highlight group written in roles. |
| colorscheme | The compiler's output, everything needed to paint. |
| query | One request to the terminal. `terminal.query()` starts one. |
| settle | A query ends: with the reply, or at the timeout. |
| attached | This colorscheme is active and listening. `App.terminal` exists exactly then. |
| outcome | How a query settled: `reply`, `late reply`, `timeout`, `send failed`. |
| reason | What started a sync: `launch`, `focus`, `resume`, `mode`, `background`, `manual`, `retry`, `broadcast`. |
| saved theme | The last complete theme, in the state directory. It is what the first frame shows. |
| broadcast | Another Neovim saving a theme, noticed by watching that file. |
| sync | Run a query and repaint if the theme changed. |
| repaint | Apply a colorscheme through `:colorscheme`. |
| render | The host setting the highlights. |
| note | A record of an adjustment made to a color or role. |
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

**Identity comes from the palette, not from a fingerprint.** A faithful compiler
turns nearly identical palettes into nearly identical colors, so separating such
themes takes something other than color. The obvious candidate is which role each
color plays, and for a while a fingerprint chose that. It worked by the numbers,
taking themes with an identical twin from 152 to 0, but it measured the wrong thing:
one invisible step of red in a background visibly recast 757 of 819 themes, and
every family of themes split apart. A fingerprint knows nothing about a theme, so
that was difference by noise.

So roles follow the ANSI convention, the closest thing a terminal theme has to its
author's intent, and move only for readability. The arrangements for that are the
even permutations of seven roles: 2,520, any two at least three roles apart by
construction, because differing in exactly two would be a single swap, which is odd.
The list is only built when a theme needs it.

**`force_unique` is a voice, not a hash.** Recognizable themes make one strong
decision, and most Rex themes have already made one: they gave the cursor a color of
its own. So the opt-in picks one of six named arrangements by the cursor's hue. It
keeps most of what made the fingerprint fail: an invisible change almost never
recasts a theme, and families stay together. The cost is that near-clones with matching
cursors stay alike. No rule can both respond smoothly and split palettes that are
nearly identical, so those differ in the accent and not in the code. The cursor does
not reveal what an author meant, and this rule does not claim to. Where a row would
cost a role its readability, the theme keeps the convention.

The promise is two-sided, and both sides are tests: a difference you can see must
show, and a difference you cannot see must not. Twins are not a failure when two
themes have the same colors. Most of Ghostty's 152 do, and differ in their background.
Terminal themes cannot say which color is a keyword, so an author's own mapping is
out of reach: TokyoNight's Neovim theme uses an orange for constants that is not in
its ANSI colors at all.

**Text is judged against what is behind it.** Every color is made readable on the
background, and most of the editor is not the background. A group that sets both its
text and its fill can simply be made to read: colored text is lifted against the float
it sits on, and `Search` and `DiffText` take whichever of fg or bg reads better, which
on a mid-tone theme is not always fg. Selections and whole-line diffs cannot, because
they lie under whatever syntax is there. So they ease off instead, until text reaches
2.5:1 and comments 2.25:1, and stop while they can still be seen: a selection you
cannot find is worse than one that is hard to read through. The floor is contrast with
the background and not a percentage, because the same percentage is a different
strength on every theme. `DiffText` sets its own text for a different reason. No
strength that still marks the changed words leaves a comment readable, and the
words are short and meant to stand out, so giving up their syntax color is the better
trade. Borders and separators are lines, not text, and are exempt.

**Shape comes from position, not kinds of token.** A chunk can start at a definition or
at a call, and which depends on the code: 37% of chunks in TypeScript source open with a
named definition against 10% in tests, where 56% open with a call like `describe(...)`.
So `chunks.lua` reads position in the tree, and asks only that a landmark has a name,
using the field names grammars share, which drops `if` and `for` with no list of
keywords. Limiting it to the outer two levels and five lines or more took landmarks from
14-19% of lines to 3-5% across TypeScript, TSX, Lua and Python. Fewer is the point:
color only says something when it is scarce. This cannot live in highlight groups,
because a group cannot know a token's position, so the host draws ephemeral marks during
redraw, on the rows on screen, from the tree Treesitter already parsed.

Shape is the same in every theme, and voice is not. The rule for where landmarks go is
fixed, and what fills them is the theme's own cursor color, so structure does not make
themes more alike. Landmarks need no role moved, which is why themes with a look of
their own elsewhere keep it, where `force_unique` does not.

**The saved theme doubles as a signal.** This idea is from `tinted-osc-colors.nvim`.
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
