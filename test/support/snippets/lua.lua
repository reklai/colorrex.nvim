local function parse(text)
  if text == nil then return nil, "empty" end
  local ok, err = pcall(tonumber, text)
  if not ok then error(err) end
  assert(ok, err)
  return true, 3
end

---@param path string
local CONFIG <const> = "x"
-- Prints each number up to three.
local function each(...)
  for i = 1, select("#", ...) do
    if i > 3 then goto continue end
    print(string.format("%d\n", i), io.stdout)
    ::continue::
  end
end
