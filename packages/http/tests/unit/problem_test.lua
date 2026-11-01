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
function T:test_every_error_class_maps_to_a_status_and_a_fixed_detail_that_echoes_nothing()
  local net = require("hecate.net")
  local Parser = require("hecate.http.errors")
  local SECRET = "SECRET-10.9.8.7-/etc/passwd"
  local function e(class, context) return class({ message = SECRET, context = context or {} }) end
  local cases = {
    { e(Parser.ParseError, { status = 400, reason = "x", detail = SECRET, code = SECRET, position = 0 }), 400 },
    { e(Parser.ParseError, { status = 414, reason = "target_too_long", detail = SECRET }), 414 },
    { e(Parser.ParseError, { status = 431, reason = "head_too_large", detail = SECRET }), 431 },
    { e(http.ContentError, { status = 413, reason = "too_large", limit = 1 }), 413 },
    { e(http.ContentError, { status = 408, reason = "timeout" }), 408 },
    { e(http.ContentError, { status = 400, reason = "truncated" }), 400 },
    { e(http.FormError, { status = 415, reason = "unsupported_media_type" }), 415 },
    { e(http.FormError, { status = 400, reason = "bad_part_fields" }), 400 },
    { e(http.FormError, { status = 413, reason = "too_many_parts" }), 413 },
    { e(reactor.TransportError, { errno = SECRET, host = SECRET, attempts = { { address = SECRET } } }), 500 },
    { e(core.NetworkError), 500 },
    { e(net.EndOfStreamError), 500 },
    { e(net.TlsError, { reason = SECRET }), 500 },
    { e(core.DeadlineExceededError), 500 },
    { e(core.CancellationError), 500 },
    { e(core.ArgumentError), 500 },
    { e(core.ProtocolError, { status = 418 }), 500 },
    { e(core.Error), 500 },
    { SECRET, 500 }, { { message = SECRET }, 500 }, { 42, 500 }, { false, 500 },
  }
  for index, case in ipairs(cases) do
    local response = problem.from_error(case[1])
    self:assert_equal(case[2], response.status, "case " .. index)
    self:assert_equal("application/problem+json", response.fields:get("Content-Type"))
    self:assert_nil(response.content:find("SECRET", 1, true), "case " .. index .. " echoed: " .. response.content)
    self:assert_nil(response.content:find("10.9.8.7", 1, true))
    self:assert_equal("string", type(json.decode(response.content).detail))
  end
end

return T
