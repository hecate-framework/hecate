---@diagnostic disable: missing-fields, param-type-mismatch, need-check-nil  -- the tests pass invalid arguments on purpose
local test = require("harness.test")
local core = require("hecate.core")
local form = require("hecate.http.form")
local T = test.Case("FormTest")

local function kind_of(self, text, limits)
  local err = self:assert_error(function() form.parse_urlencoded(text, limits) end)
  self:assert_true(core.is_instance_of(err, form.FormError), tostring(err))
  self:assert_true(core.is_instance_of(err, core.ProtocolError))
  return err.context.kind, err.context.status, err
end

function T:test_pairs_are_decoded_in_order_with_repeated_names()
  local f = form.parse_urlencoded("a=1&b=two+words&a=%C3%A9&empty=&novalue&=x&&")
  self:assert_equal(6, f:count())
  self:assert_equal("1", f:get("a"))
  self:assert_equal("two words", f:get("b"))
  self:assert_equal("é", f:get_all("a")[2])
  self:assert_equal("", f:get("empty"))
  self:assert_equal("", f:get("novalue"))
  self:assert_equal("x", f:get(""))
  self:assert_nil(f:get("missing"))
  local names = {}
  for name in f:pairs() do names[#names + 1] = name end
  self:assert_equal("a,b,a,empty,novalue,", table.concat(names, ","))
  self:assert_equal(0, form.parse_urlencoded(""):count())
end

function T:test_a_value_keeps_equals_signs_after_the_first()
  self:assert_equal("b=c", form.parse_urlencoded("a=b%3Dc"):get("a"))
  self:assert_equal("b=c", form.parse_urlencoded("a=b=c"):get("a"))
end

function T:test_malformed_percent_sequences_invalid_utf8_and_nul_are_400()
  for _, text in ipairs({ "a=%", "a=%4", "a=%zz", "a=%4z", "%=1", "a=1%" }) do
    local kind, status = kind_of(self, text)
    self:assert_equal("bad_percent_encoding", kind, text)
    self:assert_equal(400, status)
  end
  self:assert_equal("invalid_utf8", (kind_of(self, "a=%FF")))
  self:assert_equal("invalid_utf8", (kind_of(self, "a=%C3")))
  self:assert_equal("nul_in_value", (kind_of(self, "a=x%00y")))
end

function T:test_limits_are_413_and_the_message_holds_no_input()
  local kind, status, err = kind_of(self, "a=1&b=2&c=3", { max_pairs = 2 })
  self:assert_equal("too_many_pairs", kind)
  self:assert_equal(413, status)
  self:assert_equal("too_large", (kind_of(self, "a=" .. ("x"):rep(100), { max_size = 50 })))
  self:assert_equal(2, form.parse_urlencoded("a=1&b=2", { max_pairs = 2 }):count())
  local secret = select(3, kind_of(self, "password=%zz"))
  self:assert_nil(tostring(secret):find("password", 1, true))
  self:assert_error(function() form.parse_urlencoded("a=1", { max_pairs = -1 }) end)
  self:assert_error(function() form.parse_urlencoded("a=1", { unknown = 1 }) end)
  self:assert_error(function() form.parse_urlencoded(42) end)
  self:assert_equal(1000, form.DEFAULTS.max_pairs)
end

function T:test_encoding_round_trips_and_escapes_everything_else()
  self:assert_equal("a=1&b=two+words&c=%C3%A9%26%3D%25", form.encode_urlencoded({ { "a", "1" }, { "b", "two words" }, { "c", "é&=%" } }))
  local pairs_ = { { "n ame", "v\r\nal" }, { "x", "" }, { "x", "*-._" } }
  local back = form.parse_urlencoded(form.encode_urlencoded(pairs_))
  self:assert_equal("v\r\nal", back:get("n ame"))
  self:assert_equal(2, #back:get_all("x"))
  self:assert_equal("a=1", form.encode_urlencoded(form.Form({ { "a", "1" } })))
  self:assert_equal("", form.encode_urlencoded({}))
  self:assert_error(function() form.encode_urlencoded({ { "a" } }) end)
  self:assert_error(function() form.encode_urlencoded("a=1") end)
end

return T
