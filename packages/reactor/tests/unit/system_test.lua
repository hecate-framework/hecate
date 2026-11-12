local test = require("harness.test")
local reactor = require("hecate.reactor")
local T = test.Case("SystemTest")

function T:test_system_name_is_a_known_name()
  local name = reactor.system_name()
  self:assert_equal("string", type(name))
  self:assert_true(name ~= "")
  local windows = package.config:sub(1, 1) == "\\"
  if windows then self:assert_true(name:find("^Windows") ~= nil) end
end

function T:test_available_parallelism_is_a_positive_integer()
  local count = reactor.available_parallelism()
  self:assert_equal("integer", math.type(count))
  self:assert_true(count >= 1)
end

return T
