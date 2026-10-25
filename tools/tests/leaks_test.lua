local test = require("harness.test")
local leaks = require("lib.leaks")
local T = test.Case("LeaksTest")

function T:test_environment_sets_the_switch_per_platform()
  self:assert_equal("HECATE_TEST_LEAKS=1 ", leaks.environment(false))
  self:assert_equal("set HECATE_TEST_LEAKS=1&& ", leaks.environment(true))
end

function T:test_default_packages_are_the_reactor_heavy_ones()
  self:assert_equal("reactor", leaks.packages[1])
  self:assert_equal("net", leaks.packages[2])
end

function T:test_a_leaking_test_fails_the_file()
  local util = require("lib.util")
  local root = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/tests/[^/]*$") or "."
  local path = os.tmpname()
  local f = assert(io.open(path, "w"))
  f:write([[
local test = require("test")
local C = test.Case("Leaky")
function C:test_clean() end
function C:test_leaks() _G.timer = require("luv").new_timer() end
return C
]])
  f:close()
  local ok_luv = pcall(require, "luv")
  if ok_luv then
    local out, ok = util.capture(leaks.environment(util.is_windows()) .. ("%s %s %s 2>&1"):format(util.quote(util.interpreter()),
      util.quote(root .. "/harness/run_file.lua"), util.quote(path)))
    self:assert_false(ok, out)
    self:assert_true(out:find("leaked 1 libuv handle", 1, true) ~= nil, out)
  end
  os.remove(path)
end

return T
