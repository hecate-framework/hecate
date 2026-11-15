local test = require("hecate.test")
local test = require("hecate.test")
local T = test.Case("FixtureA")
function T:test_ok() self:assert_true(true) end
return require("hecate.core").finalise(T)
