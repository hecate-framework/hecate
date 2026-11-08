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

--- Throws `thrown` from `__pairs` (where = "pairs") or from its iterator (where = "iterator") and returns what
--- `json.encode` raised.
local function raised_by(where, thrown)
  local metatable
  if where == "pairs" then
    metatable = { __pairs = function() error(thrown, 0) end }
  else
    metatable = { __pairs = function() return function() error(thrown, 0) end, nil, nil end }
  end
  local ok, err = pcall(json.encode, { setmetatable({}, metatable) })
  assert(not ok, "json.encode must raise")
  return err
end

local WHERES = { "pairs", "iterator" }

function T:test_a_table_raised_by_pairs_or_its_iterator_is_the_same_table()
  for _, where in ipairs(WHERES) do
    local thrown = { code = 7 }
    self:assert_true(rawequal(thrown, raised_by(where, thrown)), where)
  end
end

function T:test_a_core_error_instance_raised_by_pairs_keeps_its_identity_and_context()
  local Boom = core.error_class("PairsBoom", "test.PairsBoom", core.Error)
  for _, where in ipairs(WHERES) do
    local thrown = Boom({ message = "boom", context = { where = where } })
    local err = raised_by(where, thrown)
    self:assert_true(rawequal(thrown, err), where)
    self:assert_true(core.is_instance_of(err, Boom), where)
    self:assert_equal(where, thrown.context.where)
  end
end

function T:test_a_string_raised_by_pairs_arrives_without_traceback_or_prefix()
  for _, where in ipairs(WHERES) do
    self:assert_equal("x", raised_by(where, "x"))
  end
end

function T:test_nil_and_a_number_raised_by_pairs_arrive_as_they_were_thrown()
  -- Lua 5.5 itself turns `error(nil)` into a message: whatever a plain `pcall` sees is what `encode` must raise.
  local plain = select(2, pcall(error, nil))
  for _, where in ipairs(WHERES) do
    self:assert_equal(plain, raised_by(where, nil))
    local number = raised_by(where, 42)
    self:assert_equal(42, number)
    self:assert_equal("number", type(number))
  end
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

function T:test_an_iterator_repeating_one_key_is_refused_as_a_duplicate_key()
  -- The repeat is found as soon as it is yielded, before the budget could be spent.
  local value = setmetatable({}, {
    __pairs = function() return function() return "k", 1 end, nil, nil end,
  })
  fails(self, value, "duplicate_key", { max_size = 1000 })
  fails(self, value, "duplicate_key")
end

--- An iterator that yields the given `{ key, value }` pairs in order, then ends.
local function sequence(...)
  local pairs_list = { ... }
  return setmetatable({}, {
    __pairs = function()
      local index = 0
      return function()
        index = index + 1
        local item = pairs_list[index]
        if item then return item[1], item[2] end
      end, nil, nil
    end,
  })
end

function T:test_an_iterator_repeating_a_string_key_is_refused()
  local err = fails(self, sequence({ "a", 1 }, { "a", 2 }), "duplicate_key")
  self:assert_equal("", err.context.path)
end

function T:test_a_repeated_key_is_not_echoed_in_the_error()
  local secret = "s3cr3t-key"
  local err = fails(self, sequence({ secret, 1 }, { secret, 2 }), "duplicate_key")
  self:assert_nil(string.find(err.message, secret, 1, true))
  self:assert_nil(string.find(err.context.path, secret, 1, true))
  self:assert_nil(string.find(tostring(err), secret, 1, true))
end

function T:test_a_repeated_key_at_depth_reports_the_pointer_of_its_object()
  local inner = sequence({ "x", 1 }, { "y", 2 }, { "x", 3 })
  local err = fails(self, { a = { b = inner } }, "duplicate_key")
  self:assert_equal("/a/b", err.context.path)
  err = fails(self, { { 1, sequence({ "k", 1 }, { "k", 1 }) } }, "duplicate_key")
  self:assert_equal("/0/1", err.context.path)
  err = fails(self, { ["a/b"] = sequence({ "k", 1 }, { "k", 1 }) }, "duplicate_key")
  self:assert_equal("/a~1b", err.context.path)
end

