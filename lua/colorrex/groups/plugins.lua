-- Plugins, only where their own defaults would not already follow the other groups.
-- None of these is a dependency: a group nobody uses is inert.
return function(define)
  local base, link, syn, each = define.base, define.link, define.syn, define.each
  local G = {}

  G.TelescopeNormal = { fg = "fg", bg = base }
  G.TelescopeBorder = { fg = "border_strong", bg = base }
  G.TelescopeTitle = { fg = "accent", bold = true }
  -- A picker's chosen row is the item Enter acts on, as in the completion menu.
  G.TelescopeSelection = { bg = "accent_soft", bold = true }
  G.TelescopeSelectionCaret = { fg = "select_accent", bg = "accent_soft", bold = true }
  G.TelescopeMatching = { fg = "select_accent", bold = true }
  G.TelescopePromptPrefix = { fg = "accent" }
  G.BlinkCmpMenu = link("Pmenu")
  G.BlinkCmpMenuBorder = link("FloatBorder")
  G.BlinkCmpMenuSelection = { bg = "accent_soft", bold = true }
  G.BlinkCmpLabelMatch = { fg = "select_accent", bold = true }
  G.BlinkCmpLabelDeprecated = { strikethrough = true }
  G.BlinkCmpKind = { fg = "muted" }
  -- Ghost text: a suggestion, not code and not a comment (see ComplHint).
  G.BlinkCmpGhostText = link("ComplHint")
  G.CopilotSuggestion = link("ComplHint")
  G.CopilotAnnotation = link("ComplHintMore")
  G.BlinkCmpDoc = link("NormalFloat")
  G.BlinkCmpDocBorder = link("FloatBorder")
  G.BlinkCmpSignatureHelp = link("NormalFloat")
  G.BlinkCmpSignatureHelpBorder = link("FloatBorder")
  G.WhichKey = { fg = "accent" }
  G.WhichKeyGroup = syn("keyword")
  G.WhichKeyDesc = { fg = "fg" }
  G.WhichKeySeparator = { fg = "comment" }
  G.WhichKeyNormal = link("NormalFloat")
  G.TroubleNormal = { fg = "fg", bg = base }
  G.TroubleNormalNC = { fg = "fg", bg = base }
  G.TroubleCount = { fg = "accent" }
  G.OilDir = { fg = "func" }
  G.OilDirIcon = { fg = "func" }
  G.OilLink = { fg = "accent" }
  G.OilFile = { fg = "fg" }
  G.MiniIndentscopeSymbol = { fg = "border_strong", nocombine = true }
  G.MiniIndentscopeSymbolOff = { fg = "border_strong", nocombine = true }
  -- mini.jump2d draws its labels over code in fixed white on black, whatever the theme.
  G.MiniJump2dSpot = { fg = "on_accent", bg = "accent", bold = true, nocombine = true }
  G.MiniJump2dSpotUnique = { fg = "on_warn", bg = "warn", bold = true, nocombine = true }
  G.MiniJump2dSpotAhead = { fg = "fg", bg = "element", nocombine = true }
  G.FidgetTitle = { fg = "accent" }
  G.FidgetTask = { fg = "comment" }
  G.MasonHeader = { fg = "on_accent", bg = "accent", bold = true }
  G.MasonHighlight = { fg = "accent" }
  G.MasonHighlightBlock = { fg = "on_accent", bg = "accent" }
  G.MasonHighlightBlockBold = { fg = "on_accent", bg = "accent", bold = true }
  G.MasonMuted = { fg = "comment" }
  -- Mason's second color marks what has an update waiting. It ships as a fixed orange.
  G.MasonHeaderSecondary = { fg = "on_warn", bg = "warn", bold = true }
  G.MasonHighlightSecondary = { fg = "warn" }
  G.MasonHighlightBlockSecondary = { fg = "on_warn", bg = "warn" }
  G.MasonHighlightBlockBoldSecondary = { fg = "on_warn", bg = "warn", bold = true }
  G.MasonMutedBlock = { fg = "fg", bg = "subtle" }
  G.MasonMutedBlockBold = { fg = "fg", bg = "subtle", bold = true }
  -- rainbow-delimiters ships seven fixed colors. Depth is not a meaning, so these take
  -- the colors that keep their slot whatever the casting, and leave failure's alone.
  G.RainbowDelimiterRed = { fg = "special" }
  G.RainbowDelimiterOrange = { fg = "accent" }
  G.RainbowDelimiterYellow = { fg = "warn" }
  G.RainbowDelimiterGreen = { fg = "ok" }
  G.RainbowDelimiterCyan = { fg = "info" }
  G.RainbowDelimiterBlue = { fg = "hint" }
  G.RainbowDelimiterViolet = { fg = "preproc" }

  -- Snacks' GitHub views: the state of an issue or pull request, in GitHub's own colors.
  G.SnacksGhGreen = { fg = "ok" }
  G.SnacksGhRed = { fg = "error" }
  G.SnacksGhPurple = { fg = "preproc" }
  G.SnacksGhGray = { fg = "comment" }

  -- neo-tree links most of its groups to ones above. These it ships as fixed greys and
  -- oranges, whatever the theme.
  G.NeoTreeDotfile = { fg = "comment" }
  G.NeoTreeFadeText1 = { fg = "comment" }
  G.NeoTreeFadeText2 = { fg = "border_strong" }
  G.NeoTreeModified = { fg = "warn" }
  G.NeoTreeGitConflict = { fg = "error", bold = true, italic = true }
  G.NeoTreeGitUntracked = { fg = "warn", italic = true }
  G.NeoTreeTabInactive = { fg = "muted", bg = "cursorline" }
  G.NeoTreeTabSeparatorActive = { fg = "border" }
  G.NeoTreeTabSeparatorInactive = link("NeoTreeTabInactive")
  G.NvimTreeFolderIcon = { fg = "func" }
  G.NvimTreeWindowPicker = { fg = "on_accent", bg = "accent", bold = true }

  -- fzf-lua names colors from Neovim's color map for what fzf itself draws.
  G.FzfLuaHeaderBind = { fg = "accent" }
  G.FzfLuaHeaderText = { fg = "comment" }
  G.FzfLuaPathLineNr = { fg = "ok" }
  G.FzfLuaPathColNr = { fg = "info" }
  each(G, { "FzfLuaLivePrompt", "FzfLuaLiveSym" }, { fg = "accent" })
  G.FzfLuaBufNr = { fg = "warn" }
  G.FzfLuaBufFlagCur = { fg = "special" }
  G.FzfLuaBufFlagAlt = { fg = "info" }
  G.FzfLuaTabTitle = { fg = "info", bold = true }
  G.FzfLuaTabMarker = { fg = "ok", bold = true }
  G.fzf1 = { fg = "float_error", bg = "element" }
  G.fzf2 = { fg = "float_ok", bg = "element" }
  G.fzf3 = { fg = "fg", bg = "element" }

  -- todo-comments fills a keyword with its color and picks the text from Normal, black
  -- or white when Normal has no background, as it has none when transparent.
  G.TodoBgFIX = { fg = "on_error", bg = "error", bold = true }
  each(G, { "TodoBgHACK", "TodoBgWARN" }, { fg = "on_warn", bg = "warn", bold = true })
  G.TodoBgTODO = { fg = "on_info", bg = "info", bold = true }
  G.TodoBgNOTE = { fg = "on_hint", bg = "hint", bold = true }
  each(G, { "TodoBgPERF", "TodoBgTEST" }, { fg = "base", bg = "fg", bold = true })
  G.LazyH1 = { fg = "on_accent", bg = "accent", bold = true }
  G.LazyButton = { fg = "fg", bg = "element" }
  G.LazyButtonActive = { fg = "on_accent", bg = "accent" }
  G.LazySpecial = { fg = "accent" }
  -- Never drawn: nvim-notify fades a notification toward this. It reads Normal's
  -- background by default, which a transparent theme leaves unset, so it warns on
  -- screen and fades toward black. This keeps the theme's own background even then.
  G.NotifyBackground = { bg = "base" }
  -- nvim-notify ships fixed colors for each level, the same in every theme. These
  -- are the roles diagnostics use, so a level reads the same wherever it appears.
  for level, role in pairs({ ERROR = "error", WARN = "warn", INFO = "info", DEBUG = "comment", TRACE = "hint" }) do
    G["Notify" .. level .. "Border"] = { fg = role }
    G["Notify" .. level .. "Icon"] = { fg = role }
    G["Notify" .. level .. "Title"] = { fg = role }
  end
  G.GitSignsAdd = { fg = "ok" }
  G.GitSignsChange = { fg = "warn" }
  G.GitSignsDelete = { fg = "error" }
  -- The changed words in a hunk preview. gitsigns falls back to TermCursor for these,
  -- which is drawn in reverse, so a preview showed inverted blocks.
  each(G, { "GitSignsAddInline", "GitSignsChangeInline", "GitSignsDeleteInline" }, link("DiffText"))

  return G
end
