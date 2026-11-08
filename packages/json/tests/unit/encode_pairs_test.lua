-- The encoder honours the `__pairs` metamethod of a table that defines one (OQ-94): the standard iteration
-- protocol, so that a frozen value object (attributes in a hidden table behind `__pairs`) and any user-built proxy
-- encode as the entries they iterate. A table without `__pairs` keeps the raw fast path. The rules for keys, arrays,
-- limits and failures are those of raw tables.
local test = require("harness.test")
local core = require("hecate.core")
local json = require("hecate.json")
local T = test.Case("JsonEncodePairsTest")

--- A table with no entries of its own whose iteration yields `entries`.
local function proxy(entries)
  return setmetatable({}, {
    __pairs = function() return next, entries, nil end,
  })
end

local function fails(self, value, reason, options)
  local err = self:assert_error(function() return json.encode(value, options) end)
  self:assert_true(core.is_instance_of(err, json.EncodeError), tostring(err))
  self:assert_equal(reason, err.context.reason)
  return err
end

local Point = core.value_class("PointForEncode")
function Point:init(x, y, extra) self.x, self.y, self.extra = x, y, extra end
core.finalise(Point)

function T:test_frozen_value_object_encodes_as_its_attributes()
  local text = json.encode(Point(1, 2), { canonical = true })
  self:assert_equal('{"x":1,"y":2}', text)
end

function T:test_value_object_attributes_of_every_kind()
  local inner = Point(1.5, true)
  local object = Point("text", false, { list = { 1, 2, 3 }, nested = inner, flag = json.null })
  local decoded = json.decode(json.encode(object))
  self:assert_equal("text", decoded.x)
  self:assert_equal(false, decoded.y)
  self:assert_equal(3, #decoded.extra.list)
  self:assert_equal(1.5, decoded.extra.nested.x)
  self:assert_equal(true, decoded.extra.nested.y)
  self:assert_equal(json.null, decoded.extra.flag)
end

function T:test_value_object_with_no_attribute_is_an_empty_object()
  local Empty = core.value_class("EmptyForEncode")
  core.finalise(Empty)
  self:assert_equal("{}", json.encode(Empty()))
end

function T:test_pretty_and_canonical_apply_to_a_proxy()
  local value = proxy({ b = 1, a = { c = 2 } })
  self:assert_equal('{"a":{"c":2},"b":1}', json.encode(value, { canonical = true }))
  self:assert_equal('{\n  "a": {\n    "c": 2\n  },\n  "b": 1\n}', json.encode(value, { canonical = true, pretty = true }))
end

function T:test_proxy_in_a_raw_table_and_raw_table_in_a_proxy()
  local value = { proxy({ k = "v" }), proxy({ inner = { 1, 2 } }) }
  self:assert_equal('[{"k":"v"},{"inner":[1,2]}]', json.encode(value))
end

function T:test_pairs_result_is_an_array_when_it_is_a_sequence()
  -- Same rule as a raw table: all keys positive indices make an array.
  self:assert_equal("[10,20,30]", json.encode(proxy({ 10, 20, 30 })))
end

function T:test_pairs_result_with_holes_follows_the_raw_rule()
  self:assert_equal("[1,null,3]", json.encode(proxy({ [1] = 1, [3] = 3 })))
  fails(self, proxy({ [1000] = 1 }), "ambiguous_table")
end

function T:test_empty_pairs_result_is_an_object()
  self:assert_equal("{}", json.encode(proxy({})))
end

function T:test_marked_proxy_keeps_its_marker_rule()
  -- A marker is the metatable: a marked table never has a `__pairs`, and stays on the raw path.
  self:assert_equal("[]", json.encode(json.array()))
  self:assert_equal("{}", json.encode(json.object()))
end

function T:test_key_rules_are_those_of_raw_tables()
  fails(self, proxy({ a = 1, [1] = 2 }), "ambiguous_table")
  fails(self, proxy({ [true] = 1 }), "ambiguous_table")
  fails(self, proxy({ [1.5] = 1 }), "ambiguous_table")
end

function T:test_non_finite_numbers_and_unsupported_values_stay_refused_with_their_path()
  local err = fails(self, proxy({ a = { b = 0 / 0 } }), "non_finite_number")
  self:assert_equal("/a/b", err.context.path)
  fails(self, proxy({ a = math.huge }), "non_finite_number")
  fails(self, proxy({ a = print }), "unsupported_type")
end

function T:test_a_table_without_pairs_but_with_a_metatable_is_read_raw()
  local value = setmetatable({ a = 1 }, { __index = { b = 2 } })
  self:assert_equal('{"a":1}', json.encode(value))
  local non_function = setmetatable({ a = 1 }, { __pairs = "not a function" })
  self:assert_equal('{"a":1}', json.encode(non_function))
end

function T:test_an_error_raised_by_pairs_is_the_original_error()
  local value = setmetatable({}, { __pairs = function() error("boom from pairs", 0) end })
  local err = self:assert_error(function() return json.encode(value) end)
  self:assert_true(tostring(err):find("boom from pairs", 1, true) ~= nil, tostring(err))
end

function T:test_an_error_raised_by_the_iterator_is_the_original_error()
  local value = setmetatable({}, {
    __pairs = function() return function() error("boom from iterator", 0) end, nil, nil end,
  })
  local err = self:assert_error(function() return json.encode({ value }) end)
  self:assert_true(tostring(err):find("boom from iterator", 1, true) ~= nil, tostring(err))
end

function T:test_a_pairs_that_does_not_return_a_function_is_an_error_not_a_crash()
  ---@diagnostic disable-next-line: return-type-mismatch
  local value = setmetatable({}, { __pairs = function() return nil end })
  self:assert_error(function() return json.encode(value) end)
end

function T:test_an_infinite_iterator_is_bounded_by_max_size()
  local value = setmetatable({}, {
    __pairs = function()
      return function(_, control)
        local n = (control or 0) + 1
        return n, n
      end, nil, nil
    end,
  })
  fails(self, value, "size_limit", { max_size = 1000 })
  fails(self, value, "size_limit")
end

function T:test_an_iterator_repeating_one_key_is_bounded_by_max_size()
  local value = setmetatable({}, {
    __pairs = function() return function() return "k", 1 end, nil, nil end,
  })
  fails(self, value, "size_limit", { max_size = 1000 })
end

function T:test_many_entries_beyond_max_size_are_refused_and_within_it_are_written()
  local entries = {}
  for i = 1, 100 do entries["k" .. i] = i end
  local value = proxy(entries)
  self:assert_equal("string", type(json.encode(value)))
  fails(self, value, "size_limit", { max_size = 100 })
end

function T:test_a_cycle_through_a_proxy_is_stopped_by_max_depth()
  local cycle = {}
  setmetatable(cycle, { __pairs = function() return next, { self = cycle }, nil end })
  local err = fails(self, cycle, "depth_limit")
  self:assert_true(#err.context.path > 0)
  fails(self, cycle, "depth_limit", { max_depth = 5 })
end

function T:test_a_frozen_value_object_cycle_free_nesting_within_depth()
  local value = Point(Point(Point(1, 2), 3), 4)
  self:assert_equal('{"x":{"x":{"x":1,"y":2},"y":3},"y":4}', json.encode(value, { canonical = true }))
end

function T:test_round_trip_of_a_value_object()
  local decoded = json.decode(json.encode(Point(1, 2)))
  self:assert_equal(1, decoded.x)
  self:assert_equal(2, decoded.y)
end

return T
