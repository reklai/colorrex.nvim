-- The themes both real-terminal suites switch between.
local function theme(fg, bg, cursor, ansi)
  return { fg = fg, bg = bg, cursor = cursor, ansi = ansi }
end

return {
  dracula = theme("#f8f8f2", "#282a36", "#ff79c6", {
    "#21222c", "#ff5555", "#50fa7b", "#f1fa8c", "#bd93f9", "#ff79c6", "#8be9fd", "#f8f8f2",
    "#6272a4", "#ff6e6e", "#69ff94", "#ffffa5", "#d6acff", "#ff92df", "#a4ffff", "#ffffff" }),
  gruvbox = theme("#ebdbb2", "#282828", "#fe8019", {
    "#282828", "#cc241d", "#98971a", "#d79921", "#458588", "#b16286", "#689d6a", "#a89984",
    "#928374", "#fb4934", "#b8bb26", "#fabd2f", "#83a598", "#d3869b", "#8ec07c", "#ebdbb2" }),
  onelight = theme("#383a42", "#fafafa", "#526fff", {
    "#383a42", "#e45649", "#50a14f", "#c18401", "#0184bc", "#a626a4", "#0997b3", "#fafafa",
    "#4f525e", "#e06c75", "#98c379", "#e5c07b", "#61afef", "#c678dd", "#56b6c2", "#ffffff" }),
  -- Dracula with only its background tinted: the case a tint alone cannot separate.
  dracula_tint = theme("#f8f8f2", "#2d2f3b", "#ff79c6", {
    "#21222c", "#ff5555", "#50fa7b", "#f1fa8c", "#bd93f9", "#ff79c6", "#8be9fd", "#f8f8f2",
    "#6272a4", "#ff6e6e", "#69ff94", "#ffffa5", "#d6acff", "#ff92df", "#a4ffff", "#ffffff" }),
  -- Dracula's background, with everything else from Gruvbox: the case where only
  -- a comparison of the background would see no change.
  same_background = theme("#ebdbb2", "#282a36", "#fe8019", {
    "#282828", "#cc241d", "#98971a", "#d79921", "#458588", "#b16286", "#689d6a", "#a89984",
    "#928374", "#fb4934", "#b8bb26", "#fabd2f", "#83a598", "#d3869b", "#8ec07c", "#ebdbb2" }),
}
