local test = require("hecate.test")
local T = test.Case("ParallelB")
function T:test_fails() self:assert_equal(1, 2) end
return require("hecate.core").finalise(T)
