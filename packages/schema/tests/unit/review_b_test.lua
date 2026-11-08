---@diagnostic disable: need-check-nil, param-type-mismatch, undefined-field, inject-field, invisible, assign-type-mismatch
-- Fix pass B of the review of the `schema` item: stable violation codes (S5), the `members` method (S6), actionable
-- declaration and refusal messages (S12, x1), the type messages that name the received type, and `HasSchema` (x3).
local test = require("harness.test")
local core = require("hecate.core")
local json = require("hecate.json")
local schema = require("hecate.schema")
local T = test.Case("SchemaReviewBTest")

local function message_of(fn)
  local ok, caught = pcall(fn)
  if ok then error("expected an error", 2) end
  return tostring(caught.message or caught)
end

local function contains(text, part) return text:find(part, 1, true) ~= nil end

-- S5: the violation codes are stable ------------------------------------------------------------------------------------

--- The code of the first violation of `value` against `s`.
local function code_of(s, value)
  local ok, violations = s:validate(value)
  if ok then error("expected a violation", 2) end
  return violations[1].code
end

function T:test_every_documented_violation_code_is_emitted_by_its_kind()
  local cases = {
    { "type", schema.string(), 1 },
    { "required", schema.object({ a = schema.string() }), {} },
    { "additional_properties", schema.object({}), { a = 1 } },
    { "minimum", schema.integer({ minimum = 1 }), 0 },
    { "maximum", schema.integer({ maximum = 1 }), 2 },
    { "exclusive_minimum", schema.integer({ exclusive_minimum = 1 }), 1 },
    { "exclusive_maximum", schema.integer({ exclusive_maximum = 1 }), 1 },
    { "multiple_of", schema.integer({ multiple_of = 2 }), 3 },
    { "min_length", schema.string({ min_length = 2 }), "a" },
    { "max_length", schema.string({ max_length = 1 }), "ab" },
    { "invalid_utf8", schema.string({ min_length = 1 }), "\xff" },
    { "pattern", schema.string({ pattern = "^a$" }), "b" },
    { "format", schema.string({ format = "uuid" }), "x" },
    { "literal", schema.literal("a"), "b" },
    { "enum", schema.enumeration({ "a" }), "b" },
    { "min_items", schema.array(schema.string(), { min_items = 1 }), json.array({}) },
    { "max_items", schema.array(schema.string(), { max_items = 0 }), { "a" } },
    { "unique_items", schema.array(schema.string(), { unique_items = true }), { "a", "a" } },
    { "min_properties", schema.map(schema.string(), { min_properties = 1 }), json.object({}) },
    { "max_properties", schema.map(schema.string(), { max_properties = 0 }), { a = "b" } },
    { "union", schema.union({ schema.string(), schema.integer() }), true },
    { "tagged_union", schema.tagged_union("k", { a = schema.object({}) }), { k = "b" } },
  }
  for _, case in ipairs(cases) do
    self:assert_equal(case[1], code_of(case[2], case[3]), case[1])
  end
  local ok, violations = schema.integer():coerce("x")
  self:assert_false(ok)
  self:assert_equal("coercion", violations[1].code)
end

function T:test_the_old_singular_code_is_gone()
  local ok, violations = schema.object({}):validate({ a = 1 })
  self:assert_false(ok)
  self:assert_equal("additional_properties", violations[1].code)
  self:assert_equal("a", violations[1].context.property)
end

-- S6: members is a real method ------------------------------------------------------------------------------------------

