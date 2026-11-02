# Sync Spec

What happens between a theme existing in your terminal and it being on screen.

1. `:colorscheme colorrex` runs `colors/colorrex.lua`, which calls `App:load()`.

2. `App:seed()` reads the last theme from `stdpath("state")/colorrex/theme`. A
   complete cached theme is compiled and used. Otherwise a neutral grey theme is,
   so a failed query looks unthemed rather than plausibly themed.

3. The colorscheme is painted at once. The first frame never waits on the terminal.

4. `App:attach()` creates the `terminal` machine and subscribes to `TermResponse`,
   `FocusGained`, `VimResume`, `UIEnter`, `ColorScheme` and `VimLeavePre`, and to
   changes to the saved theme.

5. When a terminal UI is ready, `App:sync("launch")` starts a query. During
   startup that is `UIEnter`. With no terminal attached, nothing is sent.

6. The query writes one OSC 21 request for all 19 colors: foreground, background,
   cursor and ANSI 0 through 15.

7. The reply arrives in one piece through `TermResponse`, about 320 bytes, and
   the query settles. A color with no value comes back empty (`foreground=`).
   With no reply it settles empty after 500ms. A reply that comes later still
   applies when it arrives. If nothing has answered 2 seconds after that, the
   user is told, once, in a line short enough not to stop at a hit-enter prompt.
   A UI with no terminal at all is told straight away.

8. A sync requested during a query discards that query and runs one more,
   however many were requested. Focus events arrive in pairs.

9. The result is graded for completeness: `full` is foreground, background and
   16 ANSI colors; `none` is nothing; anything else is `partial`.

10. A `full` theme is compiled. If it differs from the current colorscheme, the
    theme is saved and repainted through `:colorscheme`.

11. A `partial` theme is shown only if nothing complete is held. It never
    replaces a complete theme, because a Rex block with no theme yet is the
    usual source, and the theme we hold is the better guess.

12. A `partial` result is retried after 250ms, 1s and 3s, then no more. A Rex
    block usually gets its theme within 150ms. A `full` result ends the retries.

13. After that there are no timers and no queries. Nothing runs until one of:

    | Trigger | Applies when |
    | --- | --- |
    | `:ColorRex`, or any key mapped to it | Always |
    | `FocusGained` or `VimResume` | `auto` is on |
    | Another Neovim on this machine saving a new theme | `auto` is on |
    | An OSC 11 reply, which means the terminal reported a change | `auto` is on |
    | Neovim re-sourcing `colors/colorrex.lua` with `'background'` flipped | `auto` is on |

## Between Neovims

Whichever Neovim sees a theme change first saves it to the state file, and every
other Neovim is watching that file. This is what reaches a Neovim with no focus
event coming: press the sync key in one, and the rest follow.

The file is only a nudge. A Neovim that hears it asks its own terminal, because
each Rex block can show a different theme, and it stays on the theme its terminal
reports. Three rules keep this from becoming a loop: a Neovim writes only when its
own terminal changed, it never rewrites identical text, and a file that already
matches what it shows costs no query.

## Dark and light

Libghostty reports a change through mode 2031. Neovim consumes the report itself
and sends OSC 11, so all a plugin ever sees is the OSC 11 reply. colorrex never
sends OSC 11, so any such reply means the terminal reported something, and it
syncs. Values are not compared: Ghostty reports every config reload, and a new
palette on the same background has to get through. A query never causes one of
these replies, so this cannot loop.

The two terminals differ in when they report:

| | Rex | Ghostty |
| --- | --- | --- |
| Dark to light, either way | Reported | Reported |
| Same brightness | Not reported | Reported, on config reload |

Ghostty's report on reload is deliberate. Its source says: "The config could have
changed any of our colors so update mode 2031." Its report can say light on a dark
theme, which does not matter: colorrex reads the background from the theme.

By the mode 2031 spec, a program changing colors with OSC 10, 11 or 12 is not
reported, in either terminal.

Neovim also flips `'background'` and re-sources the colorscheme. Painting then
would force `'background'` straight back, so `App:load()` syncs instead. With
`auto` off, or with no terminal to ask, it repaints the current colors instead, and
always from outside the option handler: setting the option back from inside it
makes Neovim abandon the colorscheme.

Both paths are needed. A user who sets `'background'` makes Neovim delete its
detection, which leaves only the first. Both are covered in `test/e2e/rex.lua`.

## Current Gaps

- **In Rex, same-brightness theme changes are not live.** A program in a block
  hears nothing when a theme changes and the scheme does not: no mode 2031,
  nothing on `rex events`, no session revision. They apply on the next focus
  change or `:ColorRex`. Ghostty has no such gap.

  Rex's data connection does push them. `data.connect` on a block streams its
  output, with an APC `rex1` message of type `theme` on each change. This was
  tested with `set_theme`, not the app. It is deliberately not used:
  - A reader that stops draining stalled the block's program for 17.9 seconds.
    In that block the program is Neovim, so a bug here would freeze the editor.
  - The stream mirrors all of the block's output, so Neovim would be reading
    everything it just drew, for as long as it runs.
  - It needs a WebSocket client written by hand on `vim.uv`, for Rex alone. It
    is described by the server's `/llms.txt`, not by the public docs.

  The real fix belongs in Rex and is small. libghostty leaves unsolicited reports
  to its host ("Hosts should gate unsolicited sends on mode 2031"), and Rex already
  links `ghostty_color_scheme_report_encode`. If `set_theme` sent that report when
  it applies, as Ghostty does on reload, colorrex would need no change at all.

- **A lone unfocused Neovim has no focus event coming.** Rex's theme picker
  produced a focus event for the focused pane within 270ms in 12 of 14 observed
  changes. The other 2, while Neovim was not focused, took 6 to 8 seconds. Another
  Neovim noticing now covers this, but with none open it still waits.

- **The nudge stops at the machine.** Neovims on different hosts have separate
  state files, so an SSH session does not hear about a local sync.

- **Selection colors are not available.** The kitty spec defines them, but neither
  Rex nor Ghostty answers them, so `Visual` is always derived.

- **Ghostty's `minimum-contrast` overrides colorrex.** If it is set, Ghostty
  adjusts text colors as it draws, so the screen can differ from `:ColorRex explain`.

- **Ghostty's `osc-color-report-format = none` hides reloads.** OSC 21 still
  answers, so launching and syncing work. Neovim's OSC 11 does not, so the report
  of a change never reaches a plugin, and a reload applies on the next focus
  change or `:ColorRex`, as a same-brightness change does in Rex.

- **Changing themes through a keybind or automatic dark mode is untested.** Only
  the Rex theme picker and `set_theme` have been observed.

- **Latency over SSH is unmeasured.** A slow reply still applies when it arrives,
  but a manual sync would report that the terminal did not answer.

- **Contrast is measured against the background only.** A color on a tinted
  surface such as `Visual` is not separately held to the floor.