function T:test_the_same_key_three_times_is_refused()
  fails(self, sequence({ "a", 1 }, { "a", 2 }, { "a", 3 }), "duplicate_key")
end

function T:test_a_repeat_that_is_not_adjacent_is_refused()
  fails(self, sequence({ "a", 1 }, { "b", 2 }, { "a", 3 }), "duplicate_key")
end

function T:test_an_iterator_repeating_an_integer_key_is_refused_instead_of_overwriting_a_slot()
  local err = fails(self, sequence({ 1, "a" }, { 1, "b" }), "duplicate_key")
  self:assert_equal("", err.context.path)
  fails(self, sequence({ 1, "a" }, { 2, "b" }, { 2, "c" }), "duplicate_key")
  fails(self, sequence({ 1, "a" }, { 2, "b" }, { 3, "c" }, { 1, "d" }), "duplicate_key")
  fails(self, sequence({ 3, "a" }, { 1, "b" }, { 2, "c" }, { 3, "d" }), "duplicate_key")
  fails(self, sequence({ 2, "a" }, { 2, "b" }), "duplicate_key")
  fails(self, sequence({ -1, "a" }, { -1, "b" }), "duplicate_key")
end

function T:test_a_repeated_integer_key_is_not_echoed_and_reports_the_pointer_of_its_array()
  local err = fails(self, { a = { 7, sequence({ 1, "x" }, { 1, "y" }) } }, "duplicate_key")
  self:assert_equal("/a/1", err.context.path)
  local echoed = fails(self, sequence({ 424242, 1 }, { 424242, 2 }), "duplicate_key")
  self:assert_equal("", echoed.context.path)
  self:assert_nil(string.find(tostring(echoed), "424242", 1, true))
  err = fails(self, { ["a/b"] = sequence({ 1, 1 }, { 1, 2 }) }, "duplicate_key")
  self:assert_equal("/a~1b", err.context.path)
end

function T:test_a_repeated_integer_key_is_refused_before_the_budget_is_spent()
  local value = setmetatable({}, {
    __pairs = function() return function() return 1, 1 end, nil, nil end,
  })
  fails(self, value, "duplicate_key", { max_size = 1000 })
  fails(self, value, "duplicate_key")
end

function T:test_a_float_key_is_never_taken_for_an_integer_slot()
  -- The array rule reads only integer keys as indices: 1.0 is not one, so mixing it with 1 is refused as an
  -- ambiguous table (nothing can be overwritten), the same as any float key.
  fails(self, sequence({ 1, "a" }, { 1.0, "b" }), "ambiguous_table")
  fails(self, sequence({ 1.0, "a" }, { 1.0, "b" }), "ambiguous_table")
  fails(self, sequence({ 1.0, "a" }), "ambiguous_table")
end

function T:test_a_proper_sequence_from_a_proxy_is_still_an_array()
  self:assert_equal('["a","b","c"]', json.encode(sequence({ 1, "a" }, { 2, "b" }, { 3, "c" })))
  self:assert_equal('["c","b","a"]', json.encode(sequence({ 3, "a" }, { 2, "b" }, { 1, "c" })))
  self:assert_equal('["a",null,"c"]', json.encode(sequence({ 1, "a" }, { 3, "c" })))
end

function T:test_mixed_integer_and_string_keys_keep_their_rules()
  fails(self, sequence({ 1, "a" }, { "k", "b" }), "ambiguous_table")
  fails(self, sequence({ "k", "b" }, { 1, "a" }), "ambiguous_table")
  fails(self, sequence({ 1, "a" }, { "k", "b" }, { "k", "c" }), "duplicate_key")
  -- A string key "1" and the integer key 1 are different keys.
  fails(self, sequence({ 1, "a" }, { "1", "b" }), "ambiguous_table")
end

