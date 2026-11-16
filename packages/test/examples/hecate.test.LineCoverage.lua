-- Record which lines of the sources run while a runner works, then read the
-- figures and the LCOV report. `include` is a Lua pattern on the path of a
-- source; this example records itself.
local core = require("hecate.core")
local test = require("hecate.test")

local function double(n)
  return n * 2
end

local DoubleTest = test.Case("DoubleTest")
function DoubleTest:test_double() self:assert_equal(4, double(2)) end
core.finalise(DoubleTest)

local coverage = test.LineCoverage({ include = "hecate.test.LineCoverage" })
local summary = test.Runner({ coverage = coverage }):run({ DoubleTest })
print(summary.ok, coverage:report().percent > 0)
-- Prints: true	true
print(coverage:lcov():find("^SF:") ~= nil)
-- Prints: true
