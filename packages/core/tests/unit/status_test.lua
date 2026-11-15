local test = require("harness.test")
local status = require("hecate.core.status")
local core = require("hecate.core")
local T = test.Case("StatusTest")

function T:test_reason_of_registered_codes()
  self:assert_equal("OK", status.reason(200))
  self:assert_equal("Not Found", status.reason(404))
  self:assert_equal("Unprocessable Content", status.reason(422))
  self:assert_equal("Content Too Large", status.reason(413))
  self:assert_equal("Network Authentication Required", status.reason(511))
  self:assert_equal("I'm a teapot", status.reason(418))
end

function T:test_reason_of_unregistered_code_is_nil()
  self:assert_nil(status.reason(299))
  self:assert_nil(status.reason(600))
  self:assert_nil(status.reason(404.5))
end

function T:test_every_registered_code_is_valid_and_has_a_class()
  local count = 0
  for code = 100, 599 do
    local reason = status.reason(code)
    if reason ~= nil then
      count = count + 1
      self:assert_true(status.is_valid(code))
      self:assert_true(status.class(code) ~= nil)
      self:assert_true(#reason > 0)
    end
  end
  self:assert_equal(62, count)
end

function T:test_is_valid_accepts_integers_from_100_to_599_only()
  self:assert_true(status.is_valid(100))
  self:assert_true(status.is_valid(599))
  self:assert_false(status.is_valid(99))
  self:assert_false(status.is_valid(600))
  self:assert_false(status.is_valid(200.0))
  self:assert_false(status.is_valid("200"))
  self:assert_false(status.is_valid(nil))
end

function T:test_is_error_accepts_integers_from_400_to_599_only()
  self:assert_true(status.is_error(400))
  self:assert_true(status.is_error(599))
  self:assert_false(status.is_error(399))
  self:assert_false(status.is_error(100))
  self:assert_false(status.is_error(600))
  self:assert_false(status.is_error(404.0))
  self:assert_false(status.is_error("404"))
  self:assert_false(status.is_error(nil))
end

function T:test_class_of_a_code()
  self:assert_equal("informational", status.class(101))
  self:assert_equal("successful", status.class(204))
  self:assert_equal("redirection", status.class(302))
  self:assert_equal("client_error", status.class(499))
  self:assert_equal("server_error", status.class(503))
  self:assert_nil(status.class(600))
  ---@diagnostic disable-next-line: param-type-mismatch  -- a non-integer is given on purpose
  self:assert_nil(status.class("404"))
end

function T:test_forbids_content()
  for _, code in ipairs({ 100, 101, 204, 205, 304 }) do self:assert_true(status.forbids_content(code), code) end
  for _, code in ipairs({ 200, 206, 301, 404, 500 }) do self:assert_false(status.forbids_content(code), code) end
end

function T:test_exported_on_the_core_module()
  self:assert_equal(status, core.status)
end

return T
