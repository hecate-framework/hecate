local reactor = require("hecate.reactor")
local test = require("hecate.test")
local T = test.Case("ParallelSlow")
function T:test_a_fast() self:assert_true(true) end
function T:test_b_slow() reactor.sleep(0.6) self:assert_true(true) end
return require("hecate.core").finalise(T)
