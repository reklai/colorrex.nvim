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
  G.ColorRexLandmark = { bold = true }
  G.Title = { fg = "accent", bold = true }
  G.Visual = { bg = "visual" }
  G.VisualNOS = { bg = "visual" }
  G.QuickFixLine = { bg = "visual", bold = true }
  G.Search = { fg = "on_search", bg = "search" }
  G.IncSearch = { fg = "on_accent", bg = "accent" }
  G.CurSearch = { fg = "on_accent", bg = "accent", bold = true }
  G.Substitute = { fg = "on_error", bg = "error" }
  G.WildMenu = { fg = "on_accent", bg = "accent" }

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
  G.PmenuSel = { fg = "on_accent", bg = "accent" }
  G.PmenuKind = { fg = "muted", bg = "element" }
  G.PmenuKindSel = { fg = "on_accent", bg = "accent" }
  G.PmenuExtra = { fg = "muted", bg = "element" }
  G.PmenuExtraSel = { fg = "on_accent", bg = "accent" }
  G.PmenuSbar = { bg = "subtle" }
  G.PmenuThumb = { bg = "border_strong" }
  G.PmenuMatch = { fg = "float_accent", bg = "element", bold = true }
  G.PmenuMatchSel = { fg = "on_accent", bg = "accent", bold = true }
  G.PmenuBorder = link("FloatBorder")
  G.PmenuShadow = link("FloatShadow")
  G.PmenuShadowThrough = link("FloatShadowThrough")
  G.ComplMatchIns = { fg = "muted" }
  G.PreInsert = { fg = "comment" }
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
  G.SpellBad = { sp = "error", undercurl = true }
  G.SpellCap = { sp = "warn", undercurl = true }
  G.SpellLocal = { sp = "info", undercurl = true }
  G.SpellRare = { sp = "keyword", undercurl = true }

  return G
end
