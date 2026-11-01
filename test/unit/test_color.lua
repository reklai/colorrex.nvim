local T = require("harness")
local Color = require("color-rex.color")

T.test("color: hex round-trips through OKLab for every channel extreme", function()
  for _, hex in ipairs({ "#000000", "#ffffff", "#ff0000", "#00ff00", "#0000ff", "#808080", "#123456" }) do
    T.eq(Color.from_oklab(Color.oklab(hex)), hex)
  end
end)

T.test("color: contrast matches the WCAG reference values", function()
  T.eq(math.floor(Color.contrast("#000000", "#ffffff") * 100 + 0.5), 2100)
  T.eq(Color.contrast("#777777", "#777777"), 1)
  T.eq(math.floor(Color.contrast("#777777", "#ffffff") * 100 + 0.5), 448)
end)

T.test("color: is_dark agrees with Neovim's rule at the boundary", function()
  T.ok(Color.is_dark("#0d1117"))
  T.ok(not Color.is_dark("#fafafa"))
  T.ok(Color.is_dark("#00b900"), "Neovim calls this dark even though WCAG luminance says otherwise")
end)

T.test("color: lift leaves a readable color alone", function()
  T.eq(Color.lift("#ff7b72", "#0d1117", 3), "#ff7b72")
end)

T.test("color: lift reaches the floor and keeps the hue", function()
  local lifted = Color.lift("#e5c07b", "#fafafa", 3)
  T.ok(Color.contrast(lifted, "#fafafa") >= 3)
  T.ok(Color.hue_gap(lifted, "#e5c07b") < 12, "hue must not drift")
end)

T.test("color: lift reaches 4.5:1 on the hardest possible mid-grey", function()
  T.ok(Color.contrast(Color.lift("#777777", "#777777", 4.5), "#777777") >= 4.5)
end)

T.test("color: an out-of-gamut color keeps its hue instead of clipping", function()
  local L, a, b = Color.oklab("#ff0000")
  local out = Color.from_oklab(0.95, a, b)
  T.ok(Color.hue_gap(out, "#ff0000") < 15, "got " .. out)
end)
