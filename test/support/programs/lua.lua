-- logscan: count log levels in a file.
local M = {}

APP_NAME = "logscan" -- a global, on purpose
local MAX_RETRIES <const> = 3

local Levels = { INFO = 1, WARN = 2, ERROR = 3 }

local Entry = {}
Entry.__index = Entry

function Entry.new(level, message)
  return setmetatable({ level = level, message = message }, Entry)
end

function Entry:is_serious()
  return self.level ~= Levels.INFO
end

local function parse(line)
  line = line:match("^%s*(.-)%s*$")
  if line == "" then
    return nil, "empty line"
  end
  local head, rest = line:match("^(%u+)%s+(.*)$")
  if not head then
    return nil, "no level in: " .. line
  end
  local level = Levels[head]
  if level == nil then
    return nil, string.format("bad level %q", head)
  end
  return Entry.new(level, rest)
end

function M.load(path)
  local file, err = io.open(path, "r")
  if not file then
    return nil, err
  end
  local entries = {}
  for line in file:lines() do
    local entry, perr = parse(line)
    if entry then
      table.insert(entries, entry)
    elseif perr ~= "empty line" then
      file:close()
      error(perr, 2)
    end
  end
  file:close()
  return entries
end

---@deprecated use M.load
local function load_all(path)
  return M.load(path)
end

local function each(entries, visit)
  for _, entry in ipairs(entries) do
    visit(entry)
  end
end

local function main(...)
  local path = select(1, ...) or os.getenv("LOG") or "app.log"
  local entries, err
  for attempt = 1, MAX_RETRIES do
    local ok, result = pcall(load_all, path)
    if ok and result then
      entries = result
      break
    end
    err = result
    print(APP_NAME .. ": retry " .. attempt)
  end
  assert(entries, err)
  local counts = {}
  each(entries, function(entry)
    if entry:is_serious() then
      counts[entry.level] = (counts[entry.level] or 0) + 1
    end
  end)
  for level, count in pairs(counts) do
    io.write(level, "\t", count, "/", #entries, "\n")
  end
end

main(...)
return M
