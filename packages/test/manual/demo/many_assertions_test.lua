-- A suite whose assertion count grows past three digits: the line must never exceed the terminal width.
local test = require("hecate.test")
local T = test.Case("ManyAssertionsTest")

function T:test_a_thousand_assertions()
  for index = 1, 1000 do self:assert_equal(index, index) end
end

function T:test_another_thousand_assertions()
  for index = 1, 1000 do self:assert_true(index > 0) end
end

return require("hecate.core").finalise(T)
