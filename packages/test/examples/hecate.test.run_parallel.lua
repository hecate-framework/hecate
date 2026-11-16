-- Run test files in worker processes. The events reach the reporter live and
-- in the order of the files. The test file is written here so that the
-- example stands alone; yours are the `*_test.lua` files of a directory
-- (`test.discover`).
local reactor = require("hecate.reactor")
local test = require("hecate.test")

local directory = os.getenv("TMPDIR") or os.getenv("TEMP") or "/tmp"
local path = directory .. "/hecate_example_greeting_test.lua"
local file = assert(io.open(path, "w"))
file:write([[
local test = require("hecate.test")
local GreetingTest = test.Case("GreetingTest")
function GreetingTest:test_a_greeting() self:assert_match("^Hello", "Hello, Ada") end
return require("hecate.core").finalise(GreetingTest)
]])
file:close()

reactor.run(function()
  local summary = test.run_parallel({ path }, { jobs = 2 })
  print(summary.total, summary.passed, summary.exit_code)
  -- Prints: 1	1	0
end)
os.remove(path)
