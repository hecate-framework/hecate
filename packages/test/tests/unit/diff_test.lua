local diff = require("hecate.test.diff")
local test = require("hecate.test")
local T = test.Case("DiffTest")

function T:test_equal_tables_have_no_differences()
  local ok, lines = diff.compare({ 1, { a = "x" } }, { 1, { a = "x" } })
  self:assert_true(ok)
  self:assert_equal(0, #lines)
end

function T:test_a_changed_value_is_reported_with_its_path()
  local ok, lines = diff.compare({ a = { b = 1 } }, { a = { b = 2 } })
  self:assert_false(ok)
  self:assert_equal(".a.b: expected 1, got 2", lines[1])
end

function T:test_missing_and_unexpected_keys_are_reported()
  local ok, lines = diff.compare({ a = 1, b = 2 }, { b = 2, c = 3 })
  self:assert_false(ok)
  self:assert_equal(".a: missing, expected 1", lines[1])
  self:assert_equal(".c: unexpected 3", lines[2])
end

function T:test_array_indices_appear_in_brackets()
  local _, lines = diff.compare({ 1, 2 }, { 1, 3 })
  self:assert_equal("[2]: expected 2, got 3", lines[1])
end

function T:test_cycles_terminate()
  local a, b = {}, {}
  a.self, b.self = a, b
  self:assert_true((diff.compare(a, b)))
end

function T:test_the_number_of_differences_is_bounded()
  local e, a = {}, {}
  for i = 1, 100 do e[i] = i; a[i] = -i end
  local _, lines = diff.compare(e, a)
  self:assert_equal(20, #lines)
end

function T:test_show_quotes_strings_and_abbreviates_nesting()
  self:assert_equal('{1, "a", k = {x = {...}}}', diff.show({ 1, "a", k = { x = { y = 1 } } }))
end

return require("hecate.core").finalise(T)
