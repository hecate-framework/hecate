-- Behaviour of json.decode: RFC 8259 grammar, numbers (integer/float fidelity), strings, UTF-8,
-- duplicate names, limits and arguments.
local test = require("harness.test")
local core = require("hecate.core")
local json = require("hecate.json")
local T = test.Case("JsonDecodeTest")

local function decode_error(self, text, options)
  local err = self:assert_error(function() return json.decode(text, options) end)
  self:assert_true(core.is_instance_of(err, json.DecodeError), tostring(err))
  return err
end

function T:test_scalars_and_top_level_values()
  self:assert_equal(true, json.decode("true"))
  self:assert_equal(false, json.decode(" false\n"))
  self:assert_true(json.decode("null") == json.null)
  self:assert_equal("x", json.decode('"x"'))
  self:assert_equal(7, json.decode("\t7\r\n"))
end

function T:test_integers_stay_integers_and_floats_stay_floats()
  local cases = {
    { "0", "integer", 0 }, { "-17", "integer", -17 }, { "9223372036854775807", "integer", math.maxinteger },
    { "-9223372036854775808", "integer", math.mininteger },
    { "1.0", "float", 1.0 }, { "1e2", "float", 100.0 }, { "1E+2", "float", 100.0 }, { "25e-1", "float", 2.5 },
    { "-0.5", "float", -0.5 }, { "0.1", "float", 0.1 },
  }
  for _, case in ipairs(cases) do
    local value = json.decode(case[1])
    self:assert_equal(case[2], math.type(value), case[1])
    self:assert_equal(case[3], value, case[1])
  end
end

function T:test_integers_beyond_64_bits_become_floats()
  local value = json.decode("9223372036854775808")
  self:assert_equal("float", math.type(value))
  self:assert_equal(2.0 ^ 63, value)
  self:assert_equal("float", math.type(json.decode("-12345678901234567890123")))
end

function T:test_negative_zero_is_an_integer_but_a_float_zero_keeps_its_sign()
  local value = json.decode("-0")
  self:assert_equal("integer", math.type(value))
  self:assert_equal(0, value)
  self:assert_equal("-0.0", tostring(json.decode("-0.0")))
  self:assert_equal("-0.0", tostring(json.decode("-0e0")))
end

function T:test_malformed_numbers_are_rejected()
  for _, text in ipairs({ "01", "-", "+1", ".5", "1.", "1e", "1e+", "--1", "0x10", "1.5.2", "NaN", "Infinity", "-Infinity", "00" }) do
    local err = decode_error(self, text)
    self:assert_equal("syntax", err.context.reason, text)
  end
end

function T:test_a_float_outside_the_double_range_is_rejected()
  local err = decode_error(self, "[1e999]")
  self:assert_equal("number_out_of_range", err.context.reason)
  self:assert_equal(1, err.context.offset)
  self:assert_equal(0.0, json.decode("1e-999"))
end

function T:test_string_escapes()
  self:assert_equal('"\\/\b\f\n\r\t', json.decode([["\"\\\/\b\f\n\r\t"]]))
  self:assert_equal("A\u{e9}\u{20ac}", json.decode([["\u0041\u00e9\u20AC"]]))
  self:assert_equal("a\0b", json.decode([["a\u0000b"]]))
end

function T:test_surrogate_pairs_decode_to_one_scalar_value()
  self:assert_equal("\u{1F600}", json.decode([["\ud83d\ude00"]]))
  self:assert_equal("\u{10000}", json.decode([["\uD800\uDC00"]]))
  self:assert_equal("\u{10FFFF}", json.decode([["\uDBFF\uDFFF"]]))
end

function T:test_lone_surrogates_are_rejected()
  for _, text in ipairs({ [["\ud83d"]], [["\ud83dx"]], [["\ude00"]], [["\ud83d\u0041"]], [["\ud83d\ud83d"]], [["\ude00\ud83d"]] }) do
    self:assert_equal("lone_surrogate", decode_error(self, text).context.reason, text)
  end
end

