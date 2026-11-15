local test = require("hecate.test")
local test = require("hecate.test")
local T = test.Case("FixtureB")
function T:test_ok() end
return require("hecate.core").finalise(T)
