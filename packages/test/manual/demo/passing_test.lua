-- A slow suite of passing tests: on a terminal the line of the suite is redrawn as each test finishes.
local reactor = require("hecate.reactor")
local test = require("hecate.test")
local T = test.Case("PassingTest")

for index = 1, 24 do
  T["test_step_" .. ("%02d"):format(index)] = function(self)
    reactor.sleep(0.1)
    self:assert_equal(index, index)
  end
end

return require("hecate.core").finalise(T)
