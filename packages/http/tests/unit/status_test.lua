local test = require("harness.test")
local Status = require("hecate.http").Status
local T = test.Case("StatusTest")

function T:test_reasons()
  self:assert_equal("OK", Status.reason(200))
  self:assert_equal("Not Found", Status.reason(404))
  self:assert_equal("Content Too Large", Status.reason(413))
  self:assert_equal("Unprocessable Content", Status.reason(422))
  self:assert_nil(Status.reason(299))
end

function T:test_validity_and_class()
  self:assert_true(Status.is_valid(100))
  self:assert_true(Status.is_valid(599))
  self:assert_false(Status.is_valid(99))
  self:assert_false(Status.is_valid(600))
  self:assert_false(Status.is_valid(200.5))
  self:assert_false(Status.is_valid("200"))
  self:assert_equal("informational", Status.class(101))
  self:assert_equal("successful", Status.class(204))
  self:assert_equal("redirection", Status.class(302))
  self:assert_equal("client_error", Status.class(404))
  self:assert_equal("server_error", Status.class(503))
  self:assert_nil(Status.class(700))
end

function T:test_forbids_content()
  for _, code in ipairs({ 100, 101, 204, 304 }) do self:assert_true(Status.forbids_content(code)) end
  for _, code in ipairs({ 200, 205, 301, 404, 500 }) do self:assert_false(Status.forbids_content(code)) end
end

return T
