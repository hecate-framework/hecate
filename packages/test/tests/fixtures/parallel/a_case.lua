local test = require("hecate.test")
local T = test.Case("ParallelA")
function T:test_one() self:assert_equal(1, 1) end
function T:test_two() self:assert_equal(2, 2) end
return require("hecate.core").finalise(T)
