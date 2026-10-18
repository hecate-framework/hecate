-- The in-house JSON decoder (RFC 8259) that reads the LuaLS export, and its encoder.
local test = require("harness.test")
local json = require("hecate.doc.internal.json")
local T = test.Case("JsonTest")

function T:test_scalars()
  self:assert_equal(42, json.decode("42"))
  self:assert_equal("integer", math.type(json.decode("42")))
  self:assert_equal("float", math.type(json.decode("4.0")))
  self:assert_equal(-1500.0, json.decode("-1.5e3"))
  self:assert_equal("float", math.type(json.decode("1e2")))
  self:assert_equal(true, json.decode("true"))
  self:assert_equal(false, json.decode("false"))
  self:assert_nil(json.decode("null"))
  self:assert_equal("a", json.decode('"a"'))
end

function T:test_objects_and_arrays_nest()
  local value = json.decode(' { "a" : [1, 2, {"b": "c"}], "d": {} , "e": [] } ')
  self:assert_equal(3, #value.a)
  self:assert_equal("c", value.a[3].b)
  self:assert_equal(0, #value.e)
  self:assert_nil(next(value.d))
end

function T:test_null_member_is_omitted_and_null_array_item_keeps_its_place()
  local value = json.decode('{"a": null, "b": [1, null, 3]}')
  self:assert_nil(value.a)
  self:assert_equal(3, #value.b)
  self:assert_equal(json.null, value.b[2])
  self:assert_equal(3, value.b[3])
end

function T:test_string_escapes_and_unicode()
  self:assert_equal('"\\/\b\f\n\r\t', json.decode([["\"\\\/\b\f\n\r\t"]]))
  self:assert_equal("\u{e9}", json.decode([["é"]]))
  self:assert_equal("\u{1F600}", json.decode([["😀"]]), "a surrogate pair is one code point")
  self:assert_equal("\u{e9}", json.decode('"\u{e9}"'), "UTF-8 passes through")
end

function T:test_encoder_round_trips()
  local value = { a = { 1, 2.5, "x\ny" }, b = true, c = "<>&" }
  self:assert_equal(json.encode(value), json.encode(json.decode(json.encode(value))))
end

function T:test_malformed_input_raises_with_a_position()
  for _, source in ipairs({
    "", "{", "[1,]", '{"a" 1}', '{"a":1,}', "tru", "01", "1.", '"abc', '"\\x"', '"\\ud83d"', "[1] 2", "'a'",
    '"a\nb"', "{1:2}", "-", "+1",
  }) do
    local err = self:assert_error(function() json.decode(source) end)
    self:assert_true(tostring(err):find("invalid JSON", 1, true) ~= nil, source)
  end
end

function T:test_deep_nesting_is_refused_not_overflowed()
  local source = string.rep("[", 1000) .. string.rep("]", 1000)
  self:assert_error(function() json.decode(source) end, "too deep")
end

return T
