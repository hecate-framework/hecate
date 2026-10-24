local test = require("harness.test")
local log = require("hecate.log")
local T = test.Case("SecretTest")

function T:test_tostring_never_shows_the_value()
  local secret = log.Secret("hunter2")
  self:assert_equal("[redacted]", tostring(secret))
  self:assert_nil(tostring(secret):find("hunter2", 1, true))
end

function T:test_the_value_is_reachable_only_through_reveal()
  self:assert_equal("hunter2", log.Secret("hunter2"):reveal())
end

function T:test_no_field_of_the_secret_holds_the_value()
  for _, field in pairs(log.Secret("hunter2")) do self:assert_equal("function", type(field)) end
end

return T
