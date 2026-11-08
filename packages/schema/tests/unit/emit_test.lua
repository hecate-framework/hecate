---@diagnostic disable: need-check-nil, param-type-mismatch  -- the tests index emitted tables they just asserted exist
local test = require("harness.test")
local core = require("hecate.core")
local json = require("hecate.json")
local schema = require("hecate.schema")
local T = test.Case("SchemaEmitTest")

local null = json.null
local math_type = math.type

-- The independent checker of the emitted keywords (tests/support/conforms.lua), itself validated against the official
-- JSON Schema test suite in `json_schema_suite_test.lua`.
local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or "."
local conforms = dofile(here .. "/../support/conforms.lua").conforms

local VALUES = {
  "", "a", "abc", "abcd", "\u{e9}\u{e9}", "\u{1F600}", 0, 1, 2, 3, 4, -1, 1.5, 2.5, true, false, null,
  {}, { 1 }, { 1, 2 }, { 1, 2, 3 }, { "a", "b" }, { "a", 1 }, { null }, { { 1 } },
  { name = "x" }, { name = "x", age = 3 }, { name = "x", age = 3.5 }, { name = 1 }, { age = 3 },
  { name = "x", nick = null }, { name = "x", nick = "n" }, { name = "x", extra = true }, { name = "x", tags = { "a" } },
  { name = "x", tags = { 1 } }, { kind = "a", x = 1 }, { kind = "a", x = "s" }, { kind = "b" }, { kind = "b", y = 1 },
  { kind = "c" }, { kind = 1 }, { x = 1 }, { name = "x", level = 2 }, { name = "x", level = "2" }, { a = { b = 1 } }, { a = { b = "s" } }, { [1] = "a", x = 1 },
}

local function differential(self, label, s)
  local emitted = s:to_json_schema()
  for i, value in ipairs(VALUES) do
    local lua_ok = s:validate(value)
    local json_ok = conforms(emitted, value)
    self:assert_equal(lua_ok, json_ok, ("%s: value #%d disagrees"):format(label, i))
  end
end

function T:test_base_types()
  self:assert_equal("string", schema.string():to_json_schema().type)
  self:assert_equal("integer", schema.integer():to_json_schema().type)
  self:assert_equal("number", schema.number():to_json_schema().type)
  self:assert_equal("boolean", schema.boolean():to_json_schema().type)
end

function T:test_root_declares_the_dialect_and_nested_schemas_do_not()
  local emitted = schema.array(schema.string()):to_json_schema()
  self:assert_equal("https://json-schema.org/draft/2020-12/schema", emitted["$schema"])
  self:assert_nil(emitted.items["$schema"])
end

function T:test_refinements_map_to_validation_keywords()
  local s = schema.string({ min_length = 1, max_length = 5 }):to_json_schema()
  self:assert_equal(1, s.minLength)
  self:assert_equal(5, s.maxLength)
  local n = schema.integer({ minimum = 0, maximum = 9 }):to_json_schema()
  self:assert_equal(0, n.minimum)
  self:assert_equal(9, n.maximum)
  local a = schema.array(schema.integer(), { min_items = 1, max_items = 2 }):to_json_schema()
  self:assert_equal(1, a.minItems)
  self:assert_equal(2, a.maxItems)
  self:assert_equal("integer", a.items.type)
end

