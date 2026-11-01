---@diagnostic disable: missing-fields, param-type-mismatch  -- the tests pass invalid arguments on purpose
local test = require("harness.test")
local core = require("hecate.core")
local json = require("hecate.json")
local reactor = require("hecate.reactor")
local http = require("hecate.http")
local T = test.Case("ProblemTest")

local problem = http.problem

function T:test_response_is_rfc_9457_problem_details()
  local response = problem.response(404, "No such thing.")
  self:assert_equal(404, response.status)
  self:assert_equal("application/problem+json", response.fields:get("Content-Type"))
  local body = json.decode(response.content)
  self:assert_equal("about:blank", body.type)
  self:assert_equal("Not Found", body.title)
  self:assert_equal(404, body.status)
  self:assert_equal("No such thing.", body.detail)
end

function T:test_response_refuses_a_status_that_is_not_an_error()
  self:assert_error(function() problem.response(200) end)
  self:assert_error(function() problem.response(600) end)
end

function T:test_a_transport_error_becomes_a_generic_detail_without_addresses_or_errno()
  local err = reactor.TransportError({
    message = "net.connect: connect to db.internal:5432 failed: ECONNREFUSED connection refused (tried 10.1.2.3, 10.1.2.4)",
    context = { errno = "ECONNREFUSED", host = "db.internal", port = 5432,
      attempts = { { address = "10.1.2.3", errno = "ECONNREFUSED" }, { address = "10.1.2.4", errno = "ETIMEDOUT" } } },
  })
  local status, detail = problem.of_error(err)
  self:assert_equal(500, status)
  local text = json.encode(json.decode(problem.from_error(err).content))
  for _, secret in ipairs({ "10.1.2.3", "10.1.2.4", "ECONNREFUSED", "ETIMEDOUT", "db.internal", "5432" }) do
    self:assert_nil(text:find(secret, 1, true), secret .. " leaked into " .. text)
    self:assert_nil(detail:find(secret, 1, true))
  end
end

function T:test_other_errors_and_strings_are_generic()
  for _, err in ipairs({ "boom: /etc/secret", core.Error("password is hunter2"), core.ArgumentError("x") }) do
    local response = problem.from_error(err)
    self:assert_equal(500, response.status)
    self:assert_nil(response.content:find("hunter2", 1, true))
    self:assert_nil(response.content:find("secret", 1, true))
  end
end

function T:test_content_errors_keep_their_status_and_not_their_text()
  local err = http.ContentError({ message = "limit 12345 exceeded", context = { status = 413, reason = "too_large", limit = 12345 } })
  local response = problem.from_error(err)
  self:assert_equal(413, response.status)
  self:assert_nil(response.content:find("12345", 1, true))
  local timeout = http.ContentError({ message = "x", context = { status = 408, reason = "timeout" } })
  self:assert_equal(408, problem.from_error(timeout).status)
end
return T
