local test = require("harness.test")
local T = test.Case("HarnessTest")
function T:test_equal() self:assert_equal(1, 1) end
function T:test_error() self:assert_error(function() error("boom") end, "boom") end
function T:test_failure_is_reported()
  local results = test.run_case((function()
    local C = test.Case("Inner")
    function C:test_bad() self:assert_equal(1, 2) end
    return C
  end)())
  self:assert_false(results[1].ok)
end
return T
