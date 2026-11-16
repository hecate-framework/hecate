-- The property runner: runs a property over generated values and shrinks a counterexample.
global <const> require, ipairs, pcall, error, table, math

local core = require("hecate.core")
local schema = require("hecate.schema")
local json = require("hecate.json")
local hecate_test = require("hecate.test")

local T = hecate_test.Case("PropertyTest")

function T:test_a_property_that_holds_passes_all_its_runs()
  local result = hecate_test.check_property(schema.integer({ minimum = 0, maximum = 1000 }),
    function(n) return n >= 0 and n <= 1000 end)
  self:assert_true(result.ok)
  self:assert_equal(100, result.runs)
  self:assert_equal(nil, result.counterexample)
  local few = hecate_test.check_property(schema.boolean(), function() return true end, { runs = 7 })
  self:assert_equal(7, few.runs)
end

function T:test_an_integer_counterexample_shrinks_to_the_boundary()
  local result = hecate_test.check_property(schema.integer({ minimum = 0, maximum = 100000 }),
    function(n) return n < 50 end)
  self:assert_false(result.ok)
  self:assert_equal(50, result.counterexample)
  self:assert_true(result.shrinks > 0)
  self:assert_true(result.original >= 50)
end

function T:test_a_string_counterexample_shrinks_to_the_shortest_failing_length()
  local result = hecate_test.check_property(schema.string({ max_length = 40 }), function(s) return #s < 3 end)
  self:assert_false(result.ok)
  self:assert_equal(3, #result.counterexample)
end

function T:test_an_array_counterexample_shrinks_to_one_element()
  local result = hecate_test.check_property(
    schema.array(schema.integer({ minimum = 0, maximum = 100 }), { max_items = 8 }),
    function(list)
      local sum = 0
      for _, n in ipairs(list) do sum = sum + n end
      return sum < 10
    end)
  self:assert_false(result.ok)
  self:assert_equal(1, #result.counterexample)
  self:assert_equal(10, result.counterexample[1])
end

function T:test_a_counterexample_still_conforms_to_the_schema()
  local s = schema.object({
    name = schema.string({ min_length = 2, max_length = 10 }),
    age = schema.integer({ minimum = 18, maximum = 99 }),
    tags = schema.optional(schema.array(schema.string({ min_length = 1 }), { min_items = 1 })),
  })
  local result = hecate_test.check_property(s, function(user) return user.age < 30 end)
  self:assert_false(result.ok)
  self:assert_true(s:validate(result.counterexample))
  self:assert_equal(30, result.counterexample.age)
  self:assert_equal(2, #result.counterexample.name)
end

function T:test_a_raising_property_is_a_failure_with_its_message()
  local result = hecate_test.check_property(schema.integer({ minimum = 0, maximum = 10 }),
    function(n) if n >= 0 then error("kaput", 0) end end)
  self:assert_false(result.ok)
  self:assert_match("kaput", result.failure)
end

function T:test_a_seed_reproduces_the_counterexample()
  local s = schema.array(schema.integer({ minimum = 0, maximum = 1000 }), { max_items = 6 })
  local function property(list) return #list < 3 end
  local a = hecate_test.check_property(s, property, { seed = 7 })
  local b = hecate_test.check_property(s, property, { seed = 7 })
  self:assert_equal(json.encode(a.counterexample), json.encode(b.counterexample))
  self:assert_equal(a.run, b.run)
end

function T:test_assert_property_passes_or_fails_with_the_seed_and_counterexample()
  self:assert_property(schema.boolean(), function() return true end)
  local ok, err = pcall(function()
    self:assert_property(schema.integer({ minimum = 0, maximum = 1000 }), function(n) return n < 5 end, { seed = 3 })
  end)
  self:assert_false(ok)
  self:assert_true(core.is_instance_of(err, hecate_test.AssertionFailure))
  local message = (err --[[@as hecate.core.Error]]).message
  self:assert_match("seed 3", message)
  self:assert_match("counterexample 5", message)
end

function T:test_bad_arguments_raise_argument_error()
  local function bad(...) local args = { ... }
    self:assert_error(function() hecate_test.check_property(table.unpack(args, 1, 3)) end, { class = core.ArgumentError })
  end
  bad({}, function() end)
  bad(schema.boolean(), "x")
  bad(schema.boolean(), function() end, { runs = 0 })
  bad(schema.boolean(), function() end, { seed = 1.5 })
  bad(schema.boolean(), function() end, { unknown = 1 })
end

function T:test_the_default_seed_is_the_same_for_generators_and_properties()
  local s = schema.integer({ minimum = 0, maximum = 1000000 })
  local first = hecate_test.generate(s)
  self:assert_equal(hecate_test.generate(s, 1), first)
  self:assert_equal(hecate_test.Generator(s):next(), first)
  self:assert_equal(hecate_test.generate_invalid(s), hecate_test.generate_invalid(s, 1))
  local result = hecate_test.check_property(s, function() return false end)
  self:assert_equal(1, result.seed)
  self:assert_equal(first, result.original)
end

function T:test_shrinking_stops_within_its_budget_and_when_nothing_gets_simpler()
  local always = hecate_test.check_property(schema.integer({ minimum = 0, maximum = 1000000 }),
    function() return false end, { max_shrinks = 5 })
  self:assert_false(always.ok)
  self:assert_true(always.shrinks <= 5)
  local evens = hecate_test.check_property(schema.integer({ minimum = 0, maximum = 1000 }),
    function(n) return n % 2 == 1 end)
  self:assert_false(evens.ok)
  self:assert_equal(0, evens.counterexample % 2)
end

function T:test_unions_nullables_maps_and_tagged_unions_shrink_and_stay_valid()
  local cases = {
    schema.map(schema.integer({ minimum = 0, maximum = 9 }), { min_properties = 1, max_properties = 6 }),
    schema.nullable(schema.integer({ minimum = 0, maximum = 1000 })),
    schema.union({ schema.integer({ minimum = 0, maximum = 1000 }), schema.string({ min_length = 1, max_length = 20 }) }),
    schema.tagged_union("kind", {
      a = schema.object({ n = schema.integer({ minimum = 0, maximum = 1000 }) }),
      b = schema.object({ s = schema.string({ max_length = 20 }) }),
    }),
  }
  for index, s in ipairs(cases) do
    local result = hecate_test.check_property(s, function(value) return value == json.null end)
    self:assert_false(result.ok, "schema " .. index)
    self:assert_true(s:validate(result.counterexample), "the counterexample of schema " .. index .. " is not valid")
  end
end

function T:test_different_seeds_give_different_values()
  local s = schema.integer({ minimum = 0, maximum = 1000000 })
  local first = hecate_test.check_property(s, function() return false end, { seed = 1 })
  local second = hecate_test.check_property(s, function() return false end, { seed = 2 })
  self:assert_true(first.original ~= second.original)
end

function T:test_a_property_that_changes_its_value_does_not_corrupt_the_counterexample()
  local s = schema.array(schema.integer({ minimum = 0, maximum = 100 }), { min_items = 1, max_items = 6 })
  local result = hecate_test.check_property(s, function(list)
    local fails = #list >= 1
    list[#list + 1] = -1 -- the property abuses its argument
    return not fails
  end)
  self:assert_false(result.ok)
  self:assert_true(s:validate(result.original), "the original value was changed by the property")
  self:assert_true(s:validate(result.counterexample))
end

return core.finalise(T)
