-- The editor itself: windows, messages, bars, menus, diffs and spelling.
return function(define)
  local base, link = define.base, define.link
  local G = {}

  -- Editor --------------------------------------------------------------------
  G.Normal = { fg = "fg", bg = base }
  G.NormalNC = { fg = "fg", bg = base }
  G.NormalFloat = { fg = "fg", bg = "element" }
  G.FloatBorder = { fg = "border_strong", bg = "element" }
  G.FloatTitle = { fg = "float_accent", bg = "element", bold = true }
  G.FloatFooter = { fg = "muted", bg = "element" }
  G.FloatShadow = { bg = "border" }
  G.FloatShadowThrough = { bg = "subtle" }
  G.ColorColumn = { bg = "cursorline" }
  G.Conceal = { fg = "muted" }
  G.Cursor = { fg = "base", bg = "fg" }
  G.lCursor = link("Cursor")
  G.CursorIM = link("Cursor")
  G.TermCursor = { reverse = true }
  G.CursorColumn = { bg = "cursorline" }
  G.CursorLine = { bg = "cursorline" }
  G.CursorLineNr = { fg = "fg", bold = true }
  G.CursorLineFold = { fg = "muted", bg = "cursorline" }
  G.CursorLineSign = { bg = "cursorline" }
  -- Where a debugger has stopped the program. nvim-dap draws the line with this, which
  -- only Neovim's termdebug defines, so it showed nothing. The program is here, which
  -- is not where your cursor is.
  G.debugPC = { bg = "stopped" }
  G.LineNr = { fg = "comment" }
  G.LineNrAbove = link("LineNr")
  G.LineNrBelow = link("LineNr")
  G.SignColumn = { fg = "comment", bg = base }
  G.FoldColumn = { fg = "comment", bg = base }
  G.Folded = { fg = "muted", bg = "element" }
  G.Directory = { fg = "func" }
  G.EndOfBuffer = { fg = "border" }
  G.NonText = { fg = "border_strong" }
  G.SpecialKey = { fg = "border_strong" }
  G.Whitespace = { fg = "border" }
  G.WinSeparator = { fg = "border", bg = base }
  G.MatchParen = { fg = "accent", bold = true }
  G.ColorRexLandmark = { fg = "landmark", bold = true }
  G.Title = { fg = "accent", bold = true }
  G.Visual = { bg = "visual" }
  G.VisualNOS = { bg = "visual" }
  -- The item Enter acts on, in every list: completion, pickers, quickfix and the
  -- wildmenu, in the same accent as a snippet's next stop. A text selection is
  -- something else, and keeps `visual`; the cursor line only says where you are.
  G.QuickFixLine = { bg = "accent_soft", bold = true }
  G.Search = { fg = "on_search", bg = "search" }
  G.IncSearch = { fg = "on_accent", bg = "accent" }
  G.CurSearch = { fg = "on_accent", bg = "accent", bold = true }
  G.Substitute = { fg = "on_error", bg = "error" }
  G.WildMenu = { fg = "fg", bg = "accent_soft", bold = true }

  -- Messages ------------------------------------------------------------------
  G.MsgArea = { fg = "fg" }
  G.MsgSeparator = { fg = "border", bg = "statusline" }
  G.ModeMsg = { fg = "fg", bold = true }
  G.MoreMsg = { fg = "info" }
  G.Question = { fg = "info" }
  G.ErrorMsg = { fg = "error" }
  G.WarningMsg = { fg = "warn" }
  G.OkMsg = { fg = "ok" }
  G.StderrMsg = link("ErrorMsg")
  G.StdoutMsg = { fg = "fg" }

  -- Bars ----------------------------------------------------------------------
  G.StatusLine = { fg = "fg", bg = "statusline" }
  G.StatusLineNC = { fg = "muted", bg = "cursorline" }
  G.StatusLineTerm = link("StatusLine")
  G.StatusLineTermNC = link("StatusLineNC")
  G.TabLine = { fg = "muted", bg = "cursorline" }
  G.TabLineFill = { bg = "cursorline" }
  G.TabLineSel = { fg = "on_accent", bg = "accent", bold = true }
  G.WinBar = { fg = "fg", bg = "element" }
  G.WinBarNC = { fg = "muted", bg = "cursorline" }

  -- Popup menu ----------------------------------------------------------------
  G.Pmenu = { fg = "fg", bg = "element" }
  G.PmenuSel = { fg = "fg", bg = "accent_soft", bold = true }
  G.PmenuKind = { fg = "muted", bg = "element" }
  G.PmenuKindSel = { fg = "fg", bg = "accent_soft" }
  G.PmenuExtra = { fg = "muted", bg = "element" }
  G.PmenuExtraSel = { fg = "fg", bg = "accent_soft" }
  G.PmenuSbar = { bg = "subtle" }
  G.PmenuThumb = { bg = "border_strong" }
  G.PmenuMatch = { fg = "float_accent", bg = "element", bold = true }
  G.PmenuMatchSel = { fg = "select_accent", bg = "accent_soft", bold = true }
  G.PmenuBorder = link("FloatBorder")
  G.PmenuShadow = link("FloatShadow")
  G.PmenuShadowThrough = link("FloatShadowThrough")
  G.ComplMatchIns = { fg = "muted" }
  -- Text that is not in the file: a completion's suggestion, drawn ahead of the
  -- cursor. It is not a comment, so it does not look like one: a quiet accent, slanted.
  G.ComplHint = { fg = "predicted", italic = true }
  G.ComplHintMore = { fg = "comment" } -- a note on the suggestion, such as 1/3
  -- Text a completion put in the file that you have not accepted yet. It is real code,
  -- so it keeps its own colors, and is marked as not yet yours.
  G.PreInsert = { sp = "accent", underdotted = true }
  G.SnippetTabstop = { bg = "accent_soft" }
  G.SnippetTabstopActive = { bg = "visual" }

  -- Diff ----------------------------------------------------------------------
  G.DiffAdd = { bg = "diff_add" }
  G.DiffChange = { bg = "diff_change" }
  G.DiffDelete = { fg = "diff_deleted", bg = "diff_delete" }
  -- The one diff surface that sets its text. The changed words are short and meant
  -- to stand out, and at this strength it would drown any syntax color on it.
  G.DiffText = { fg = "on_diff_text", bg = "diff_text" }
  G.DiffTextAdd = link("DiffText")
  G.Added = { fg = "ok" }
  G.Changed = { fg = "warn" }
  G.Removed = { fg = "error" }

  -- Spelling ------------------------------------------------------------------
  -- A misspelling is not an error in the code, so it is never a curl.
  G.SpellBad = { sp = "error", underdotted = true }
  G.SpellCap = { sp = "warn", underdotted = true }
  G.SpellLocal = { sp = "info", underdotted = true }
  G.SpellRare = { sp = "keyword", underdotted = true }

  return G
end
