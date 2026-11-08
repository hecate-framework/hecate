---@diagnostic disable: need-check-nil, param-type-mismatch  -- the tests index violations they just asserted exist
local test = require("harness.test")
local json = require("hecate.json")
local schema = require("hecate.schema")
local T = test.Case("SchemaCoerceTest")

function T:test_integer_reads_decimal_text()
  local ok, value = schema.integer():coerce("42")
  self:assert_true(ok)
  self:assert_equal(42, value)
  self:assert_equal("integer", math.type(value))
  self:assert_equal(-7, select(2, schema.integer():coerce("-7")))
end

function T:test_integer_refuses_other_texts()
  for _, text in ipairs({ "", "1.5", "0x10", "abc", " 1", "99999999999999999999" }) do
    local ok, violations = schema.integer():coerce(text)
    self:assert_false(ok, text)
    self:assert_equal("coercion", violations[1].code, text)
  end
end

function T:test_number_reads_json_grammar()
  self:assert_equal("integer", math.type(select(2, schema.number():coerce("3"))))
  self:assert_equal(1.5, select(2, schema.number():coerce("1.5")))
  self:assert_equal(1000.0, select(2, schema.number():coerce("1e3")))
  for _, text in ipairs({ "nan", "inf", ".5", "1.", "1e999" }) do
    self:assert_false((schema.number():coerce(text)), text)
  end
end

function T:test_boolean_reads_true_and_false_only()
  self:assert_equal(true, select(2, schema.boolean():coerce("true")))
  self:assert_equal(false, select(2, schema.boolean():coerce("false")))
  self:assert_false((schema.boolean():coerce("1")))
  self:assert_false((schema.boolean():coerce("True")))
end

function T:test_coerced_value_is_validated()
  local ok, violations = schema.integer({ minimum = 10 }):coerce("5")
  self:assert_false(ok)
  self:assert_equal("minimum", violations[1].code)
end

function T:test_non_text_values_are_not_converted()
  self:assert_equal(5, select(2, schema.integer():coerce(5)))
  self:assert_false((schema.integer():coerce(5.5)))
  self:assert_false((schema.string():coerce(5)))
end

function T:test_constants()
  self:assert_equal(2, select(2, schema.enumeration({ 1, 2, 3 }):coerce("2")))
  self:assert_equal("a", select(2, schema.enumeration({ "a", "b" }):coerce("a")))
  self:assert_equal(true, select(2, schema.literal(true):coerce("true")))
  self:assert_equal(json.null, select(2, schema.literal(json.null):coerce("null")))
  self:assert_false((schema.enumeration({ 1, 2 }):coerce("9")))
end

function T:test_array_splits_text_and_takes_lists()
  local ints = schema.array(schema.integer())
  self:assert_equal("1,2,3", table.concat(select(2, ints:coerce("1,2,3")), ","))
  self:assert_equal("1,2", table.concat(select(2, ints:coerce({ "1", "2" })), ","))
  self:assert_equal(0, #select(2, ints:coerce("")))
  self:assert_equal(2, #select(2, schema.array(schema.integer(), { delimiter = "|" }):coerce("4|5")))
  self:assert_equal(1, #select(2, schema.array(schema.string()):coerce("solo")))
end

function T:test_array_reports_each_bad_element_with_its_path()
  local ok, violations = schema.array(schema.integer()):coerce({ "1", "x", "y" })
  self:assert_false(ok)
  self:assert_equal(2, #violations)
  self:assert_equal("/1", violations[1].path)
  self:assert_equal("/2", violations[2].path)
end

function T:test_object_converts_declared_properties_without_mutating_input()
  local s = schema.object({ id = schema.integer(), tags = schema.optional(schema.array(schema.string())),
    active = schema.boolean() })
  local input = { id = "42", active = "true", tags = "a,b" }
  local ok, value = s:coerce(input)
  self:assert_true(ok)
  self:assert_equal(42, value.id)
  self:assert_equal(true, value.active)
  self:assert_equal(2, #value.tags)
  self:assert_equal("42", input.id)
end

function T:test_object_paths_and_missing_properties()
  local s = schema.object({ id = schema.integer(), page = schema.optional(schema.integer()) })
  local ok, violations = s:coerce({ id = "x" })
  self:assert_false(ok)
  self:assert_equal("/id", violations[1].path)
  local _, missing = s:coerce({})
  self:assert_equal("required", missing[1].code)
  self:assert_true((s:coerce({ id = "1" })))
end

function T:test_union_takes_first_accepting_alternative()
  local s = schema.union({ schema.integer(), schema.boolean() })
  self:assert_equal(3, select(2, s:coerce("3")))
  self:assert_equal(true, select(2, s:coerce("true")))
  local ok, violations = s:coerce("x")
  self:assert_false(ok)
  self:assert_equal("union", violations[1].code)
end

function T:test_nullable_and_optional_delegate()
  self:assert_equal(4, select(2, schema.nullable(schema.integer()):coerce("4")))
  self:assert_equal(4, select(2, schema.optional(schema.integer()):coerce("4")))
end

function T:test_empty_delimiter_is_refused()
  self:assert_error(function() schema.array(schema.string(), { delimiter = "" }) end)
end

return T
