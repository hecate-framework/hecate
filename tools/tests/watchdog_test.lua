local test = require("harness.test")
local util = require("lib.util")
local T = test.Case("WatchdogTest")

local is_windows = package.config:sub(1, 1) == "\\"

--- Runs the file runner on `file` with a one-second timeout and returns its output and success.
local function run_file(file)
  local root = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/tests/[^/]*$") or "."
  local command = ("%s %s %s"):format(util.quote(util.interpreter()), util.quote(root .. "/harness/run_file.lua"),
    util.quote(file))
  local env = is_windows and "set HECATE_TEST_TIMEOUT=1&& " or "HECATE_TEST_TIMEOUT=1 "
  return util.capture(env .. command .. " 2>&1")
end

function T:test_a_test_that_never_finishes_fails_the_file_and_is_named()
  local path = os.tmpname()
  local f = assert(io.open(path, "w"))
  f:write([[
local test = require("test")
local C = test.Case("Hang")
function C:test_quick() end
function C:test_spins() while true do end end
return C
]])
  f:close()
  local out, ok = run_file(path)
  os.remove(path)
  self:assert_false(ok, out)
  self:assert_true(out:find("Hang.test_spins", 1, true) ~= nil, out)
  self:assert_true(out:find("timed out after 1 seconds", 1, true) ~= nil, out)
end

function T:test_a_passing_file_is_not_affected()
  local path = os.tmpname()
  local f = assert(io.open(path, "w"))
  f:write([[
local test = require("test")
local C = test.Case("Fine")
function C:test_a() self:assert_true(true) end
return C
]])
  f:close()
  local out, ok = run_file(path)
  os.remove(path)
  self:assert_true(ok, out)
  self:assert_true(out:find("ok 1 - Fine.test_a", 1, true) ~= nil, out)
end

return T
