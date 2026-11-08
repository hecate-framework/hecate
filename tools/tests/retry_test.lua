local test = require("harness.test")
local retry = require("lib.retry")
local T = test.Case("RetryTest")

function T:test_a_step_that_succeeds_is_not_repeated()
  local calls = 0
  local out, ok, used = retry.run(function() calls = calls + 1 return "done", true end, 3, 1, function() end)
  self:assert_true(ok)
  self:assert_equal("done", out)
  self:assert_equal(1, used)
  self:assert_equal(1, calls)
end

function T:test_a_transient_failure_is_retried_with_a_pause()
  local calls, pauses = 0, {}
  local out, ok, used = retry.run(function()
    calls = calls + 1
    return "attempt " .. calls, calls == 3
  end, 3, 7, function(seconds) pauses[#pauses + 1] = seconds end)
  self:assert_true(ok)
  self:assert_equal("attempt 3", out)
  self:assert_equal(3, used)
  self:assert_equal(2, #pauses)
  self:assert_equal(7, pauses[1])
end

function T:test_a_persistent_failure_gives_up_after_the_tries_with_the_last_output()
  local calls = 0
  local out, ok, used = retry.run(function() calls = calls + 1 return "fail " .. calls, false end, 3, 1, function() end)
  self:assert_false(ok)
  self:assert_equal("fail 3", out)
  self:assert_equal(3, used)
end

return T
