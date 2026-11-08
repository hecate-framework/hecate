---@diagnostic disable: need-check-nil, inject-field, param-type-mismatch, assign-type-mismatch  -- the tests index violations they just asserted exist, and pass wrong types on purpose
local test = require("harness.test")
local core = require("hecate.core")
local json = require("hecate.json")
local schema = require("hecate.schema")
local T = test.Case("SchemaValidateTest")

--- Returns the violations of `value` as a sorted list of "path code" strings.
local function codes(s, value)
  local ok, violations = s:validate(value)
  if ok then return nil end
  local out = {}
  for i, v in ipairs(violations) do out[i] = v.path .. " " .. v.code end
  table.sort(out)
  return out
end

function T:test_valid_values_return_true_and_no_violations()
  local ok, violations = schema.string():validate("x")
  self:assert_true(ok)
  self:assert_nil(violations)
end

function T:test_base_types_reject_other_types()
  self:assert_equal(" type", codes(schema.string(), 1)[1])
  self:assert_equal(" type", codes(schema.integer(), "1")[1])
  self:assert_equal(" type", codes(schema.number(), "1")[1])
  self:assert_equal(" type", codes(schema.boolean(), 0)[1])
end

function T:test_integer_rejects_floats_and_number_accepts_both()
  self:assert_equal(" type", codes(schema.integer(), 1.5)[1])
  self:assert_equal(" type", codes(schema.integer(), 1.0)[1])
  self:assert_true((schema.integer():validate(3)))
  self:assert_true((schema.number():validate(3)))
  self:assert_true((schema.number():validate(3.5)))
  self:assert_equal(" type", codes(schema.number(), 0 / 0)[1])
  self:assert_equal(" type", codes(schema.number(), math.huge)[1])
end

function T:test_minimum_and_maximum_are_inclusive()
  local s = schema.integer({ minimum = 1, maximum = 3 })
  self:assert_true((s:validate(1)))
  self:assert_true((s:validate(3)))
  self:assert_equal(" minimum", codes(s, 0)[1])
  self:assert_equal(" maximum", codes(s, 4)[1])
end

function T:test_exclusive_bounds_reject_the_bound_itself()
  local s = schema.number({ exclusive_minimum = 1, exclusive_maximum = 3 })
  self:assert_true((s:validate(2)))
  self:assert_equal(" exclusive_minimum", codes(s, 1)[1])
  self:assert_equal(" exclusive_maximum", codes(s, 3)[1])
  self:assert_error(function() schema.integer({ exclusive_minimum = 3, exclusive_maximum = 1 }) end)
end

function T:test_unique_items_reports_the_first_duplicate()
  local s = schema.array(schema.object({ a = schema.integer() }), { unique_items = true })
  self:assert_true((s:validate({ { a = 1 }, { a = 2 } })))
  self:assert_equal("/1 unique_items", codes(s, { { a = 1 }, { a = 1 }, { a = 1 } })[1])
  self:assert_true((schema.array(schema.integer()):validate({ 1, 1 })))
end

function T:test_string_length_counts_code_points()
  local s = schema.string({ min_length = 2, max_length = 3 })
  self:assert_true((s:validate("\u{e9}\u{e9}")))
  self:assert_equal(" min_length", codes(s, "a")[1])
  self:assert_equal(" max_length", codes(s, "abcd")[1])
  self:assert_equal(" invalid_utf8", codes(s, "\xff\xfe")[1])
end

function T:test_pattern()
  local s = schema.string({ pattern = "^%d+$" })
  self:assert_true((s:validate("123")))
  self:assert_equal(" pattern", codes(s, "12a")[1])
end

function T:test_enumeration_and_literal()
  local e = schema.enumeration({ "a", "b", 3 })
  self:assert_true((e:validate("b")))
  self:assert_true((e:validate(3)))
  self:assert_equal(" enum", codes(e, "c")[1])
  local l = schema.literal("ok")
  self:assert_true((l:validate("ok")))
  self:assert_equal(" literal", codes(l, "no")[1])
  self:assert_equal(" literal", codes(schema.literal(1), 1.0)[1])
end

