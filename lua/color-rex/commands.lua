-- One catalog of commands. `:ColorRex`, its subcommands and their <Plug> mappings
-- all resolve here, so a keybind and a typed command can never behave differently.
-- Adding an entry adds it everywhere, completion included.
local M = {}

--- Bare `:ColorRex`, the one you run all the time. It has no subcommand name.
M.default = {
  desc = "Read the terminal's theme and repaint if it changed",
  run = function(app)
    app:sync("manual")
  end,
}

M.catalog = {
  {
    name = "status",
    desc = "Show the active theme and the last sync",
    plug = true,
    run = function(app)
      app:report_status()
    end,
  },
  {
    name = "explain",
    desc = "Show where a group's color came from (default: under the cursor)",
    plug = true,
    max_args = 1,
    run = function(app, args)
      app:explain(args[1])
    end,
  },
  {
    name = "check",
    desc = "Judge the current theme against the promises",
    plug = true,
    run = function(app)
      app:check()
    end,
  },
  {
    name = "compile",
    desc = "Write the current theme as a standalone colorscheme",
    max_args = 1,
    run = function(app, args, bang)
      app:compile_to(args[1], bang)
    end,
  },
}

local function find(name)
  for _, command in ipairs(M.catalog) do
    if command.name == name then
      return command
    end
  end
  return nil
end

--- Run `:ColorRex [name] [args]`. Returns an error message instead of raising,
--- so the caller presents it.
function M.run(app, fargs, bang)
  if #fargs == 0 then
    M.default.run(app)
    return nil
  end
  local name = fargs[1]
  local command = find(name)
  if not command then
    return ("unknown command '%s' (try: %s)"):format(name, table.concat(M.names(), ", "))
  end
  local args = { unpack(fargs, 2) }
  if #args > (command.max_args or 0) then
    return ("%s takes at most %d argument(s)"):format(name, command.max_args or 0)
  end
  command.run(app, args, bang)
  return nil
end

function M.names()
  local names = {}
  for _, command in ipairs(M.catalog) do
    names[#names + 1] = command.name
  end
  return names
end

function M.complete(arglead, cmdline)
  if select(2, cmdline:gsub("%s+", " ")) > 1 then
    return {}
  end
  local out = {}
  for _, name in ipairs(M.names()) do
    if name:sub(1, #arglead) == arglead then
      out[#out + 1] = name
    end
  end
  return out
end

return M
