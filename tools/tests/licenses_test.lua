local test = require("harness.test")
local licenses = require("lib.licenses")
local T = test.Case("LicensesTest")

function T:test_reports_a_vendored_directory_without_licence_file()
  local problems = licenses.check({ "packages/a/csrc/vendor" }, function() return false end, "")
  self:assert_equal(2, #problems)
  self:assert_true(problems[1]:find("LICENSE", 1, true) ~= nil)
end

function T:test_reports_a_vendored_directory_missing_from_the_notices()
  local problems = licenses.check({ "packages/a/csrc/vendor" }, function() return true end, "nothing here")
  self:assert_equal(1, #problems)
  self:assert_true(problems[1]:find("THIRD_PARTY_NOTICES", 1, true) ~= nil)
end

function T:test_accepts_a_complete_vendored_directory()
  local notices = "Location: packages/a/csrc/vendor/ (x)"
  self:assert_equal(0, #licenses.check({ "packages/a/csrc/vendor" }, function() return true end, notices))
end

return T
