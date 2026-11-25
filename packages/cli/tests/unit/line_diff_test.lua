local test = require("harness.test")
local line_diff = require("hecate.cli.internal.line_diff")
local T = test.Case("CliLineDiffTest")

function T:test_equal_texts_have_no_diff()
  self:assert_equal(nil, line_diff.unified("a\nb\n", "a\nb\n", "x", "y"))
  self:assert_equal(nil, line_diff.unified("", "", "x", "y"))
end

function T:test_a_changed_line_is_one_removal_and_one_addition_with_context()
  local diff = line_diff.unified("1\n2\n3\n4\n5\n6\n7\n8\n9\n", "1\n2\n3\n4\nfive\n6\n7\n8\n9\n", "old", "new")
  self:assert_equal("--- old\n+++ new\n@@ -2,7 +2,7 @@\n 2\n 3\n 4\n-5\n+five\n 6\n 7\n 8", diff)
end

function T:test_insertions_deletions_and_distant_changes_make_hunks()
  local old, new = {}, {}
  for i = 1, 20 do old[i] = "l" .. i .. "\n"; new[i] = "l" .. i .. "\n" end
  new[2] = "two\n"
  table.remove(new, 19)
  local diff = assert(line_diff.unified(table.concat(old), table.concat(new) .. "end\n", "a", "b"))
  local _, hunks = diff:gsub("\n@@", "")
  self:assert_equal(2, hunks)
  self:assert_true(diff:find("-l2\n+two\n", 1, true) ~= nil, diff)
  self:assert_true(diff:find("-l19\n", 1, true) ~= nil, diff)
  self:assert_true(diff:find("+end", 1, true) ~= nil, diff)
end

function T:test_from_and_to_empty()
  self:assert_equal("--- a\n+++ b\n@@ -0,0 +1,2 @@\n+x\n+y", line_diff.unified("", "x\ny\n", "a", "b"))
  self:assert_equal("--- a\n+++ b\n@@ -1 +0,0 @@\n-x", line_diff.unified("x\n", "", "a", "b"))
end

function T:test_a_missing_final_line_break_is_marked()
  self:assert_equal("--- a\n+++ b\n@@ -1 +1 @@\n-x\n\\ No newline at end of file\n+x", line_diff.unified("x", "x\n", "a", "b"))
end

return T
