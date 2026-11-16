-- Failures and errors: the report shows the location, a structural diff and a traceback.
local test = require("hecate.test")
local T = test.Case("FailingTest")

function T:test_passes() self:assert_true(true) end
function T:test_fails_with_a_diff() self:assert_equal({ name = "Ada", tags = { "a", "b" } }, { name = "Ada", tags = { "a", "c" } }) end
function T:test_errors() error("something went wrong", 0) end
function T:test_unicode_in_a_message() self:assert_equal("héllo wörld ✓", "hello world") end

return require("hecate.core").finalise(T)
