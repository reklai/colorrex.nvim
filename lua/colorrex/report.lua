-- What the commands say. Pure: data in, text out, so every report can be judged
-- without Neovim. Each function returns a message and, when it is not routine, a
-- notification level.
local M = {}

function M.status(status)
  local last = status.last
  local summary = not last.reason and "not yet"
    or not last.outcome and ("%s: waiting for the terminal"):format(last.reason)
    or ("%s: %s (%s)"):format(last.reason, last.completeness, last.outcome)
  return table.concat({
    ("theme     %s, from %s (%s)"):format(status.background, status.source, status.completeness),
    ("id        %s, %s"):format(status.id,
      status.voice and ("%s voice"):format(status.voice) or ("casting %d"):format(status.casting)),
    ("colors    fg %s  bg %s  accent %s"):format(status.fg, status.bg, status.accent),
    ("last sync %s"):format(summary),
    ("auto      %s"):format(status.auto and "on (focus, dark/light changes, and a watch while unfocused)" or "off (:ColorRex only)"),
    ("adjusted  %d (see :ColorRex check)"):format(status.adjustments),
  }, "\n")
end

--- The group this plugin defines for a name, if any. Neovim reads @comment.lua as
--- @comment when no such group exists, so this does the same.
local function defined(specs, name)
  while name do
    if specs[name] then
      return name
    end
    name = name:match("^(.+)%.[^.]+$")
  end
  return nil
end

--- Why a group is the color it is. `candidates` are names to try, in order: a
--- cursor can sit on several, and not all of them are ours.
function M.explain(colorscheme, candidates)
  if #candidates == 0 then
    return "nothing under the cursor; try :ColorRex explain Comment", "warn"
  end
  local specs = colorscheme.group_specs
  local name
  for _, candidate in ipairs(candidates) do
    name = name or defined(specs, candidate)
  end
  if not name then
    return ("%s is not a group colorrex defines"):format(candidates[1]), "warn"
  end
  local lines = {}
  while specs[name].link do
    lines[#lines + 1] = ("%s links to %s"):format(name, specs[name].link)
    name = specs[name].link
  end
  lines[#lines + 1] = name
  local described = false
  for _, key in ipairs({ "fg", "bg", "sp" }) do
    local role_name = specs[name][key]
    if role_name then
      described = true
      local role = colorscheme.roles[role_name]
      local origin = role.from and (", moved from %s to stay readable"):format(role.from) or ""
      lines[#lines + 1] = ("  %s %s  role %s, from %s%s"):format(key, role.hex, role_name, role.source, origin)
    end
  end
  if not described then
    lines[#lines + 1] = "  sets no color of its own"
  end
  return table.concat(lines, "\n")
end

--- The verdict on a colorscheme, with every adjustment that was needed.
function M.check(colorscheme, failures)
  local lines = {}
  if #failures == 0 then
    lines[1] = "promises kept for this theme"
  end
  for _, failure in ipairs(failures) do
    lines[#lines + 1] = ("BROKEN %s: %s"):format(failure.code, failure.message)
  end
  if colorscheme.completeness ~= "full" then
    lines[#lines + 1] = "not the terminal's full theme yet; run :ColorRex"
  end
  for _, note in ipairs(colorscheme.notes) do
    lines[#lines + 1] = ("  %s: %s"):format(note.code, note.message)
  end
  return table.concat(lines, "\n"), #failures > 0 and "error" or nil
end

return M
