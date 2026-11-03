-- Plugins, only where their own defaults would not already follow the other groups.
-- None of these is a dependency: a group nobody uses is inert.
return function(define)
  local base, link, syn = define.base, define.link, define.syn
  local G = {}

  G.TelescopeNormal = { fg = "fg", bg = base }
  G.TelescopeBorder = { fg = "border_strong", bg = base }
  G.TelescopeTitle = { fg = "accent", bold = true }
  G.TelescopeSelection = { bg = "visual" }
  G.TelescopeMatching = { fg = "select_accent", bold = true }
  G.TelescopePromptPrefix = { fg = "accent" }
  G.BlinkCmpMenu = link("Pmenu")
  G.BlinkCmpMenuBorder = link("FloatBorder")
  G.BlinkCmpMenuSelection = { bg = "visual" }
  G.BlinkCmpLabelMatch = { fg = "select_accent", bold = true }
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
