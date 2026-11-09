local test = require("harness.test")
local core = require("hecate.core")
local json = require("hecate.json")
local schema = require("hecate.schema")
local http = require("hecate.http")
local reactor = require("hecate.reactor")
local problems = require("hecate.kernel.problems")
local T = test.Case("ProblemsTest")

local SECRET <const> = "s3cr3t-/etc/passwd-10.0.0.7"

---@param response hecate.http.Response
local function body(response) return json.decode(response.content --[[@as string]]) end

---@param match table
---@return hecate.http.Response
local function failure_of(match)
  local response = problems.from_match(match --[[@as hecate.router.Match]])
  assert(response ~= nil, "the match is a failure")
  return response
end

local function request() return http.Request({ method = "GET", target = "/x", fields = http.Fields() }) end

---@param response hecate.http.Response
local function assert_no_leak(self, response)
  self:assert_nil(string.find(response.content --[[@as string]], SECRET, 1, true))
end

function T:test_response_is_problem_json_with_the_members_of_rfc_9457()
  local response = problems.response(404)
  self:assert_equal(404, response.status)
  self:assert_equal("application/problem+json", response.fields:get("Content-Type"))
  local p = body(response)
  self:assert_equal("about:blank", p.type)
  self:assert_equal("Not Found", p.title)
  self:assert_equal(404, p.status)
  self:assert_equal("string", type(p.detail))
end

function T:test_response_refuses_a_status_outside_400_599()
  self:assert_equal("hecate.core.ArgumentError", self:assert_error(function() problems.response(200) end).code)
end

function T:test_not_found_and_method_not_allowed_from_a_router_match()
  local nf = failure_of({ status = 404 })
  self:assert_equal(404, nf.status)
  local na = failure_of({ status = 405, allow = { "GET", "HEAD" }, allow_field = "GET, HEAD" })
  self:assert_equal(405, na.status)
  self:assert_equal("GET, HEAD", na.fields:get("Allow"))
  self:assert_equal("application/problem+json", na.fields:get("Content-Type"))
end

function T:test_unreadable_path_is_a_400_without_the_reason()
  local response = failure_of({ status = 400, reason = SECRET })
  self:assert_equal(400, response.status)
  assert_no_leak(self, response)
end

function T:test_a_match_that_is_not_a_failure_gives_nil()
  self:assert_nil(problems.from_match({ status = 200 } --[[@as hecate.router.Match]]))
  self:assert_nil(problems.from_match({ status = 204 } --[[@as hecate.router.Match]]))
end

function T:test_input_validation_error_is_a_422_with_one_entry_per_violation()
  local s = schema.object({ name = schema.string(), age = schema.integer() })
  local ok, violations = s:validate({ age = "x" })
  self:assert_false(ok)
  assert(violations ~= nil)
  local err = core.ValidationError("bad " .. SECRET, { context = { violations = violations } })
  local response = problems.from_error(err, { input = true })
  self:assert_equal(422, response.status)
  local p = body(response)
  self:assert_equal(#violations, #p.errors)
  for i, v in ipairs(violations) do
    self:assert_equal(v.path, p.errors[i].pointer)
    self:assert_equal(v.code, p.errors[i].code)
  end
  assert_no_leak(self, response)
end

function T:test_validation_error_is_a_500_unless_it_is_about_the_input()
  -- A represent failure of a response is a defect of the server (OQ-95), not of the client.
  local err = core.ValidationError(SECRET, { context = { violations = { schema.Violation("/a", "type", "m") } } })
  local response = problems.from_error(err)
  self:assert_equal(500, response.status)
  self:assert_nil(body(response).errors)
  assert_no_leak(self, response)
end

function T:test_input_flag_without_violations_is_a_500()
  self:assert_equal(500, problems.from_error(core.ValidationError(SECRET), { input = true }).status)
end

function T:test_violations_are_capped()
  local list = {}
  for i = 1, 500 do list[i] = schema.Violation("/" .. i, "type", "m") end
  local response = problems.from_error(core.ValidationError("x", { context = { violations = list } }), { input = true })
  self:assert_equal(problems.MAX_ERRORS, #body(response).errors)
end

function T:test_http_errors_keep_their_status_without_their_text()
  local err = http.ParseError(SECRET, { context = { status = 413 } })
  local response = problems.from_error(err)
  self:assert_equal(413, response.status)
  assert_no_leak(self, response)
end

function T:test_unexpected_errors_are_a_generic_500()
  for _, err in ipairs({
    core.Error(SECRET), core.ArgumentError(SECRET), core.IoError(SECRET), core.DatabaseError(SECRET),
    reactor.TransportError(SECRET), SECRET, { secret = SECRET }, 42,
  }) do
    local response = problems.from_error(err)
    self:assert_equal(500, response.status)
    assert_no_leak(self, response)
  end
end

function T:test_guard_passes_a_response_through()
  local expected = http.Response(200)
  local serve = problems.guard(function() return expected end)
  self:assert_true(serve(request()) == expected)
end

function T:test_guard_turns_an_error_into_a_500_and_returns_the_failure()
  local serve = problems.guard(function() error(core.Error(SECRET)) end)
  local response, failure = serve(request())
  self:assert_equal(500, response.status)
  assert_no_leak(self, response)
  self:assert_true(core.is_instance_of(failure, core.Error))
end

function T:test_guard_maps_a_lua_runtime_error_without_its_text()
  local serve = problems.guard(function() local x = nil; return x --[[@as table]].y end)
  local response, failure = serve(request())
  self:assert_equal(500, response.status)
  self:assert_equal("string", type(failure))
end

function T:test_guard_maps_input_validation_errors_to_422()
  local serve = problems.guard(function()
    schema.object({ a = schema.integer() }):check({ a = "x" })
    return http.Response(200)
  end, { input = true })
  self:assert_equal(422, (serve(request()) --[[@as hecate.http.Response]]).status)
end

function T:test_guard_logs_the_failure_once()
  local seen = {}
  local logger = { log = function(_, severity, message, fields) seen[#seen + 1] = { severity, message, fields } end }
  problems.guard(function() error(core.Error("boom")) end, { logger = logger })(request())
  self:assert_equal(1, #seen)
  self:assert_equal("error", seen[1][1])
end

function T:test_guard_never_swallows_cancellation()
  local serve = problems.guard(function() error(core.CancellationError("cancelled")) end)
  self:assert_equal("hecate.core.CancellationError", self:assert_error(function() serve(request()) end).code)
end

function T:test_guard_never_swallows_a_deadline()
  local serve = problems.guard(function() error(core.DeadlineExceededError("late")) end)
  self:assert_equal("hecate.core.DeadlineExceededError", self:assert_error(function() serve(request()) end).code)
end

return T
