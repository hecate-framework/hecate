---@diagnostic disable: missing-fields, param-type-mismatch, assign-type-mismatch, need-check-nil  -- the tests pass invalid arguments on purpose
-- The in-process request-serving seam (OQ-78): no socket, no native module. And the pure normalisation of a response frame.
local test = require("harness.test")
local core = require("hecate.core")
local reactor = require("hecate.reactor")
local json = require("hecate.json")
local http = require("hecate.http")
local responses = require("hecate.http.internal.server_response")
local T = test.Case("ServeRequestTest")

local Response, Request, Fields = http.Response, http.Request, http.Fields
local serve_request = http.serve_request

local function request() return Request({ method = "GET", target = "/" }) end

function T:test_a_response_passes_through_without_a_failure()
  local response = Response(200, { content = "hi" })
  local got, failure = serve_request(function(r) return response end, request())
  self:assert_true(got == response)
  self:assert_nil(failure)
end

function T:test_the_action_receives_the_request()
  local req = request()
  local seen
  serve_request(function(r) seen = r; return Response(204) end, req)
  self:assert_true(seen == req)
end

function T:test_an_error_maps_to_problem_details_by_its_class_and_is_returned()
  local err = http.ContentError({ message = "secret detail", context = { status = 413 } })
  local got, failure = serve_request(function() error(err, 0) end, request())
  self:assert_equal(413, got.status)
  self:assert_true(failure == err)
  self:assert_nil(got.content:find("secret", 1, true))
  local plain, failure2 = serve_request(function() error("boom") end, request())
  self:assert_equal(500, plain.status)
  self:assert_not_nil(failure2)
end

function T:test_a_table_as_content_is_an_error_mapped_to_the_generic_500()
  local got, failure = serve_request(function() return Response(200, { content = { id = 42, password = "hunter2" } }) end, request())
  self:assert_equal(500, got.status)
  self:assert_equal("application/problem+json", got.fields:get("Content-Type"))
  self:assert_equal("The server could not process the request.", json.decode(got.content).detail)
  self:assert_nil(got.content:find("hunter2", 1, true))
  self:assert_true(core.is_instance_of(failure, core.Error))
end

function T:test_a_result_the_server_cannot_send_is_a_500_with_a_failure()
  local function check(fn)
    local got, failure = serve_request(fn, request())
    self:assert_equal(500, got.status)
    self:assert_not_nil(failure)
  end
  check(function() return nil end)
  check(function() return "text" end)
  check(function() return { status = 200 } end)
  check(function() return Response(200, { content = 42 }) end)
  check(function() local r = Response(200); r.status = 99; return r end)
  check(function() local r = Response(200); r.fields = {}; return r end)
  check(function() local r = Response(200); r.reason = 1; return r end)
  check(function() return Response(101) end) -- an interim status is not a final response
end

function T:test_a_cancellation_is_raised_not_mapped()
  local err = core.CancellationError({ message = "cancelled" })
  local ok, raised = pcall(serve_request, function() error(err, 0) end, request())
  self:assert_false(ok)
  self:assert_true(raised == err)
end

function T:test_the_action_may_suspend()
  reactor.run(function()
    local got = serve_request(function() reactor.sleep(0.001); return Response(200, { content = "late" }) end, request())
    self:assert_equal("late", got.content)
  end)
end

-- Normalisation ---------------------------------------------------------------------------------------------------

local function info(extra)
  local t = { method = "GET", version = "HTTP/1.1", keep_alive = true }
  for k, v in pairs(extra or {}) do t[k] = v end
  return t
end

function T:test_normalise_sets_the_length_and_replaces_the_framing_fields_of_the_action()
  local response = Response(200, { content = "hello", fields = Fields({ { "Content-Length", "99" }, { "Transfer-Encoding", "chunked" }, { "Keep-Alive", "x" } }) })
  local fields, mode, text, close = responses.normalise(info(), response, false)
  self:assert_equal("length", mode)
  self:assert_equal("hello", text)
  self:assert_equal("5", fields:get("Content-Length"))
  self:assert_nil(fields:get("Transfer-Encoding"))
  self:assert_nil(fields:get("Keep-Alive"))
  self:assert_not_nil(fields:get("Date"))
  self:assert_false(close)
  self:assert_equal("99", response.fields:get("Content-Length"), "the response is not modified")
end

function T:test_normalise_keeps_head_204_and_1xx_free_of_content_and_head_keeps_the_length()
  local _, mode204 = responses.normalise(info(), Response(204), false)
  self:assert_equal("none", mode204)
  local fields, mode = responses.normalise(info({ method = "HEAD" }), Response(200, { content = "hello" }), false)
  self:assert_equal("length", mode)
  self:assert_equal("5", fields:get("Content-Length"))
  local streamed, smode = responses.normalise(info({ method = "HEAD" }), Response(200, { content = function() end }), false)
  self:assert_equal("chunked", smode)
  self:assert_nil(streamed:get("Transfer-Encoding"), "a HEAD response announces no coding it does not send")
end

function T:test_normalise_chunks_a_function_and_honours_a_declared_length()
  local fields, mode = responses.normalise(info(), Response(200, { content = function() end }), false)
  self:assert_equal("chunked", mode)
  self:assert_equal("chunked", fields:get("Transfer-Encoding"))
  local declared, dmode, text = responses.normalise(info(), Response(200, { content = function() end, fields = Fields({ { "Content-Length", "6" } }) }), false)
  self:assert_equal("declared", dmode)
  self:assert_equal("6", text)
  self:assert_equal("6", declared:get("Content-Length"))
  local _, cmode, _, close = responses.normalise(info({ version = "HTTP/1.0", keep_alive = false }), Response(200, { content = function() end }), false)
  self:assert_equal("close_delimited", cmode)
  self:assert_true(close)
end

function T:test_normalise_decides_the_connection_option()
  local fields, _, _, close = responses.normalise(info(), Response(200), true)
  self:assert_true(close)
  self:assert_equal("close", fields:get("Connection"))
  local _, _, _, by_action = responses.normalise(info(), Response(200, { fields = Fields({ { "Connection", "close" } }) }), false)
  self:assert_true(by_action)
  local _, _, _, by_request = responses.normalise(info({ keep_alive = false }), Response(200), false)
  self:assert_true(by_request)
  local one0 = responses.normalise(info({ version = "HTTP/1.0" }), Response(200), false)
  self:assert_equal("keep-alive", one0:get("Connection"))
end

function T:test_normalise_refuses_content_that_is_not_nil_a_string_or_a_function()
  self:assert_error(function() responses.normalise(info(), Response(200, { content = { a = 1 } }), false) end)
end
return T
