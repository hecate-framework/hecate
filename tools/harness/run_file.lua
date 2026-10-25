-- Runs one *_test.lua file and prints TAP lines. Usage: lua run_file.lua <file> <src-path>...
local harness_dir = arg[0]:gsub("\\", "/"):match("^(.*)/[^/]*$") or "."
package.path = harness_dir .. "/?.lua;" .. package.path
local test = require("test")
-- Project-local LuaRocks trees (native rocks such as luv): `.hecate/rocks` is where CI and
-- developers install them; `spikes/rocks` is the cloud-session spike tree.
do
  local root = harness_dir .. "/../.."
  local version = _VERSION:match("%d+%.%d+")
  for _, tree in ipairs({ "/.hecate/rocks", "/spikes/rocks" }) do
    local base = root .. tree
    package.path = base .. "/share/lua/" .. version .. "/?.lua;" .. base .. "/share/lua/" .. version
      .. "/?/init.lua;" .. package.path
    package.cpath = base .. "/lib/lua/" .. version .. "/?.so;" .. base .. "/lib/lua/" .. version
      .. "/?.dll;" .. package.cpath
  end
end
local file = arg[1]
for i = 2, #arg do package.path = arg[i] .. "/?.lua;" .. arg[i] .. "/?/init.lua;" .. package.path end

-- Watchdog: a test that does not finish within HECATE_TEST_TIMEOUT seconds (default 120) fails the
-- file and names the test, instead of blocking the run until the CI job is cancelled. A luv timer
-- catches a wait inside the event loop (the usual hang of a transport test); a count hook catches a
-- loop in Lua. A blocking system call is caught by neither (the job-level timeout of CI covers it).
do
  local limit = tonumber(os.getenv("HECATE_TEST_TIMEOUT")) or 120
  local current, deadline
  local function expire()
    io.stdout:write(("not ok - %s\n  # timed out after %s seconds (HECATE_TEST_TIMEOUT)\n"):format(current, limit))
    io.stdout:flush()
    os.exit(124)
  end
  local has_luv, uv = pcall(require, "luv")
  local timer = has_luv and uv.new_timer() or nil
  if timer then timer:unref() end
  debug.sethook(function() if deadline and os.time() > deadline then expire() end end, "", 1000000)
  test.on_start = function(name)
    current, deadline = name, os.time() + limit
    if timer then
      timer:stop()
      timer:start(limit * 1000, 0, expire)
    end
  end
end

-- Leak detection (`leaks` task, HECATE_TEST_LEAKS=1): a test must leave the libuv loop with the handles it
-- found, so a stream, timer or process handle that a test (or the code under test) forgot to close fails it.
if os.getenv("HECATE_TEST_LEAKS") then
  local ok, uv = pcall(require, "luv")
  if ok then
    local function open_handles()
      local count = 0
      uv.walk(function(handle) if not uv.is_closing(handle) then count = count + 1 end end)
      return count
    end
    local baseline
    local previous = test.on_start
    test.on_start = function(name)
      if previous then previous(name) end
      baseline = open_handles()
    end
    test.on_finish = function(_, passed)
      local now = open_handles()
      if passed and now > baseline then
        return ("leaked %d libuv handle(s) (HECATE_TEST_LEAKS)"):format(now - baseline)
      end
    end
  end
end
local class = assert(loadfile(file))()
local failed = 0
for i, r in ipairs(test.run_case(class)) do
  if r.ok then print(("ok %d - %s"):format(i, r.name))
  else
    failed = failed + 1
    print(("not ok %d - %s"):format(i, r.name))
    print("  # " .. tostring(r.message):gsub("\n", "\n  # "))
  end
end
os.exit(failed == 0 and 0 or 1)