function T:test_a_huge_string_key_yielded_twice_is_refused_as_a_duplicate()
  local huge = string.rep("k", 1024 * 1024)
  local err = fails(self, sequence({ huge, 1 }, { huge, 2 }), "duplicate_key", { max_size = 8 * 1024 * 1024 })
  self:assert_true(#tostring(err) < 1000, "the key is not echoed")
  -- A repeat built apart from the first copy is the same key.
  fails(self, sequence({ huge, 1 }, { "x", 2 }, { string.rep("k", 1024 * 1024), 3 }), "duplicate_key")
end

function T:test_two_long_keys_sharing_a_prefix_are_different_keys()
  local prefix = string.rep("p", 4096)
  local value = sequence({ prefix .. "a", 1 }, { prefix .. "b", 2 }, { prefix, 3 }, { prefix .. "ab", 4 })
  local decoded = json.decode(json.encode(value))
  self:assert_equal(1, decoded[prefix .. "a"])
  self:assert_equal(2, decoded[prefix .. "b"])
  self:assert_equal(3, decoded[prefix])
  self:assert_equal(4, decoded[prefix .. "ab"])
end

function T:test_many_distinct_keys_are_accepted_and_one_late_repeat_is_found()
  local list = {}
  for i = 1, 20000 do list[i] = { "key" .. i, i } end
  local function iteration(repeat_last)
    local count = #list + (repeat_last and 1 or 0)
    return setmetatable({}, {
      __pairs = function()
        local index = 0
        return function()
          index = index + 1
          if index > count then return nil end
          local item = list[index] or list[1]
          return item[1], item[2]
        end, nil, nil
      end,
    })
  end
  self:assert_equal("string", type(json.encode(iteration(false), { max_size = 4 * 1024 * 1024 })))
  fails(self, iteration(true), "duplicate_key", { max_size = 4 * 1024 * 1024 })
end

function T:test_the_same_key_in_two_objects_is_not_a_duplicate()
  local value = { sequence({ "a", 1 }), sequence({ "a", 2 }), { a = proxy({ a = 3 }) } }
  self:assert_equal('[{"a":1},{"a":2},{"a":{"a":3}}]', json.encode(value))
end

function T:test_two_different_keys_are_fine()
  self:assert_equal('{"a":1,"b":2}', json.encode(sequence({ "a", 1 }, { "b", 2 }), { canonical = true }))
end

function T:test_keys_that_differ_only_by_case_are_fine()
  local value = sequence({ "a", 1 }, { "A", 2 })
  self:assert_equal('{"A":2,"a":1}', json.encode(value, { canonical = true }))
end

function T:test_a_plain_table_cannot_repeat_a_key_and_is_unaffected()
  self:assert_equal('{"a":1,"b":2}', json.encode({ a = 1, b = 2 }, { canonical = true }))
  self:assert_equal('{"a":1}', json.encode(setmetatable({ a = 1 }, { __index = {} })))
end

function T:test_a_valid_proxy_still_honours_canonical_and_pretty()
  local value = sequence({ "b", 1 }, { "a", 2 })
  self:assert_equal('{"a":2,"b":1}', json.encode(value, { canonical = true }))
  self:assert_equal('{\n  "a": 2,\n  "b": 1\n}', json.encode(value, { canonical = true, pretty = true }))
  self:assert_equal('{"a":2,"b":1}', json.encode(value, { canonical = "rfc8785" }))
end

function T:test_many_entries_beyond_max_size_are_refused_and_within_it_are_written()
  local entries = {}
  for i = 1, 100 do entries["k" .. i] = i end
  local value = proxy(entries)
  self:assert_equal("string", type(json.encode(value)))
  fails(self, value, "size_limit", { max_size = 100 })
end

function T:test_the_entries_of_all_tables_share_one_budget()
  -- Each table is far below the budget (about max_size / 2 = 500 entries), the whole tree is above it.
  local child_entries = {}
  for i = 1, 40 do child_entries[i] = 1 end
  local children = {}
  for i = 1, 30 do children[i] = proxy(child_entries) end
  fails(self, children, "size_limit", { max_size = 1000 })
  self:assert_equal("string", type(json.encode(children)))
end

function T:test_a_self_referencing_proxy_tree_is_bounded_by_the_shared_budget()
  local tree = {}
  local entries = { a = 1, b = 2, c = 3, d = 4, e = 5, f = 6, g = 7, h = 8, tree = tree }
  setmetatable(tree, { __pairs = function() return next, entries, nil end })
  fails(self, tree, "size_limit", { max_size = 1000 })
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
