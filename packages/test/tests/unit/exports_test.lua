-- The public surface of `hecate.test`: exactly the documented names, each of the documented kind.
local core = require("hecate.core")
local hecate_test = require("hecate.test")
local T = hecate_test.Case("ExportsTest")

local CLASSES = {
  "AssertionFailure", "Client", "ConsoleReporter", "Generator", "JUnitReporter", "JsonLinesReporter", "LineCoverage",
  "LoadError", "RouteCoverage", "Runner",
}
local FUNCTIONS = {
  "Case", "boot", "check_property", "discover", "generate", "generate_invalid", "is_case", "load", "of_type",
  "parse_arguments", "run_parallel",
}

function T:test_the_module_exports_exactly_the_documented_names()
  local expected, actual = {}, {}
  for _, name in ipairs(CLASSES) do expected[#expected + 1] = name end
  for _, name in ipairs(FUNCTIONS) do expected[#expected + 1] = name end
  expected[#expected + 1] = "TapReporter"
  for name in pairs(hecate_test) do actual[#actual + 1] = name end
  table.sort(expected)
  table.sort(actual)
  self:assert_equal(expected, actual)
end

function T:test_classes_are_classes_and_the_rest_are_functions()
  for _, name in ipairs(CLASSES) do
    self:assert_true(core.is_class(hecate_test[name]), name .. " is not a class")
  end
  self:assert_true(core.is_class(hecate_test.TapReporter))
  for _, name in ipairs(FUNCTIONS) do
    self:assert_equal("function", type(hecate_test[name]), name .. " is not a function")
  end
end

return core.finalise(T)
