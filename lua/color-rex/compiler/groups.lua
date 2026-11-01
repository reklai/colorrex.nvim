-- Highlight groups, written in terms of roles.
--
-- There is not one hex literal in this file, and test/architecture enforces
-- that. A group can only name a role, so no group can drift away from the
-- theme. Colors here are role names; the compiler resolves them.
local M = {}

function M.build(opts, styles)
  local base = (not opts.transparent) and "base" or nil
  local G = {}

  local function syn(role, extra)
    local style = styles[role] or {}
    local spec = { fg = role, bold = style.bold, italic = style.italic, underline = style.underline }
    for key, value in pairs(extra or {}) do
      spec[key] = value
    end
    return spec
  end
  local function link(to)
    return { link = to }
  end
  local function set(names, spec)
    for _, name in ipairs(names) do
      G[name] = spec
    end
  end

  -- Editor --------------------------------------------------------------------
  G.Normal = { fg = "fg", bg = base }
  G.NormalNC = { fg = "fg", bg = base }
  G.NormalFloat = { fg = "fg", bg = "element" }
  G.NormalSB = { fg = "fg", bg = base }
  G.FloatBorder = { fg = "border_strong", bg = "element" }
  G.FloatTitle = { fg = "accent", bg = "element", bold = true }
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
  G.SignColumnSB = link("SignColumn")
  G.FoldColumn = { fg = "comment", bg = base }
  G.Folded = { fg = "muted", bg = "element" }
  G.Directory = { fg = "func" }
  G.EndOfBuffer = { fg = "border" }
  G.NonText = { fg = "border_strong" }
  G.SpecialKey = { fg = "border_strong" }
  G.Whitespace = { fg = "border" }
  G.WinSeparator = { fg = "border", bg = base }
  G.VertSplit = link("WinSeparator")
  G.MatchParen = { fg = "accent", bold = true }
  G.Title = { fg = "accent", bold = true }
  G.Visual = { bg = "visual" }
  G.VisualNOS = { bg = "visual" }
  G.QuickFixLine = { bg = "visual", bold = true }
  G.Search = { fg = "fg", bg = "search" }
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
  G.PmenuMatch = { fg = "accent", bg = "element", bold = true }
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
  G.DiffDelete = { fg = "error", bg = "diff_delete" }
  G.DiffText = { bg = "diff_text" }
  G.DiffTextAdd = link("DiffText")
  G.Added = { fg = "ok" }
  G.Changed = { fg = "warn" }
  G.Removed = { fg = "error" }

  -- Spelling ------------------------------------------------------------------
  G.SpellBad = { sp = "error", undercurl = true }
  G.SpellCap = { sp = "warn", undercurl = true }
  G.SpellLocal = { sp = "info", undercurl = true }
  G.SpellRare = { sp = "keyword", undercurl = true }

  -- Syntax --------------------------------------------------------------------
  G.Comment = { fg = "comment", italic = true }
  G.SpecialComment = { fg = "accent" }
  G.Todo = { fg = "on_warn", bg = "warn", bold = true }
  G.Constant = { fg = "constant" }
  set({ "Number", "Boolean", "Float" }, syn("number"))
  set({ "String", "Character" }, syn("string"))
  G.Identifier = { fg = "fg" }
  G.Function = syn("func")
  G.Statement = syn("keyword")
  set({ "Conditional", "Repeat", "Label", "Keyword", "Exception", "StorageClass" }, syn("keyword"))
  set({ "PreProc", "Include", "Define", "Macro", "PreCondit" }, { fg = "preproc" })
  set({ "Type", "Structure", "Typedef" }, syn("type"))
  G.Operator = syn("operator")
  G.Special = syn("operator")
  G.SpecialChar = syn("operator")
  G.Tag = syn("special")
  G.Delimiter = { fg = "muted" }
  G.Debug = { fg = "warn" }
  G.Underlined = { underline = true }
  G.Ignore = { fg = "border" }
  G.Error = { fg = "error" }

  -- Treesitter ----------------------------------------------------------------
  G["@variable"] = { fg = "fg" }
  G["@variable.builtin"] = { fg = "special" }
  G["@variable.parameter"] = { fg = "muted" }
  G["@variable.parameter.builtin"] = { fg = "special" }
  G["@variable.member"] = { fg = "fg" }
  G["@constant"] = { fg = "constant" }
  G["@constant.builtin"] = { fg = "special" }
  G["@constant.macro"] = { fg = "preproc" }
  G["@module"] = syn("type")
  G["@module.builtin"] = { fg = "special" }
  G["@label"] = syn("keyword")
  G["@string"] = syn("string")
  G["@string.documentation"] = { fg = "comment" }
  set({ "@string.regexp", "@string.escape", "@string.special", "@string.special.symbol" }, syn("operator"))
  G["@string.special.path"] = { fg = "func" }
  G["@string.special.url"] = { fg = "accent", underline = true }
  G["@character"] = syn("string")
  G["@character.special"] = syn("operator")
  set({ "@boolean", "@number", "@number.float" }, syn("number"))
  set({ "@type", "@type.builtin", "@type.definition", "@attribute" }, syn("type"))
  G["@attribute.builtin"] = { fg = "special" }
  G["@property"] = { fg = "fg" }
  set({ "@function", "@function.call", "@function.method", "@function.method.call" }, syn("func"))
  G["@function.builtin"] = { fg = "special" }
  G["@function.macro"] = { fg = "preproc" }
  G["@constructor"] = syn("type")
  G["@operator"] = syn("operator")
  set({
    "@keyword", "@keyword.coroutine", "@keyword.function", "@keyword.type", "@keyword.modifier",
    "@keyword.repeat", "@keyword.return", "@keyword.debug", "@keyword.exception",
    "@keyword.conditional",
  }, syn("keyword"))
  set({ "@keyword.directive", "@keyword.directive.define", "@keyword.import" }, { fg = "preproc" })
  set({ "@keyword.operator", "@keyword.conditional.ternary" }, syn("operator"))
  set({ "@punctuation.delimiter", "@punctuation.bracket" }, { fg = "muted" })
  G["@punctuation.special"] = syn("operator")
  G["@comment"] = link("Comment")
  G["@comment.documentation"] = link("Comment")
  G["@comment.error"] = { fg = "error", bold = true }
  G["@comment.warning"] = { fg = "warn", bold = true }
  G["@comment.todo"] = link("Todo")
  G["@comment.note"] = { fg = "info", bold = true }
  G["@tag"] = syn("special")
  G["@tag.builtin"] = syn("special")
  G["@tag.attribute"] = syn("type")
  G["@tag.delimiter"] = { fg = "muted" }
  G["@diff.plus"] = link("Added")
  G["@diff.minus"] = link("Removed")
  G["@diff.delta"] = link("Changed")
  G["@markup.strong"] = { bold = true }
  G["@markup.italic"] = { italic = true }
  G["@markup.strikethrough"] = { strikethrough = true }
  G["@markup.underline"] = { underline = true }
  G["@markup.heading"] = { fg = "accent", bold = true }
  for level = 1, 6 do
    G["@markup.heading." .. level] = link("@markup.heading")
  end
  G["@markup.quote"] = { fg = "muted", italic = true }
  G["@markup.math"] = syn("operator")
  G["@markup.link"] = { fg = "accent" }
  G["@markup.link.label"] = { fg = "accent" }
  G["@markup.link.url"] = { fg = "accent", underline = true }
  G["@markup.raw"] = syn("string")
  G["@markup.raw.block"] = syn("string")
  G["@markup.list"] = syn("operator")
  G["@markup.list.checked"] = { fg = "ok" }
  G["@markup.list.unchecked"] = { fg = "muted" }

  -- LSP -----------------------------------------------------------------------
  set({ "LspReferenceText", "LspReferenceRead", "LspReferenceTarget" }, { bg = "subtle" })
  G.LspReferenceWrite = { bg = "subtle", underline = true }
  G.LspInlayHint = { fg = "comment" }
  G.LspCodeLens = { fg = "comment" }
  G.LspCodeLensSeparator = { fg = "border" }
  G.LspSignatureActiveParameter = { fg = "accent", bold = true }
  G["@lsp.type.keyword"] = syn("keyword")
  G["@lsp.type.modifier"] = syn("keyword")
  set({ "@lsp.type.function", "@lsp.type.method" }, syn("func"))
  G["@lsp.type.macro"] = { fg = "preproc" }
  G["@lsp.type.decorator"] = syn("type")
  set({
    "@lsp.type.type", "@lsp.type.class", "@lsp.type.struct", "@lsp.type.enum",
    "@lsp.type.interface", "@lsp.type.namespace", "@lsp.type.typeParameter",
  }, syn("type"))
  set({ "@lsp.type.parameter" }, { fg = "muted" })
  set({ "@lsp.type.property", "@lsp.type.variable" }, { fg = "fg" })
  G["@lsp.type.enumMember"] = syn("number")
  G["@lsp.type.string"] = syn("string")
  G["@lsp.type.number"] = syn("number")
  G["@lsp.type.operator"] = syn("operator")
  G["@lsp.type.comment"] = link("Comment")
  G["@lsp.mod.deprecated"] = { strikethrough = true }

  -- Diagnostics ---------------------------------------------------------------
  for name, role in pairs({ Error = "error", Warn = "warn", Info = "info", Hint = "hint", Ok = "ok" }) do
    G["Diagnostic" .. name] = { fg = role }
    G["DiagnosticVirtualText" .. name] = { fg = role }
    G["DiagnosticVirtualLines" .. name] = { fg = role }
    G["DiagnosticSign" .. name] = { fg = role }
    G["DiagnosticFloating" .. name] = { fg = role, bg = "element" }
    G["DiagnosticUnderline" .. name] = { sp = role, undercurl = true }
  end
  G.DiagnosticUnnecessary = { fg = "comment" }
  G.DiagnosticDeprecated = { strikethrough = true }

  -- Plugins: only where a plugin's own defaults would not already follow the
  -- groups above. None of these is a dependency; a group nobody uses is inert.
  G.TelescopeNormal = { fg = "fg", bg = base }
  G.TelescopeBorder = { fg = "border_strong", bg = base }
  G.TelescopeTitle = { fg = "accent", bold = true }
  G.TelescopeSelection = { bg = "visual" }
  G.TelescopeMatching = { fg = "accent", bold = true }
  G.TelescopePromptPrefix = { fg = "accent" }
  G.BlinkCmpMenu = link("Pmenu")
  G.BlinkCmpMenuBorder = link("FloatBorder")
  G.BlinkCmpMenuSelection = { bg = "visual" }
  G.BlinkCmpLabelMatch = { fg = "accent", bold = true }
  G.BlinkCmpLabelDeprecated = { strikethrough = true }
  G.BlinkCmpKind = { fg = "muted" }
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
  G.FidgetTitle = { fg = "accent" }
  G.FidgetTask = { fg = "comment" }
  G.MasonHeader = { fg = "on_accent", bg = "accent", bold = true }
  G.MasonHighlight = { fg = "accent" }
  G.MasonHighlightBlock = { fg = "on_accent", bg = "accent" }
  G.MasonHighlightBlockBold = { fg = "on_accent", bg = "accent", bold = true }
  G.MasonMuted = { fg = "comment" }
  G.LazyH1 = { fg = "on_accent", bg = "accent", bold = true }
  G.LazyButton = { fg = "fg", bg = "element" }
  G.LazyButtonActive = { fg = "on_accent", bg = "accent" }
  G.LazySpecial = { fg = "accent" }
  G.GitSignsAdd = { fg = "ok" }
  G.GitSignsChange = { fg = "warn" }
  G.GitSignsDelete = { fg = "error" }

  return G
end

return M
