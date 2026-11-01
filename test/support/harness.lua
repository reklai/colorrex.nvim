-- A very small test harness, shared by LuaJIT and Neovim. No dependencies.
local T = { tests = {} }

function T.test(name, fn)
  T.tests[#T.tests + 1] = { name = name, fn = fn, file = T.current_file }
end

local function show(value)
  if type(value) == "string" then
    return ("%q"):format(value)
  end
  return tostring(value)
end

function T.eq(actual, expected, label)
  if actual ~= expected then
    error(("%sexpected %s, got %s"):format(label and label .. ": " or "", show(expected), show(actual)), 2)
  end
end

function T.ok(value, label)
  if not value then
    error(label or "expected a true value", 2)
  end
end

function T.run(pattern)
  local passed, failed, skipped = 0, 0, 0
  for _, test in ipairs(T.tests) do
    if not pattern or test.name:match(pattern) then
      local ok, err = xpcall(test.fn, debug.traceback)
      if ok then
        passed = passed + 1
      elseif type(err) == "string" and err:match("SKIP:") then
        skipped = skipped + 1
        print(("SKIP %s: %s"):format(test.name, err:match("SKIP: ([^\n]*)")))
      else
        failed = failed + 1
        print(("FAIL %s  (%s)\n  %s"):format(test.name, test.file, err))
      end
    end
  end
  print(("%d passed, %d failed, %d skipped"):format(passed, failed, skipped))
  return failed
end

function T.skip(reason)
  error("SKIP: " .. reason, 0)
end

--- A deterministic random source, so a fuzz failure can be replayed by seed.
function T.rng(seed)
  local state = seed
  return function(n)
    state = (state * 1103515245 + 12345) % 2147483648
    return math.floor(state / 65536) % n
  end
end

return T
