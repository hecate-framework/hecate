-- Behaviour of json.encode: value model, empty-table rule, floats, strings, UTF-8, pretty printing,
-- canonical order, limits and arguments.
local test = require("harness.test")
local core = require("hecate.core")
local json = require("hecate.json")
local T = test.Case("JsonEncodeTest")

local function encode_error(self, value, options)
  local err = self:assert_error(function() return json.encode(value, options) end)
  self:assert_true(core.is_instance_of(err, json.EncodeError), tostring(err))
  return err
end

function T:test_scalars()
  self:assert_equal("null", json.encode(json.null))
  self:assert_equal("true", json.encode(true))
  self:assert_equal("false", json.encode(false))
  self:assert_equal('"x"', json.encode("x"))
  self:assert_equal("42", json.encode(42))
end

function T:test_integers_are_written_without_decimal_point()
  self:assert_equal("0", json.encode(0))
  self:assert_equal("-7", json.encode(-7))
  self:assert_equal("9223372036854775807", json.encode(math.maxinteger))
  self:assert_equal("-9223372036854775808", json.encode(math.mininteger))
end

function T:test_floats_always_carry_a_decimal_point_or_an_exponent()
  self:assert_equal("1.0", json.encode(1.0))
  self:assert_equal("-3.0", json.encode(-3.0))
  self:assert_equal("0.0", json.encode(0.0))
  self:assert_equal("-0.0", json.encode(-0.0))
  self:assert_equal("0.5", json.encode(0.5))
  self:assert_equal("0.1", json.encode(0.1))
  self:assert_equal("9007199254740992.0", json.encode(2.0 ^ 53))
  for _, value in ipairs({ 1e100, 1.5e-10, 2.0 ^ 63, -2.0 ^ 63, 1e15, 1e16, 123456789012345680000.0, 5e-324, 1.7976931348623157e308 }) do
    local text = json.encode(value)
    self:assert_true(text:find("[.eE]") ~= nil, text)
    self:assert_equal("float", math.type(json.decode(text)), text)
    self:assert_equal(value, json.decode(text), text)
  end
end

function T:test_floats_use_the_shortest_digits_that_read_back()
  self:assert_equal("0.3", json.encode(0.3))
  self:assert_equal("0.30000000000000004", json.encode(0.1 + 0.2))
  self:assert_equal("3.14159", json.encode(3.14159))
end

function T:test_not_a_number_and_infinities_are_rejected()
  for _, value in ipairs({ 0 / 0, -(0 / 0), math.huge, -math.huge }) do
    self:assert_equal("non_finite_number", encode_error(self, value).context.reason)
    self:assert_equal("non_finite_number", encode_error(self, { value }).context.reason)
  end
  self:assert_equal("/1", encode_error(self, { 1, math.huge }).context.path)
end

function T:test_the_empty_table_is_an_object_unless_marked()
  self:assert_equal("{}", json.encode({}))
  self:assert_equal("{}", json.encode(json.object()))
  self:assert_equal("[]", json.encode(json.array()))
  self:assert_equal('{"a":[],"b":{}}', json.encode({ a = json.array(), b = {} }, { canonical = true }))
end

function T:test_sequences_are_arrays_and_string_keyed_tables_are_objects()
  self:assert_equal("[1,2,3]", json.encode({ 1, 2, 3 }))
  self:assert_equal('{"a":1}', json.encode({ a = 1 }))
  self:assert_equal('["a",true,null]', json.encode({ "a", true, json.null }))
  self:assert_equal('[[],{}]', json.encode({ json.array(), {} }))
end

function T:test_ambiguous_tables_are_rejected()
  for _, value in ipairs({ { 1, 2, x = 3 }, { [0] = "a" }, { [1.5] = 1 }, { [true] = 1 } }) do
    self:assert_equal("ambiguous_table", encode_error(self, value).context.reason)
  end
end

