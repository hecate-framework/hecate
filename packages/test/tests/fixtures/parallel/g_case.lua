print("noise before the result")
io.write("\030hecate-test-events\030{not json at all\n")
local test = require("hecate.test")
local T = test.Case("ParallelG")
function T:test_noise_is_ignored() self:assert_true(true) end
return require("hecate.core").finalise(T)
