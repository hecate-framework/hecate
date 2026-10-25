-- Error classes and the precise position (offset, line, column) of decoding failures.
local test = require("harness.test")
local core = require("hecate.core")
local json = require("hecate.json")
local T = test.Case("JsonErrorsTest")

local function failure(self, text)
  local err = self:assert_error(function() return json.decode(text) end)
  self:assert_true(core.is_instance_of(err, json.DecodeError), tostring(err))
  return err
end

function T:test_the_classes_are_on_the_core_hierarchy()
  local decode_error = json.DecodeError({ message = "x" })
  local encode_error = json.EncodeError({ message = "x" })
  self:assert_true(core.is_instance_of(decode_error, json.JsonError))
  self:assert_true(core.is_instance_of(encode_error, json.JsonError))
  self:assert_true(core.is_instance_of(decode_error, core.Error))
  self:assert_false(core.is_instance_of(decode_error, json.EncodeError))
  self:assert_equal("hecate.json.DecodeError", decode_error.code)
  self:assert_equal("hecate.json.EncodeError", encode_error.code)
  self:assert_equal("hecate.json.JsonError", json.JsonError.code)
end

function T:test_position_on_the_first_line()
  local err = failure(self, "[1, ?]")
  self:assert_equal(4, err.context.offset)
  self:assert_equal(1, err.context.line)
  self:assert_equal(5, err.context.column)
  self:assert_equal("syntax", err.context.reason)
  self:assert_true(tostring(err):find("line 1, column 5 (offset 4)", 1, true) ~= nil, tostring(err))
end

function T:test_position_after_line_feeds()
  local err = failure(self, '{\n  "a": 1,\n  "b": tru\n}')
  self:assert_equal(3, err.context.line)
  self:assert_equal(8, err.context.column)
  self:assert_equal(#'{\n  "a": 1,\n  "b": ' , err.context.offset)
end

function T:test_a_carriage_return_does_not_start_a_line()
  local err = failure(self, "[1,\r\n2,\r\n?]")
  self:assert_equal(3, err.context.line)
  self:assert_equal(1, err.context.column)
  local lone = failure(self, "[1,\r?]")
  self:assert_equal(1, lone.context.line)
  self:assert_equal(5, lone.context.column)
end

function T:test_column_counts_characters_not_bytes()
  local err = failure(self, '["\u{e9}\u{1F600}", ?]')
  -- characters before the offending one: [ " e-acute emoji " , space = 7 -> column 8
  self:assert_equal(8, err.context.column)
  self:assert_equal(#'["\u{e9}\u{1F600}", ', err.context.offset)
end

function T:test_unexpected_end_of_input_points_past_the_last_byte()
  local err = failure(self, "[1,\n")
  self:assert_equal(4, err.context.offset)
  self:assert_equal(2, err.context.line)
  self:assert_equal(1, err.context.column)
  self:assert_true(tostring(err):find("end of input", 1, true) ~= nil)
  local empty = failure(self, "")
  self:assert_equal(0, empty.context.offset)
  self:assert_equal(1, empty.context.line)
  self:assert_equal(1, empty.context.column)
end

function T:test_trailing_content_is_located()
  local err = failure(self, "[1] x")
  self:assert_equal(4, err.context.offset)
  self:assert_equal(5, err.context.column)
end

-- yyjson cannot say what was expected (OQ-54): the message names what was found only.
function T:test_the_message_names_what_was_found()
  local err = failure(self, '{"a" 1}')
  self:assert_true(err.message:find("unexpected character '1'", 1, true) ~= nil, err.message)
  self:assert_true(err.message:find("^unexpected") ~= nil, err.message) -- lower case, no trailing period
  self:assert_true(err.message:find("line 1, column 6 (offset 5)", 1, true) ~= nil, err.message)
end

function T:test_encode_errors_carry_a_json_pointer()
  local err = self:assert_error(function() return json.encode({ a = { 1, { b = 0 / 0 } } }) end)
  self:assert_true(core.is_instance_of(err, json.EncodeError), tostring(err))
  self:assert_equal("non_finite_number", err.context.reason)
  self:assert_equal("/a/1/b", err.context.path)
  local escaped = self:assert_error(function() return json.encode({ ["a/b~c"] = print }) end)
  self:assert_equal("/a~1b~0c", escaped.context.path)
  local top = self:assert_error(function() return json.encode(print) end)
  self:assert_equal("", top.context.path)
end

return T
