local test = require("harness.test")
local interpreter = require("hecate.cli.internal.interpreter")
local T = test.Case("CliInterpreterTest")

function T:test_the_leading_arguments_come_first_and_are_optional()
  self:assert_equal("--lua,-e,code", table.concat(interpreter.arguments({ "--lua" }, { "-e", "code" }), ","))
  self:assert_equal("main.lua", table.concat(interpreter.arguments(nil, { "main.lua" }), ","))
  self:assert_equal("", table.concat(interpreter.arguments({}, {}), ","))
end

function T:test_the_arguments_given_are_not_modified()
  local leading, args = { "--lua" }, { "a" }
  interpreter.arguments(leading, args)
  self:assert_equal(1, #leading)
  self:assert_equal(1, #args)
end

return T