function T:test_members_is_a_method_of_the_class_and_returns_fresh_lists()
  self:assert_equal("function", type(schema.Schema.members))
  local variants = schema.tagged_union("k", { b = schema.object({}), a = schema.object({}) })
  local names = variants:members()
  self:assert_equal("a", names[1])
  self:assert_equal("b", names[2])
  names[1] = "changed"
  self:assert_equal("a", variants:members()[1])
  self:assert_equal(0, #schema.string():members())
end

-- x1 and S12: messages that say what to do ----------------------------------------------------------------------------

function T:test_an_unknown_option_lists_the_accepted_ones()
  local text = message_of(function() schema.integer({ minimun = 1 }) end)
  self:assert_true(contains(text, "unknown option minimun"), text)
  self:assert_true(contains(text, "accepted options: exclusive_maximum, exclusive_minimum, maximum, minimum, multiple_of"), text)
end

function T:test_an_unknown_format_lists_the_accepted_ones()
  local text = message_of(function() schema.string({ format = "phone" }) end)
  self:assert_true(contains(text, "unknown format phone"), text)
  self:assert_true(contains(text, "accepted formats: date, date-time, email, ipv4, uri, uuid"), text)
end

function T:test_an_option_of_the_wrong_type_names_the_received_type()
  local text = message_of(function() schema.integer({ minimum = "1" }) end)
  self:assert_true(contains(text, "option minimum must be a number, got string"), text)
end

function T:test_a_malformed_pattern_message_shows_the_pattern_and_the_lua_error()
  local text = message_of(function() schema.string({ pattern = "ab%" }) end)
  self:assert_true(contains(text, '"ab%"'), text)
  self:assert_true(contains(text, "ends with '%'"), text)
  self:assert_true(contains(text, "Lua pattern"), text)
end

function T:test_a_default_that_does_not_conform_says_where_and_why()
  local text = message_of(function() schema.default(schema.integer({ minimum = 1 }), 0) end)
  self:assert_true(contains(text, 'first violation at "": the value is less than 1'), text)
  local nested = message_of(function()
    schema.default(schema.object({ a = schema.integer() }), { a = "x" })
  end)
  self:assert_true(contains(nested, "first violation at /a: expected integer, got string"), nested)
end

function T:test_type_messages_name_the_received_type_and_never_echo_the_value()
  local function message(s, value)
    local _, violations = s:validate(value)
    return violations[1].message
  end
  self:assert_equal("expected integer, got string", message(schema.integer(), "secret-value"))
  self:assert_equal("expected string, got table", message(schema.string(), {}))
  self:assert_equal("expected boolean, got null", message(schema.boolean(), json.null))
  self:assert_equal("expected object, got number", message(schema.object({}), 7))
  self:assert_equal("expected array, got boolean", message(schema.array(schema.string()), true))
  self:assert_equal("expected null, got string", message(schema.null(), "x"))
  self:assert_equal("expected number, got string", message(schema.number(), "x"))
  local whole = message(schema.integer(), 1.0)
  self:assert_true(contains(whole, "expected integer, got number"), whole)
  self:assert_true(contains(whole, "a whole float is refused"), whole)
  self:assert_false(contains(message(schema.integer(), 1.5), "whole float"))
  local _, violations = schema.integer():validate("secret-value")
  self:assert_equal("string", violations[1].context.received)
  self:assert_equal("integer", violations[1].context.expected)
end

function T:test_the_coercion_message_reads_an_integer()
  local _, violations = schema.integer():coerce("abc")
  self:assert_equal("the text is not an integer", violations[1].message)
  local _, numbers = schema.number():coerce("abc")
  self:assert_equal("the text is not a number", numbers[1].message)
end

function T:test_a_refused_pattern_says_lua_validation_still_works_and_how_to_rewrite()
  local s = schema.string({ pattern = "%bxy" })
  self:assert_true((s:validate("x(y")) ~= nil)
  local text = message_of(function() return s:to_json_schema() end)
  self:assert_true(contains(text, "%bxy"), text)
  self:assert_true(contains(text, "Lua validation is unaffected"), text)
  self:assert_true(contains(text, 'section "The `pattern` option"'), text)
  for _, word in ipairs({ "sets", "classes", "format", "min_length", "enum" }) do
    self:assert_true(contains(text, word), word .. " in " .. text)
  end
  local err = self:assert_error(function() return s:to_json_schema() end)
  self:assert_equal("pattern", err.context.option)
  self:assert_true(contains(err.context.reason, "%b has no exact translation"), err.context.reason)
end

function T:test_the_logger_warning_carries_the_pattern_and_the_reason_in_its_text()
  local warnings = {}
  local logger = { warning = function(_, message, fields) warnings[#warnings + 1] = { message, fields } end }
  schema.string({ pattern = "%bxy", logger = logger })
  self:assert_equal(1, #warnings)
  self:assert_equal(("schema: pattern %q cannot be emitted: %s"):format("%bxy", "%b has no exact translation"), warnings[1][1])
  self:assert_equal("%bxy", warnings[1][2].pattern)
  self:assert_equal("%b has no exact translation", warnings[1][2].reason)
end

-- x3: the interface of a class that has a schema -------------------------------------------------------------------------

function T:test_has_schema_is_an_interface_requiring_a_schema_function()
  self:assert_true(core.is_interface(schema.HasSchema))
end

function T:test_a_class_declaring_the_interface_without_schema_is_refused_at_finalisation()
  local Incomplete = core.class("Incomplete", nil, { implements = { schema.HasSchema } })
  local err = self:assert_error(function() core.finalise(Incomplete) end)
  self:assert_true(core.is_instance_of(err, core.ConformanceError))
end

function T:test_a_class_declaring_the_interface_works_with_of()
  local Point = core.class("Point", nil, { implements = { schema.HasSchema } })
  function Point.schema() return schema.object({ x = schema.integer() }) end
  core.finalise(Point)
  local ok, point = schema.of(Point):build({ x = 3 })
  self:assert_true(ok)
  self:assert_equal(3, point.x)
end

function T:test_of_still_accepts_a_class_that_does_not_declare_the_interface()
  local Plain = core.class("PlainClass")
  function Plain.schema() return schema.object({ x = schema.integer() }) end
  core.finalise(Plain)
  self:assert_true((schema.of(Plain):validate({ x = 3 })))
  local NoSchema = core.class("NoSchemaClass")
  core.finalise(NoSchema)
  local text = message_of(function() schema.of(NoSchema):validate({}) end)
  self:assert_true(contains(text, "schema()"), text)
end

return T
