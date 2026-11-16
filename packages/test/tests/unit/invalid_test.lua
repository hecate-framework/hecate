-- Generators of invalid values: a valid value broken in exactly one place, with the violation expected.
global <const> require, ipairs, pairs, table, os, type

local core = require("hecate.core")
local schema = require("hecate.schema")
local json = require("hecate.json")
local hecate_test = require("hecate.test")

local T = hecate_test.Case("InvalidTest")

local SCHEMAS = {
  integer = schema.integer({ minimum = -5, maximum = 5 }),
  integer_multiple = schema.integer({ minimum = 7, maximum = 100, multiple_of = 7 }),
  number = schema.number({ exclusive_minimum = 0, exclusive_maximum = 1 }),
  string = schema.string({ min_length = 2, max_length = 6 }),
  email = schema.string({ format = "email" }),
  boolean = schema.boolean(),
  null = schema.null(),
  literal = schema.literal("x"),
  enumeration = schema.enumeration({ "a", "b", "c" }),
  array = schema.array(schema.integer({ minimum = 0, maximum = 9 }), { min_items = 2, max_items = 4 }),
  unique = schema.array(schema.integer({ minimum = 0, maximum = 50 }), { min_items = 2, max_items = 4, unique_items = true }),
  map = schema.map(schema.integer({ minimum = 0, maximum = 9 }), { min_properties = 1, max_properties = 3 }),
  object = schema.object({
    id = schema.integer({ minimum = 1 }),
    name = schema.optional(schema.string({ min_length = 1 })),
    address = schema.object({ street = schema.string({ min_length = 1, max_length = 8 }) }),
    tags = schema.array(schema.string({ max_length = 3 })),
  }),
  nullable = schema.nullable(schema.integer()),
  union = schema.union({ schema.integer(), schema.string({ min_length = 1 }) }),
  pattern = schema.string({ pattern = "^%d+$" }),
  pattern_bounded = schema.string({ pattern = "^[a-f]+$", min_length = 2, max_length = 6 }),
  tagged = schema.tagged_union("kind", {
    circle = schema.object({ radius = schema.number({ minimum = 0 }) }),
    square = schema.object({ side = schema.integer({ minimum = 1 }) }),
  }),
}

function T:test_an_invalid_value_has_exactly_the_expected_violation()
  local names = {}
  for name in pairs(SCHEMAS) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    for seed = 1, 40 do
      local value, expected = hecate_test.generate_invalid(SCHEMAS[name], seed)
      local ok, violations = SCHEMAS[name]:validate(value)
      self:assert_false(ok, name .. ", seed " .. seed .. ": the value is valid")
      self:assert_equal(1, #violations, name .. ", seed " .. seed .. ": " .. #violations .. " violations")
      self:assert_equal(expected.code, violations[1].code)
      self:assert_equal(expected.path, violations[1].path)
    end
  end
end

function T:test_the_violations_cover_several_constraints()
  local seen = {}
  for seed = 1, 80 do
    local _, expected = hecate_test.generate_invalid(SCHEMAS.object, seed)
    seen[expected.code] = true
  end
  for _, code in ipairs({ "type", "required", "additional_properties", "minimum", "min_length", "max_length" }) do
    self:assert_true(seen[code], "never produced " .. code)
  end
end

function T:test_a_seed_gives_the_same_value()
  for seed = 1, 10 do
    local a, ea = hecate_test.generate_invalid(SCHEMAS.object, seed)
    local b, eb = hecate_test.generate_invalid(SCHEMAS.object, seed)
    self:assert_equal(json.encode(a), json.encode(b))
    self:assert_equal(ea.path .. ea.code, eb.path .. eb.code)
  end
end

function T:test_a_generator_yields_invalid_values_in_sequence()
  local g1, g2 = hecate_test.Generator(SCHEMAS.array, 5), hecate_test.Generator(SCHEMAS.array, 5)
  for _ = 1, 5 do
    local a, ea = g1:next_invalid()
    local b, eb = g2:next_invalid()
    self:assert_equal(json.encode(a), json.encode(b))
    self:assert_equal(ea.code, eb.code)
  end
end

function T:test_a_schema_that_accepts_everything_has_no_invalid_value()
  self:assert_error(function() hecate_test.generate_invalid(schema.any(), 1) end, { class = core.ArgumentError })
end

function T:test_a_huge_bound_does_not_allocate_it()
  local started = os.clock()
  local value = hecate_test.generate_invalid(schema.string({ max_length = 1000000000 }), 1)
  self:assert_true(type(value) ~= "string" or #value < 1000000)
  self:assert_true(os.clock() - started < 5)
end

return core.finalise(T)
