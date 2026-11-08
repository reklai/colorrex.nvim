local function parse(text)
  if text == nil then return nil, "empty" end
  local ok, err = pcall(tonumber, text)
  if not ok then error(err) end
  assert(ok, err)
  return true, 3
end