function T:test_literal_and_enumeration()
  self:assert_equal("x", schema.literal("x"):to_json_schema().const)
  self:assert_equal(null, schema.literal(null):to_json_schema().const)
  local e = schema.enumeration({ "a", "b", 3 }):to_json_schema()
  self:assert_equal(3, #e.enum)
  self:assert_equal("b", e.enum[2])
end

function T:test_object_required_and_additional_properties()
  local s = schema.object({ name = schema.string(), age = schema.optional(schema.integer()) }):to_json_schema()
  self:assert_equal("object", s.type)
  self:assert_equal("string", s.properties.name.type)
  self:assert_equal("integer", s.properties.age.type) -- `optional` is not a keyword of its own
  self:assert_equal(1, #s.required)
  self:assert_equal("name", s.required[1])
  self:assert_equal(false, s.additionalProperties)
  local open = schema.object({}, { additional_properties = true }):to_json_schema()
  self:assert_equal(true, open.additionalProperties)
  self:assert_nil(open.required)
end

function T:test_required_is_sorted()
  local s = schema.object({ b = schema.string(), a = schema.string(), c = schema.string() }):to_json_schema()
  self:assert_equal("a,b,c", table.concat(s.required, ","))
end

function T:test_nullable_and_union_are_any_of()
  local n = schema.nullable(schema.string()):to_json_schema()
  self:assert_equal(2, #n.anyOf)
  self:assert_equal("string", n.anyOf[1].type)
  self:assert_equal("null", n.anyOf[2].type)
  local u = schema.union({ schema.string(), schema.integer() }):to_json_schema()
  self:assert_equal("integer", u.anyOf[2].type)
end

function T:test_emission_is_encodable_and_stable()
  local s = schema.object({
    name = schema.string({ min_length = 1 }),
    tags = schema.optional(schema.array(schema.enumeration({ "a", "b" }))),
    nick = schema.nullable(schema.string()),
    kind = schema.literal(null),
  })
  local text = json.encode(s:to_json_schema(), { canonical = true })
  self:assert_equal(text, json.encode(s:to_json_schema(), { canonical = true }))
  local decoded = json.decode(text)
  self:assert_equal("object", decoded.type)
  self:assert_equal(null, decoded.properties.kind.const)
end

function T:test_emission_is_a_fresh_table_each_call()
  local s = schema.object({ a = schema.string() })
  local first = s:to_json_schema()
  first.type = "tampered"
  self:assert_equal("object", s:to_json_schema().type)
end

function T:test_differential_base_and_refinements()
  differential(self, "string", schema.string())
  differential(self, "string length", schema.string({ min_length = 2, max_length = 3 }))
  differential(self, "integer", schema.integer({ minimum = 1, maximum = 3 }))
  differential(self, "number", schema.number({ minimum = 1.5 }))
  differential(self, "exclusive", schema.number({ exclusive_minimum = 1, exclusive_maximum = 3 }))
  differential(self, "multiple", schema.integer({ multiple_of = 2 }))
  differential(self, "multiple number", schema.number({ multiple_of = 5.0 }))
  differential(self, "map", schema.map(schema.integer()))
  differential(self, "map bounds", schema.map(schema.string(), { min_properties = 1, max_properties = 1 }))
  differential(self, "unique", schema.array(schema.integer(), { unique_items = true }))
  differential(self, "boolean", schema.boolean())
  differential(self, "literal", schema.literal("abc"))
  differential(self, "literal null", schema.literal(null))
  differential(self, "enumeration", schema.enumeration({ "a", 2, true, null }))
end

function T:test_differential_composites()
  differential(self, "array", schema.array(schema.integer()))
  differential(self, "array bounds", schema.array(schema.string(), { min_items = 1, max_items = 2 }))
  differential(self, "nullable", schema.nullable(schema.integer()))
  differential(self, "union", schema.union({ schema.string(), schema.integer({ minimum = 2 }), schema.array(schema.integer()) }))
  local person = schema.object({
    name = schema.string(),
    age = schema.optional(schema.integer({ minimum = 0 })),
    nick = schema.optional(schema.nullable(schema.string())),
    tags = schema.optional(schema.array(schema.string())),
  })
  differential(self, "object closed", person)
  differential(self, "object open", schema.object({ name = schema.string() }, { additional_properties = true }))
  differential(self, "object empty", schema.object({}))
  differential(self, "nested", schema.object({ a = schema.object({ b = schema.integer() }) }))
  differential(self, "array of objects", schema.array(person))
end

function T:test_differential_tagged_union_and_default()
  local shape = schema.tagged_union("kind", {
    a = schema.object({ x = schema.integer() }),
    b = schema.object({ y = schema.optional(schema.integer()) }, { additional_properties = true }),
  })
  differential(self, "tagged union", shape)
  differential(self, "array of tagged unions", schema.array(shape))
  differential(self, "default property", schema.object({ name = schema.string(), level = schema.default(schema.integer(), 1) }))
end

function T:test_tagged_union_emission()
  local emitted = schema.tagged_union("kind", {
    b = schema.object({}), a = schema.object({ x = schema.integer() }),
  }):to_json_schema()
  self:assert_equal(2, #emitted.oneOf)
  self:assert_equal("a", emitted.oneOf[1].properties.kind.const)
  self:assert_equal("b", emitted.oneOf[2].properties.kind.const)
  self:assert_equal("kind", emitted.oneOf[1].required[1])
  self:assert_equal("x", emitted.oneOf[1].required[2])
end

function T:test_default_emission()
  local emitted = schema.object({ level = schema.default(schema.integer(), 3) }):to_json_schema()
  self:assert_equal(3, emitted.properties.level.default)
  self:assert_equal("integer", emitted.properties.level.type)
  self:assert_equal(nil, emitted.required)
end

function T:test_documented_superset_for_float_valued_integers()
  -- OQ-85 (2): Lua `integer` refuses 1.0; JSON Schema section 6.1.1 cannot, so the emitted schema accepts it.
  self:assert_false((schema.integer():validate(1.0)))
  self:assert_true(conforms(schema.integer():to_json_schema(), 1.0))
  self:assert_equal("float", math_type(1.0))
end

function T:test_format_is_emitted()
  self:assert_equal("uuid", schema.string({ format = "uuid" }):to_json_schema().format)
end

return T