function T:test_holes_are_written_as_null()
  self:assert_equal("[1,null,3]", json.encode({ 1, nil, 3 }))
  self:assert_equal('[null,"b"]', json.encode({ [2] = "b" }))
  self:assert_equal("[1,null,3]", json.encode(json.array({ 1, nil, 3 })))
  self:assert_equal('{"a":[1,null,3]}', json.encode({ a = { 1, nil, 3 } }))
end

function T:test_too_sparse_tables_are_rejected()
  local sparse = { [1] = 1, [1000000] = 2 }
  self:assert_equal("ambiguous_table", encode_error(self, sparse).context.reason)
  self:assert_equal("sparse_array", encode_error(self, json.array(sparse)).context.reason)
end

function T:test_canonical_order_is_utf16_order()
  -- U+1F600 is the surrogate pair D83D DE00 in UTF-16, so it sorts before U+FF5E; in UTF-8 byte order it sorts after.
  local value = { ["\u{1F600}"] = 1, ["\u{FF5E}"] = 2, ["\u{E9}"] = 3 }
  self:assert_equal('{"\u{E9}":3,"\u{1F600}":1,"\u{FF5E}":2}', json.encode(value, { canonical = true }))
end

function T:test_marked_tables_are_checked()
  self:assert_equal("sparse_array", encode_error(self, json.array({ 1, 2, x = 3 })).context.reason)
  self:assert_equal("ambiguous_table", encode_error(self, json.object({ 1, 2 })).context.reason)
  self:assert_equal("[1,2]", json.encode(json.array({ 1, 2 })))
  self:assert_equal('{"a":1}', json.encode(json.object({ a = 1 })))
end

function T:test_unsupported_values_are_rejected_with_their_path()
  for _, value in ipairs({ print, coroutine.create(print), io.stdout }) do
    self:assert_equal("unsupported_type", encode_error(self, value).context.reason)
    self:assert_equal("unsupported_type", encode_error(self, { value }).context.reason)
  end
  self:assert_equal("unsupported_type", encode_error(self, nil).context.reason)
  self:assert_equal("/a/0", encode_error(self, { a = { print } }).context.path)
end

function T:test_string_escapes()
  self:assert_equal('"\\"\\\\\\b\\f\\n\\r\\t"', json.encode('"\\\b\f\n\r\t'))
  self:assert_equal('"\\u0000\\u0001\\u001f"', json.encode("\0\1\31"))
  self:assert_equal('"/ \127"', json.encode("/ \127"))
  self:assert_equal('"\u{e9}\u{20ac}\u{1F600}"', json.encode("\u{e9}\u{20ac}\u{1F600}"))
  self:assert_equal('"\u{2028}\u{2029}"', json.encode("\u{2028}\u{2029}"))
end

function T:test_invalid_utf8_is_rejected_in_values_and_keys()
  for _, bad in ipairs({ "\255", "\192\175", "\xED\xA0\x80", "\xF4\x90\x80\x80", "\xC3", "ab\x80" }) do
    self:assert_equal("invalid_utf8", encode_error(self, bad).context.reason, ("%q"):format(bad))
    self:assert_equal("invalid_utf8", encode_error(self, { [bad] = 1 }).context.reason)
  end
  self:assert_equal("/1", encode_error(self, { "ok", "\255" }).context.path)
end

function T:test_output_is_always_valid_utf8()
  local samples = { "", "plain", "\0\31", "\u{7f}\u{80}\u{7ff}\u{800}\u{ffff}\u{10000}\u{10ffff}", "\u{d7ff}\u{e000}" }
  for _, sample in ipairs(samples) do
    for _, value in ipairs({ { sample }, { [sample] = sample } }) do
      self:assert_true(utf8.len(json.encode(value)) ~= nil, ("%q"):format(sample))
    end
  end
end

function T:test_canonical_orders_members_by_byte_value_at_every_level()
  local value = { b = 1, a = { z = 1, y = 2, A = 3 }, B = 2, [""] = 0, ["\u{e9}"] = 5, aa = 9 }
  self:assert_equal('{"":0,"B":2,"a":{"A":3,"y":2,"z":1},"aa":9,"b":1,"\u{e9}":5}', json.encode(value, { canonical = true }))
  local first = json.encode(value, { canonical = true })
  for _ = 1, 20 do
    local copy = {}
    for k, v in pairs(value) do copy[k] = v end
    self:assert_equal(first, json.encode(copy, { canonical = true }))
  end
