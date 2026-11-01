-- A lualine theme, by role. Nothing here depends on lualine; the compiled table
-- reaches it through lua/lualine/themes/color-rex.lua.
local M = {}

function M.build()
  local function mode(fill, on)
    return {
      a = { fg = on, bg = fill, gui = "bold" },
      b = { fg = "fg", bg = "subtle" },
      c = { fg = "muted", bg = "statusline" },
    }
  end
  return {
    normal = mode("accent", "on_accent"),
    insert = mode("ok", "on_ok"),
    visual = mode("keyword", "on_keyword"),
    replace = mode("error", "on_error"),
    command = mode("warn", "on_warn"),
    inactive = {
      a = { fg = "muted", bg = "cursorline" },
      b = { fg = "muted", bg = "cursorline" },
      c = { fg = "muted", bg = "cursorline" },
    },
  }
end

return M
