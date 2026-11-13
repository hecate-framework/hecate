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

function T:test_the_value_cannot_be_replaced()
  local core = require("hecate.core")
  local secret = log.Secret("hunter2")
  for _, name in ipairs({ "_reveal", "reveal", "value" }) do
    local ok, err = pcall(function() secret[name] = function() return "forged" end end)
    self:assert_false(ok, name)
    self:assert_true(core.is_instance_of(err, core.ConformanceError), tostring(err))
  end
  self:assert_equal("hunter2", secret:reveal())
  ---@diagnostic disable-next-line: undefined-field  -- the absence of the field is the point
  self:assert_nil(secret._reveal)
end

function T:test_two_secrets_are_distinct_objects()
  local secret = log.Secret("hunter2")
  self:assert_true(secret == secret)
  self:assert_false(secret == log.Secret("hunter2"))
end

return T
