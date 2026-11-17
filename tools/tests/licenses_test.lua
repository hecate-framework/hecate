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

function T:test_matches_whole_path_segments_and_not_a_substring()
  local notices = "Location: packages/a/csrc/vendor-old/ (x)"
  self:assert_equal(1, #licenses.check({ "packages/a/csrc/vendor" }, function() return true end, notices))
end

function T:test_reports_a_path_of_the_notices_that_does_not_exist()
  local notices = "Location: packages/a/csrc/vendor/ (x) and packages/a/gone.txt."
  local problems = licenses.check({ "packages/a/csrc/vendor" }, function(path) return path ~= "packages/a/gone.txt" end, notices)
  self:assert_equal(1, #problems)
  self:assert_true(problems[1]:find("gone.txt", 1, true) ~= nil)
end

function T:test_reports_a_vendor_directory_without_vendored_md()
  local problems = licenses.check({}, function() return true end, "", { "packages/b/csrc/vendor" })
  self:assert_equal(1, #problems)
  self:assert_true(problems[1]:find("VENDORED.md", 1, true) ~= nil)
end

function T:test_finds_the_vendor_directory_of_a_nested_file()
  self:assert_equal("packages/b/csrc/vendor", licenses.vendor_directory("packages/b/csrc/vendor/x/y.c"))
  self:assert_nil(licenses.vendor_directory("packages/b/src/y.lua"))
end

local VENDORED = [[
| File | SHA-256 |
| --- | --- |
| `a.js` | `%s` |
| `sub/LICENSE` | `%s` |
]]

function T:test_reads_the_digest_table_of_a_vendored_file()
  local text = VENDORED:format(("a"):rep(64), ("B"):rep(64))
  local digests = licenses.digests(text)
  self:assert_equal(2, #digests)
  self:assert_equal("a.js", digests[1].file)
  self:assert_equal(("a"):rep(64), digests[1].sha256)
  self:assert_equal("sub/LICENSE", digests[2].file)
  self:assert_equal(("b"):rep(64), digests[2].sha256, "digests are compared in lower case")
end

function T:test_a_digest_that_matches_is_not_a_problem()
  local digests = { { file = "a.js", sha256 = "x1" } }
  local read = function(path) return path == "d/a.js" and "data" or nil end
  self:assert_equal(0, #licenses.verify("d", digests, read, function() return "x1" end))
end

function T:test_a_changed_or_missing_vendored_file_is_reported()
  local digests = { { file = "a.js", sha256 = "x1" }, { file = "gone.js", sha256 = "x2" } }
  local read = function(path) return path == "d/a.js" and "data" or nil end
  local problems = licenses.verify("d", digests, read, function() return "different" end)
  self:assert_equal(2, #problems)
  self:assert_true(problems[1]:find("d/a.js", 1, true) ~= nil and problems[1]:find("SHA-256", 1, true) ~= nil)
  self:assert_true(problems[2]:find("d/gone.js", 1, true) ~= nil)
end

function T:test_a_vendored_file_without_digest_table_is_reported()
  local problems = licenses.verify("d", {}, function() return nil end, function() return "" end)
  self:assert_equal(1, #problems)
  self:assert_true(problems[1]:find("VENDORED.md", 1, true) ~= nil)
end

return T
