local test = require("harness.test")
local log = require("hecate.log")
local Severity = log.Severity
local T = test.Case("SeverityTest")

function T:test_names_follow_rfc_5424_in_order_of_decreasing_urgency()
  local expected = { "emergency", "alert", "critical", "error", "warning", "notice", "informational", "debug" }
  local names = Severity:names()
  self:assert_equal(#expected, #names)
  for i, name in ipairs(expected) do self:assert_equal(name, names[i]) end
end

function T:test_numerical_codes_are_those_of_rfc_5424_section_6_2_1()
  self:assert_equal(0, log.severity_code(Severity.emergency))
  self:assert_equal(3, log.severity_code(Severity.error))
  self:assert_equal(6, log.severity_code(Severity.informational))
  self:assert_equal(7, log.severity_code(Severity.debug))
end

function T:test_a_more_urgent_severity_has_a_smaller_code()
  self:assert_true(log.severity_code(Severity.alert) < log.severity_code(Severity.warning))
end

return T
