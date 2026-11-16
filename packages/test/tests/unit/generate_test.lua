-- Generators of valid values from a schema (the basis of property-based tests).
global <const> require, ipairs, pairs, table, math, pcall

local core = require("hecate.core")
local schema = require("hecate.schema")
local json = require("hecate.json")
local hecate_test = require("hecate.test")

local T = hecate_test.Case("GenerateTest")

local function address() return schema.object({ street = schema.string({ min_length = 1, max_length = 8 }) }) end

local SCHEMAS = {
  integer = schema.integer({ minimum = -5, maximum = 5 }),
  integer_open = schema.integer(),
  integer_lower = schema.integer({ minimum = 100 }),
  integer_exclusive = schema.integer({ exclusive_minimum = 0, exclusive_maximum = 3 }),
  integer_multiple = schema.integer({ minimum = 1, maximum = 100, multiple_of = 7 }),
  number = schema.number({ minimum = 0, maximum = 1 }),
  number_exclusive = schema.number({ exclusive_minimum = 0, exclusive_maximum = 1 }),
  number_multiple = schema.number({ minimum = 0, maximum = 10, multiple_of = 2 }),
  string = schema.string({ min_length = 2, max_length = 6 }),
  string_open = schema.string(),
  uuid = schema.string({ format = "uuid" }),
  date = schema.string({ format = "date" }),
  date_time = schema.string({ format = "date-time" }),
  email = schema.string({ format = "email" }),
  uri = schema.string({ format = "uri" }),
  ipv4 = schema.string({ format = "ipv4" }),
  boolean = schema.boolean(),
  null = schema.null(),
  any = schema.any(),
  literal = schema.literal("x"),
  enumeration = schema.enumeration({ "a", "b", "c" }),
  array = schema.array(schema.integer({ minimum = 0, maximum = 9 }), { min_items = 2, max_items = 4 }),
  unique = schema.array(schema.integer({ minimum = 0, maximum = 5 }), { min_items = 3, max_items = 5, unique_items = true }),
  map = schema.map(schema.integer({ minimum = 0, maximum = 9 }), { min_properties = 1, max_properties = 3 }),
  object = schema.object({
    id = schema.integer({ minimum = 1 }),
    name = schema.optional(schema.string({ min_length = 1 })),
    tags = schema.default(schema.array(schema.string({ max_length = 3 })), {}),
    address = address(),
  }),
  nullable = schema.nullable(schema.integer()),
  union = schema.union({ schema.integer(), schema.string({ min_length = 1 }) }),
  tagged = schema.tagged_union("kind", {
    circle = schema.object({ radius = schema.number({ minimum = 0 }) }),
    square = schema.object({ side = schema.integer({ minimum = 1 }) }),
  }),
  named = schema.named("Address", address()),
  pattern_digits = schema.string({ pattern = "^%d+$" }),
  pattern_code = schema.string({ pattern = "^%u%u%d%d%d$" }),
  pattern_set = schema.string({ pattern = "^[a-f0-9]+$", min_length = 4, max_length = 8 }),
  pattern_optional = schema.string({ pattern = "^%a+%-?%d?$" }),
  pattern_group = schema.string({ pattern = "^(%a%a)%1$" }),
  pattern_negated = schema.string({ pattern = "^%S+$" }),
  pattern_not_digit = schema.string({ pattern = "^[^%d]+$" }),
  pattern_any = schema.string({ pattern = "^.+$", max_length = 5 }),
  pattern_lazy = schema.string({ pattern = "^a-b$" }),
  pattern_unanchored = schema.string({ pattern = "%d%d" }),
  pattern_escaped = schema.string({ pattern = "^%$%d%.%d%d$" }),
  pattern_control = schema.string({ pattern = "^%c+$" }),
  pattern_range = schema.string({ pattern = "^[a-c%d_]*$" }),
  pattern_long = schema.string({ pattern = "^%d*$", min_length = 12, max_length = 14 }),
}

function T:test_generated_values_are_valid_for_the_schema()
  local names = {}
  for name in pairs(SCHEMAS) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    for seed = 1, 60 do
      local value = hecate_test.generate(SCHEMAS[name], seed)
      local ok, violations = SCHEMAS[name]:validate(value)
      self:assert_true(ok, ("%s, seed %d: %s"):format(name, seed,
        ok and "" or (violations[1].path .. " " .. violations[1].code)))
    end
  end
end

function T:test_a_seed_gives_the_same_value_and_seeds_differ()
  local s = SCHEMAS.object
  local seen = {}
  for seed = 1, 20 do
    local a, b = json.encode(hecate_test.generate(s, seed)), json.encode(hecate_test.generate(s, seed))
    self:assert_equal(a, b)
    seen[a] = true
  end
  local distinct = 0
  for _ in pairs(seen) do distinct = distinct + 1 end
  self:assert_true(distinct > 5, "too few distinct values: " .. distinct)
end

