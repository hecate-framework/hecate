-- Declare a test case, run it and read the summary. A test file does the
-- same without the last lines: it declares the case and returns it, and a
-- runner (or `test.run_parallel`) loads the file.
local core = require("hecate.core")
local test = require("hecate.test")

local GreetingTest = test.Case("GreetingTest")

function GreetingTest:test_a_greeting_is_polite()
  self:assert_match("^Hello", "Hello, Ada")
end

function GreetingTest:test_tables_are_compared_by_structure()
  self:assert_equal({ name = "Ada", tags = { "a" } }, { name = "Ada", tags = { "a" } })
end

core.finalise(GreetingTest)

local summary = test.Runner():run({ GreetingTest })
print(summary.total, summary.passed, summary.exit_code)
-- Prints: 2	2	0