end

function T:test_pretty_printing()
  local value = { a = { 1, 2 }, b = json.object(), c = json.array(), d = { e = json.null } }
  local expected = '{\n  "a": [\n    1,\n    2\n  ],\n  "b": {},\n  "c": [],\n  "d": {\n    "e": null\n  }\n}'
  self:assert_equal(expected, json.encode(value, { pretty = true, canonical = true }))
  self:assert_equal(expected, json.encode(value, { indent = 2, canonical = true }))
  self:assert_equal('[\n\t1\n]', json.encode({ 1 }, { indent = "\t" }))
  self:assert_equal('[\n1\n]', json.encode({ 1 }, { indent = 0 }))
  self:assert_equal('[\n    1\n]', json.encode({ 1 }, { pretty = true, indent = 4 }))
  self:assert_equal("[1]", json.encode({ 1 }, { pretty = false }))
  self:assert_equal("[]", json.encode(json.array(), { pretty = true }))
end

function T:test_pretty_text_decodes_to_the_same_value()
  local value = json.decode('{"a":[1,2.5,{"b":null}],"c":"x"}')
  local pretty = json.encode(value, { pretty = true, canonical = true })
  self:assert_equal(json.encode(value, { canonical = true }), json.encode(json.decode(pretty), { canonical = true }))
end

function T:test_nesting_up_to_max_depth_is_accepted_and_one_more_is_rejected()
  local function nested(depth)
    local value = json.array()
    for _ = 2, depth do value = json.array({ value }) end
    return value
  end
  self:assert_equal(2000, #json.encode(nested(1000)))
  local err = encode_error(self, nested(1001))
  self:assert_equal("depth_limit", err.context.reason)
  self:assert_equal("depth_limit", encode_error(self, nested(4), { max_depth = 3 }).context.reason)
  self:assert_equal("[[[]]]", json.encode(nested(3), { max_depth = 3 }))
end

function T:test_a_cycle_is_stopped_by_the_depth_limit()
  local cyclic = {}
  cyclic.self = cyclic
  self:assert_equal("depth_limit", encode_error(self, cyclic).context.reason)
  local array = json.array()
  array[1] = array
  self:assert_equal("depth_limit", encode_error(self, array, { max_depth = 50 }).context.reason)
end

function T:test_max_size_limits_the_output()
  self:assert_equal("[1,2]", json.encode({ 1, 2 }, { max_size = 5 }))
  self:assert_equal("size_limit", encode_error(self, { 1, 2 }, { max_size = 4 }).context.reason)
  self:assert_equal("size_limit", encode_error(self, string.rep("x", 100), { max_size = 50 }).context.reason)
end

function T:test_tables_with_metatables_are_read_raw()
  local proxy = setmetatable({}, { __index = function() return 1 end, __len = function() return 9 end, __pairs = function() error("no") end })
  self:assert_equal("{}", json.encode(proxy))
  local object = setmetatable({ a = 1 }, { __metatable = "locked" })
  self:assert_equal('{"a":1}', json.encode(object))
end

function T:test_arguments_are_validated()
  local function bad(options, pattern)
    local err = self:assert_error(function() return json.encode({}, options) end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
    self:assert_true(tostring(err):find(pattern, 1, true) ~= nil, tostring(err))
  end
  bad("pretty", "options table")
  bad({ prety = true }, 'unknown option "prety"')
  bad({ pretty = "yes" }, "invalid pretty")
  bad({ indent = -1 }, "invalid indent")
  bad({ indent = 17 }, "invalid indent")
  bad({ indent = "xx" }, "invalid indent")
  bad({ indent = 2.5 }, "invalid indent")
  bad({ pretty = false, indent = 2 }, "pretty = false")
  bad({ canonical = 1 }, "invalid canonical")
  bad({ max_depth = 0 }, "invalid max_depth")
  bad({ max_size = "big" }, "invalid max_size")
end

return T