function T:test_a_generator_yields_a_reproducible_sequence()
  local g1, g2 = hecate_test.Generator(SCHEMAS.integer_open, 42), hecate_test.Generator(SCHEMAS.integer_open, 42)
  for _ = 1, 10 do self:assert_equal(g1:next(), g2:next()) end
end

function T:test_a_recursive_schema_terminates()
  local Node = core.class("GenNode", nil, { implements = { schema.Representable } })
  function Node.schema()
    return schema.object({ value = schema.integer(), children = schema.array(schema.of(Node)),
      next = schema.optional(schema.of(Node)) })
  end
  core.finalise(Node)
  local tree = schema.of(Node)
  for seed = 1, 20 do
    local ok, violations = tree:build(hecate_test.generate(tree, seed))
    self:assert_true(ok, ok and "" or violations[1].code)
  end
end

function T:test_what_cannot_be_generated_raises_argument_error()
  local function refused(s) self:assert_error(function() hecate_test.generate(s, 1) end, { class = core.ArgumentError }) end
  refused(schema.string({ pattern = "^%d$", min_length = 3 }))
  refused(schema.string({ pattern = "^%d+$", format = "email" }))
  refused(schema.array(schema.literal(1), { min_items = 2, unique_items = true }))
  ---@type any
  local not_a_schema = {}
  refused(not_a_schema)
end

function T:test_hostile_sizes_and_cycles_are_refused_quickly()
  local function refused(s) self:assert_error(function() hecate_test.generate(s, 1) end, { class = core.ArgumentError }) end
  refused(schema.string({ min_length = 1000000000 }))
  refused(schema.array(schema.integer(), { min_items = 1000000000 }))
  refused(schema.map(schema.integer(), { min_properties = 1000000000 }))
  refused(schema.string({ pattern = "^(a)(%1%1%1%1%1%1%1%1%1%1)(%2%2%2%2%2%2%2%2%2%2)(%3%3%3%3%3%3%3%3%3%3)"
    .. "(%4%4%4%4%4%4%4%4%4%4)(%5%5%5%5%5%5%5%5%5%5)(%6%6%6%6%6%6%6%6%6%6)(%7%7%7%7%7%7%7%7%7%7)"
    .. "(%8%8%8%8%8%8%8%8%8%8)(%9%9%9%9%9%9%9%9%9%9)$" }))
  local Node = core.class("RequiredNode", nil, { implements = { schema.Representable } })
  function Node.schema() return schema.object({ next = schema.of(Node) }) end
  core.finalise(Node)
  refused(schema.of(Node))
end

function T:test_a_large_bound_gives_short_values()
  for seed = 1, 20 do
    local text = hecate_test.generate(schema.string({ max_length = 1000000000 }), seed)
    self:assert_true(#text <= 300)
    local list = hecate_test.generate(schema.array(schema.integer(), { max_items = 1000000000 }), seed)
    self:assert_true(#list <= 30)
  end
end

function T:test_the_bounds_of_a_schema_are_reached()
  local seen_low, seen_high, shortest, longest = false, false, math.huge, 0
  for seed = 1, 400 do
    local n = hecate_test.generate(schema.integer({ minimum = -5, maximum = 5 }), seed)
    seen_low, seen_high = seen_low or n == -5, seen_high or n == 5
    local text = hecate_test.generate(schema.string({ min_length = 2, max_length = 6 }), seed)
    shortest, longest = math.min(shortest, #text), math.max(longest, #text)
  end
  self:assert_true(seen_low and seen_high, "the ends of the integer range never came up")
  self:assert_equal(2, shortest)
  self:assert_equal(6, longest)
end

function T:test_bounds_that_no_value_satisfies_are_refused()
  local function refused(make)
    local ok, built = pcall(make)
    if not ok then return end -- the schema itself refuses this declaration: nothing to generate
    self:assert_error(function() hecate_test.generate(built, 1) end, { class = core.ArgumentError })
  end
  refused(function() return schema.string({ min_length = 5, max_length = 2 }) end)
  refused(function() return schema.integer({ minimum = 5, maximum = 2 }) end)
  refused(function() return schema.integer({ exclusive_minimum = 3, exclusive_maximum = 3 }) end)
  refused(function() return schema.integer({ minimum = 8, maximum = 9, multiple_of = 5 }) end)
  refused(function() return schema.array(schema.integer(), { min_items = 4, max_items = 1 }) end)
  refused(function() return schema.enumeration({}) end)
end

function T:test_boundary_values_come_up_often_not_by_chance()
  local s = schema.integer({ minimum = 0, maximum = 120 })
  local edges = 0
  for seed = 1, 200 do
    local n = hecate_test.generate(s, seed)
    if n == 0 or n == 120 then edges = edges + 1 end
  end
  self:assert_true(edges >= 12, "only " .. edges .. " of 200 values were at a bound")
  local empty = 0
  for seed = 1, 200 do
    if #hecate_test.generate(schema.string({ max_length = 20 }), seed) == 0 then empty = empty + 1 end
  end
  self:assert_true(empty >= 8, "only " .. empty .. " of 200 strings were empty")
end

return core.finalise(T)
