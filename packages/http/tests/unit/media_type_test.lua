---@diagnostic disable: param-type-mismatch, need-check-nil  -- the tests pass invalid arguments on purpose
local test = require("harness.test")
local http = require("hecate.http")
local MediaType = http.MediaType
local T = test.Case("MediaTypeTest")

function T:test_parse_basic_and_lowercases()
  local m = MediaType.parse("Application/JSON; Charset=UTF-8")
  self:assert_equal("application", m.type)
  self:assert_equal("json", m.subtype)
  self:assert_equal("UTF-8", m.parameters.charset)
  self:assert_equal("application/json", m:essence())
end

function T:test_parse_quoted_string_with_escapes()
  local m = MediaType.parse('multipart/form-data; boundary="a;b\\"c"')
  self:assert_equal('a;b"c', m.parameters.boundary)
end

function T:test_first_duplicate_parameter_wins_and_order_kept()
  local m = MediaType.parse("text/plain; b=1; a=2; b=3")
  self:assert_equal("1", m.parameters.b)
  self:assert_equal("b,a", table.concat(m.order, ","))
end

function T:test_format_round_trip_quotes_when_needed()
  local m = MediaType("text", "plain", { charset = "utf-8" })
  self:assert_equal("text/plain; charset=utf-8", m:format())
  local q = MediaType("multipart", "form-data", { boundary = 'a b"c' })
  self:assert_equal('multipart/form-data; boundary="a b\\"c"', tostring(q))
  self:assert_equal('a b"c', MediaType.parse(q:format()).parameters.boundary)
end

function T:test_malformed_input_returns_nil_and_reason()
  for _, bad in ipairs({ "", "text", "text/", "/plain", "te xt/plain", "a/b; c", "a/b; c=\"x", "a/b c=d" }) do
    local m, reason = MediaType.parse(bad)
    self:assert_nil(m, bad)
    self:assert_not_nil(reason)
  end
  self:assert_nil((MediaType.parse(nil)))
end

function T:test_suffix_and_matches()
  local m = MediaType.parse("application/problem+json")
  self:assert_equal("json", m:suffix())
  self:assert_nil(MediaType.parse("text/plain"):suffix())
  self:assert_true(m:matches("application/*"))
  self:assert_true(m:matches("*/*"))
  self:assert_true(m:matches("Application/Problem+JSON"))
  self:assert_false(m:matches("text/*"))
end

function T:test_constructor_rejects_non_tokens()
  self:assert_error(function() MediaType("te xt", "plain") end)
  self:assert_error(function() MediaType("text", "plain", { ["a b"] = "c" }) end)
  self:assert_error(function() MediaType("text", "plain", { a = "x\r\ny" }) end)
end

return T
