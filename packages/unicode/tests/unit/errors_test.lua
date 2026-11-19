---@diagnostic disable: need-check-nil, param-type-mismatch, undefined-field
local test = require("harness.test")
local core = require("hecate.core")
local unicode = require("hecate.unicode")
local T = test.Case("UnicodeErrorsTest")

function T:test_invalid_utf8_is_an_error_object_with_the_position()
  for _, bad in ipairs({ "\xFF", "ab\xFFcd", "\xC0\x80", "\xED\xA0\x80", "\xF4\x90\x80\x80", "e\xCC" }) do
    for _, normalise in ipairs({ unicode.nfc, unicode.nfd, unicode.is_nfc, unicode.is_nfd }) do
      local err = self:assert_error(function() normalise(bad) end)
      self:assert_true(core.is_instance_of(err, unicode.InvalidUtf8Error), bad)
      self:assert_true(core.is_instance_of(err, unicode.UnicodeError))
      self:assert_true(core.is_instance_of(err, core.Error))
      self:assert_equal("hecate.unicode.InvalidUtf8Error", err.code)
      self:assert_equal("number", type(err.context.position))
    end
  end
  local err = self:assert_error(function() unicode.nfc("ab\xFFcd") end)
  self:assert_equal(3, err.context.position, "1-based byte position of the first invalid byte")
end

function T:test_a_value_that_is_not_a_string_is_an_argument_error()
  for _, value in ipairs({ 1, true, {}, print }) do
    local err = self:assert_error(function() unicode.nfc(value) end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError))
  end
  self:assert_true(core.is_instance_of(self:assert_error(function() unicode.nfd(nil) end), core.ArgumentError))
end

return T