function T:test_invalid_escapes_are_rejected()
  for _, text in ipairs({ [["\x"]], [["\u12"]], [["\u12G4"]], [["\']] .. '"', [["\ "]] }) do
    self:assert_equal("invalid_escape", decode_error(self, text).context.reason, text)
  end
end

function T:test_unescaped_control_characters_are_rejected()
  for code = 0, 31 do
    local err = decode_error(self, '"a' .. string.char(code) .. 'b"')
    self:assert_equal("control_character", err.context.reason)
    self:assert_equal(2, err.context.offset)
  end
  self:assert_equal("\127", json.decode('"\127"')) -- DEL is not a control character of RFC 8259 section 7
end

function T:test_invalid_utf8_is_rejected_with_its_position()
  local cases = {
    "\255", "\192\175", "\xC0\x80", "\xE0\x80\x80", "\xED\xA0\x80", "\xF4\x90\x80\x80", "\xF5\x80\x80\x80", "\x80", "\xC3",
    "\xE2\x82", "\xF0\x9F\x98",
  }
  for _, bad in ipairs(cases) do
    local err = decode_error(self, '["ab' .. bad .. '"]')
    self:assert_equal("invalid_utf8", err.context.reason, ("%q"):format(bad))
    self:assert_equal(4, err.context.offset, ("%q"):format(bad))
  end
  -- after an escape, in the slow path
  local err = decode_error(self, '"\\n\xFF"')
  self:assert_equal("invalid_utf8", err.context.reason)
  self:assert_equal(3, err.context.offset)
  -- member names too
  self:assert_equal("invalid_utf8", decode_error(self, '{"\xFF":1}').context.reason)
end

function T:test_valid_multibyte_utf8_passes_through()
  self:assert_equal("h\u{e9}llo \u{4e16}\u{754c} \u{1F600}", json.decode('"h\u{e9}llo \u{4e16}\u{754c} \u{1F600}"'))
end

function T:test_a_byte_order_mark_is_rejected()
  local err = decode_error(self, "\239\187\191[]")
  self:assert_equal("byte_order_mark", err.context.reason)
  self:assert_equal(0, err.context.offset)
end

function T:test_structure_errors()
  local cases = {
    "", "   ", "[", "[1", "[1,", "[1,]", "[,1]", "[1 2]", "{", '{"a"', '{"a":', '{"a":1', '{"a":1,}', '{,}', "{a:1}",
    "{'a':1}", '{"a" 1}', "[1]]", "{} {}", "[] x", "tru", "nul", "True", "undefined", '"abc', "'a'", "//x\n1", "[1,2,3",
  }
  for _, text in ipairs(cases) do
    self:assert_equal("syntax", decode_error(self, text).context.reason, text)
  end
end

function T:test_decoded_containers_are_marked()
  local array = json.decode("[]")
  local object = json.decode("{}")
  self:assert_true(json.is_array(array))
  self:assert_false(json.is_object(array))
  self:assert_true(json.is_object(object))
  self:assert_equal(0, #array)
  self:assert_equal(nil, next(object))
  local nested = json.decode('{"a":[1,{"b":[]}],"c":{}}')
  self:assert_true(json.is_object(nested))
  self:assert_true(json.is_array(nested.a))
  self:assert_true(json.is_object(nested.a[2]))
  self:assert_true(json.is_array(nested.a[2].b))
  self:assert_true(json.is_object(nested.c))
end

function T:test_null_is_kept_in_arrays_and_objects()
  local value = json.decode('[null,1,null]')
  self:assert_equal(3, #value)
  self:assert_true(value[1] == json.null and value[3] == json.null)
  local object = json.decode('{"a":null}')
  self:assert_true(object.a == json.null)
end

function T:test_duplicate_member_names_are_rejected()
  local err = decode_error(self, '{"a":1,"b":2,"a":3}')
  self:assert_equal("duplicate_key", err.context.reason)
  self:assert_equal(13, err.context.offset)
  self:assert_equal("duplicate_key", decode_error(self, '{"a":null,"a":1}').context.reason)
  self:assert_equal("duplicate_key", decode_error(self, '{"a\\u0062":1,"ab":2}').context.reason)
end

function T:test_whitespace_is_only_the_four_characters_of_rfc_8259()
  self:assert_equal(1, json.decode(" \t\r\n1 \t\r\n"))
  for _, space in ipairs({ "\f", "\v", "\194\160", "\226\128\168" }) do
    decode_error(self, space .. "1")
  end
end

function T:test_nesting_up_to_max_depth_is_accepted_and_one_more_is_rejected()
  local function nested(depth) return string.rep("[", depth) .. string.rep("]", depth) end
  self:assert_not_nil(json.decode(nested(1000)))
  local err = decode_error(self, nested(1001))
  self:assert_equal("depth_limit", err.context.reason)
  self:assert_equal(1000, err.context.offset)
  self:assert_not_nil(json.decode(nested(5), { max_depth = 5 }))
  self:assert_equal("depth_limit", decode_error(self, nested(6), { max_depth = 5 }).context.reason)
  self:assert_equal("depth_limit", decode_error(self, string.rep('{"a":', 6) .. "1" .. string.rep("}", 6), { max_depth = 5 }).context.reason)
  -- a hostile text far deeper than the default must fail cleanly, not exhaust the stack
  self:assert_equal("depth_limit", decode_error(self, string.rep("[", 200000)).context.reason)
  self:assert_not_nil(json.decode(nested(10000), { max_depth = 10000 }))
end

function T:test_max_size_limits_the_input()
  self:assert_equal(1, json.decode("1", { max_size = 1 }))
  local err = decode_error(self, "[1]", { max_size = 2 })
  self:assert_equal("size_limit", err.context.reason)
end

function T:test_arguments_are_validated()
  local function bad(text, options, pattern)
    local err = self:assert_error(function() return json.decode(text, options) end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
    self:assert_true(tostring(err):find(pattern, 1, true) ~= nil, tostring(err))
  end
  bad(nil, nil, "expects a string")
  bad(12, nil, "expects a string")
  bad("1", 5, "options table")
  bad("1", { max_dept = 3 }, 'unknown option "max_dept"')
  bad("1", { max_depth = 0 }, "invalid max_depth")
  bad("1", { max_depth = 1.5 }, "invalid max_depth")
  bad("1", { max_depth = 10001 }, "invalid max_depth")
  bad("1", { max_size = -1 }, "invalid max_size")
  bad("1", { pretty = true }, 'unknown option "pretty"')
end

return T