function T:test_object_collects_all_errors_with_pointers()
  local s = schema.object({
    name = schema.string({ min_length = 1 }),
    age = schema.integer({ minimum = 0 }),
    tags = schema.array(schema.string()),
  })
  local got = codes(s, { name = "", age = -1, tags = { "a", 2, "b", 3 } })
  self:assert_equal(4, #got)
  self:assert_equal("/age minimum", got[1])
  self:assert_equal("/name min_length", got[2])
  self:assert_equal("/tags/1 type", got[3])
  self:assert_equal("/tags/3 type", got[4])
end

function T:test_missing_required_and_unknown_properties()
  local s = schema.object({ a = schema.integer(), b = schema.optional(schema.integer()) })
  local got = codes(s, { c = 1 })
  self:assert_equal("/a required", got[1])
  self:assert_equal("/c additional_property", got[2])
  self:assert_equal(2, #got)
  self:assert_true((s:validate({ a = 1 })))
end

function T:test_additional_properties_can_be_allowed()
  local s = schema.object({ a = schema.integer() }, { additional_properties = true })
  self:assert_true((s:validate({ a = 1, z = "free" })))
end

function T:test_pointer_tokens_are_escaped()
  local s = schema.object({ ["a/b"] = schema.integer(), ["m~n"] = schema.integer() })
  local got = codes(s, { ["a/b"] = "x", ["m~n"] = "y" })
  self:assert_equal("/a~1b type", got[1])
  self:assert_equal("/m~0n type", got[2])
end

function T:test_nested_paths()
  local s = schema.object({ user = schema.object({ emails = schema.array(schema.string({ pattern = "@" })) }) })
  local got = codes(s, { user = { emails = { "a@b", "nope" } } })
  self:assert_equal("/user/emails/1 pattern", got[1])
end

function T:test_array_bounds_and_shape()
  local s = schema.array(schema.integer(), { min_items = 1, max_items = 2 })
  self:assert_equal(" min_items", codes(s, {})[1])
  self:assert_equal(" max_items", codes(s, { 1, 2, 3 })[1])
  self:assert_equal(" type", codes(s, { a = 1 })[1])
  self:assert_equal(" type", codes(s, "x")[1])
end

function T:test_object_rejects_non_tables_and_arrays_with_non_string_keys()
  self:assert_equal(" type", codes(schema.object({}), 1)[1])
  self:assert_equal(" type", codes(schema.object({}), { 1, 2 })[1])
end

function T:test_optional_and_nullable_are_distinct()
  local s = schema.object({ a = schema.nullable(schema.integer()), b = schema.optional(schema.integer()) })
  self:assert_true((s:validate({ a = json.null })))
  self:assert_equal("/b type", codes(s, { a = 1, b = json.null })[1])
  self:assert_equal("/a required", codes(s, {})[1])
  self:assert_equal("/a type", codes(s, { a = "x" })[1])
end

function T:test_union_accepts_any_alternative_and_reports_one_violation()
  local s = schema.union({ schema.string(), schema.integer({ minimum = 0 }) })
  self:assert_true((s:validate("x")))
  self:assert_true((s:validate(2)))
  local ok, violations = s:validate(-1)
  self:assert_false(ok)
  self:assert_equal(1, #violations)
  self:assert_equal("union", violations[1].code)
  self:assert_equal(2, #violations[1].context.alternatives)
  self:assert_equal("minimum", violations[1].context.alternatives[2][1].code)
end

function T:test_check_raises_a_validation_error_carrying_the_violations()
  local err = self:assert_error(function() schema.integer():check("x") end)
  self:assert_true(core.is_instance_of(err, core.ValidationError))
  self:assert_equal(1, #err.context.violations)
  self:assert_equal("type", err.context.violations[1].code)
  self:assert_equal(5, schema.integer():check(5))
end

function T:test_schemas_are_immutable()
  local s = schema.string()
  self:assert_error(function() s.kind = "integer" end)
  local o = schema.object({ a = schema.string() })
  self:assert_error(function() o.properties.a = nil end)
end

function T:test_members_returns_a_copy()
  local u = schema.union({ schema.string(), schema.integer() })
  local list = u:members()
  list[1] = nil
  self:assert_equal(2, #u:members())
  self:assert_equal(3, #schema.enumeration({ "a", "b", "c" }):members())
end

function T:test_the_property_table_is_copied_at_construction()
  local props = { a = schema.integer() }
  local s = schema.object(props)
  props.b = schema.integer()
  self:assert_true((s:validate({ a = 1 })))
end

function T:test_invalid_declarations_are_argument_errors()
  local function refused(fn)
    local err = self:assert_error(fn)
    self:assert_equal("hecate.core.ArgumentError", err.code)
  end
  refused(function() return schema.integer({ minimun = 1 }) end)
  refused(function() return schema.integer({ minimum = "1" }) end)
  refused(function() return schema.integer({ minimum = 3, maximum = 1 }) end)
  refused(function() return schema.string({ pattern = "[" }) end)
  refused(function() return schema.object({ a = 1 }) end)
  refused(function() return schema.array("x") end)
  refused(function() return schema.union({}) end)
  refused(function() return schema.enumeration({}) end)
  refused(function() return schema.literal({}) end)
  refused(function() return schema.optional(schema.optional(schema.string())) end)
end

function T:test_json_null_is_neither_an_array_nor_an_object()
  self:assert_equal(" type", codes(schema.array(schema.string()), json.null)[1])
  self:assert_equal(" type", codes(schema.object({}), json.null)[1])
  self:assert_true((schema.nullable(schema.array(schema.string())):validate(json.null)))
end

function T:test_violation_formats()
  local _, violations = schema.integer({ minimum = 1 }):validate(0)
  self:assert_equal('"": minimum: ' .. violations[1].message, tostring(violations[1]))
  self:assert_equal(1, violations[1].context.minimum)
end

function T:test_multiple_of()
  local s = schema.integer({ multiple_of = 3 })
  self:assert_true((s:validate(6)))
  self:assert_equal(" multiple_of", codes(s, 7)[1])
  self:assert_error(function() schema.integer({ multiple_of = 0 }) end)
  self:assert_error(function() schema.number({ multiple_of = -1 }) end)
  self:assert_error(function() schema.number({ multiple_of = 0.1 }) end)
  self:assert_error(function() schema.integer({ multiple_of = 2.5 }) end)
  self:assert_equal(true, schema.number({ multiple_of = 5.0 }):validate(10.0))
end

function T:test_map()
  local s = schema.map(schema.integer({ minimum = 0 }), { max_properties = 3 })
  self:assert_true((s:validate({})))
  self:assert_true((s:validate({ a = 1, b = 2 })))
  self:assert_equal("/a~1b minimum", codes(s, { ["a/b"] = -1 })[1])
  self:assert_equal("/x type", codes(s, { x = "s" })[1])
  self:assert_equal(" max_properties", codes(s, { a = 1, b = 1, c = 1, d = 1 })[1])
  self:assert_equal(" type", codes(s, { 1, 2 })[1])
  self:assert_equal(" type", codes(s, json.null)[1])
  self:assert_equal(" type", codes(s, "x")[1])
  self:assert_error(function() schema.map(1) end)
  self:assert_error(function() schema.map(schema.string(), { min_properties = 2, max_properties = 1 }) end)
  local ok, converted = schema.map(schema.integer()):coerce({ a = "1" })
  self:assert_true(ok)
  self:assert_equal(1, converted.a)
end

function T:test_format_uuid_date_date_time_email()
  local cases = {
    uuid = { "123e4567-e89b-12d3-a456-426614174000", "123E4567-E89B-12D3-A456-426614174000" },
    date = { "2026-11-03", "2024-02-29" },
    ["date-time"] = { "2026-11-03T12:00:00Z", "2026-11-03t12:00:00.5+01:00" },
    email = { "a@b.co", "first.last+tag@example.org" },
    ipv4 = { "0.0.0.0", "192.168.1.255" },
    uri = { "https://example.org/a?b=c#d", "mailto:a@b.co", "urn:isbn:0451450523", "http://x/%C3%A9" },
  }
  local bad = {
    uuid = { "123e4567e89b12d3a456426614174000", "123e4567-e89b-12d3-a456-42661417400g" },
    date = { "2026-13-01", "2025-02-29", "2026-1-1", "2026-11-31" },
    ["date-time"] = { "2026-11-03", "2026-11-03T25:00:00Z", "2026-11-03T12:00:00" },
    email = { "a", "@b.co", "a@", "a b@c.d", "a@b@c" },
    uri = { "example.org", "/relative", "http://x/a b", "http://x/%zz", "http://x/%4", "1http://x", "http://x/é" },
    ipv4 = { "1.2.3", "1.2.3.4.5", "256.1.1.1", "01.2.3.4", "1.2.3.-4", "1..2.3", "a.b.c.d" },
  }
  for format, good in pairs(cases) do
    local s = schema.string({ format = format })
    for _, v in ipairs(good) do self:assert_true((s:validate(v)), format .. " " .. v) end
    for _, v in ipairs(bad[format]) do self:assert_equal(" format", codes(s, v)[1], format .. " " .. v) end
    self:assert_equal(" type", codes(s, 1)[1])
  end
end

function T:test_format_unknown_is_refused()
  local ok, err = pcall(schema.string, { format = "nope" })
  self:assert_false(ok)
  self:assert_true(core.is_instance_of(err, core.ArgumentError))
end

-- JSON Schema `type: object` and `type: array` exclude each other (official suite, `type.json`): a decoded array is
-- not an object and a decoded object is not an array, even when empty or when additional properties are allowed.
function T:test_marked_arrays_and_objects_are_not_confused()
  local open_object = schema.object({}, { additional_properties = true })
  local list = schema.array(schema.any())
  local map = schema.map(schema.any())
  for _, array in ipairs({ json.decode("[]"), json.decode("[1,2]") }) do
    self:assert_false((open_object:validate(array)))
    self:assert_false((map:validate(array)))
    self:assert_true((list:validate(array)))
  end
  for _, object in ipairs({ json.decode("{}"), json.decode('{"a":1}') }) do
    self:assert_true((open_object:validate(object)))
    self:assert_true((map:validate(object)))
    self:assert_false((list:validate(object)))
  end
  self:assert_true((open_object:validate({})))
  self:assert_true((list:validate({})))
end

return T
