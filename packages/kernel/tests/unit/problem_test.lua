local test = require("harness.test")
local core = require("hecate.core")
local json = require("hecate.json")
local http = require("hecate.http")
local schema = require("hecate.schema")
local problem = require("hecate.kernel.problem")
local problems = require("hecate.kernel.problems")
local results = require("hecate.kernel.results")
local T = test.Case("ProblemTest")

local SECRET <const> = "s3cr3t-/etc/passwd-10.0.0.7"

---@param response hecate.http.Response
local function body(response) return json.decode(response.content --[[@as string]]) end

local function request() return http.Request({ method = "GET", target = "/x", fields = http.Fields() }) end

function T:test_common_classes_carry_status_and_reason_phrase_as_title()
  local expected = {
    BadRequest = 400, Unauthorized = 401, Forbidden = 403, NotFound = 404, MethodNotAllowed = 405,
    Conflict = 409, Gone = 410, UnprocessableContent = 422, TooManyRequests = 429,
    InternalServerError = 500, ServiceUnavailable = 503,
  }
  for name, status in pairs(expected) do
    local class = problem[name]
    self:assert_equal(status, class.status)
    self:assert_equal(http.Status.reason(status), class.title)
    self:assert_equal("about:blank", class.type)
    local instance = class({})
    self:assert_equal(status, instance.status)
    self:assert_equal(http.Status.reason(status), instance.title)
    self:assert_equal("about:blank", instance.type)
    self:assert_nil(instance.detail)
    self:assert_true(core.is_instance_of(instance, problem.Problem))
  end
end

function T:test_instance_is_built_by_calling_the_class_with_a_table()
  local p = problem.NotFound({ detail = "No such user.", extensions = { user_id = 7 } })
  self:assert_equal("No such user.", p.detail)
  self:assert_equal(7, p.extensions.user_id)
  self:assert_true(problem.is_problem(p))
  self:assert_false(problem.is_problem({ status = 404 }))
  self:assert_nil(next(problem.NotFound().extensions))
end

function T:test_a_problem_is_raisable_and_is_an_error()
  local ok, err = pcall(function() error(problem.NotFound({ detail = "gone" })) end)
  self:assert_false(ok)
  self:assert_true(core.is_instance_of(err, problem.NotFound))
  self:assert_true(core.is_instance_of(err, core.Error))
  self:assert_equal("gone", assert(err).detail)
end

function T:test_reserved_extension_names_are_refused()
  for _, name in ipairs({ "type", "title", "status", "detail", "instance" }) do
    local err = self:assert_error(function() problem.NotFound({ extensions = { [name] = "x" } }) end)
    self:assert_equal("hecate.core.ArgumentError", err.code)
  end
end

function T:test_invalid_fields_are_refused()
  for _, fields in ipairs({ { detail = 3 }, { extensions = "x" }, { extensions = { [1] = "x" } }, { bogus = 1 } }) do
    local err = self:assert_error(function() problem.NotFound(fields) end)
    self:assert_equal("hecate.core.ArgumentError", err.code)
  end
end

function T:test_extension_values_json_cannot_carry_are_refused_at_construction()
  for _, value in ipairs({ function() end, 0 / 0, math.huge, -math.huge, coroutine.create(function() end) }) do
    local err = self:assert_error(function() problem.NotFound({ extensions = { v = value } }) end)
    self:assert_equal("hecate.core.ArgumentError", err.code)
  end
  self:assert_equal(1.5, problem.NotFound({ extensions = { v = 1.5 } }).extensions.v)
end

function T:test_an_extension_that_cannot_be_encoded_answers_a_logged_generic_500()
  local nested = {}
  nested.self = nested -- a cycle passes the construction check, which is shallow
  local seen = {}
  local logger = { log = function(_, severity, message, fields) seen[#seen + 1] = { severity, message, fields } end }
  local p = problem.Conflict({ detail = "Taken.", extensions = { loop = nested } })
  local response = problems.from_problem(p, logger)
  self:assert_equal(500, response.status)
  self:assert_equal("application/problem+json", response.fields:get("Content-Type"))
  self:assert_nil(body(response).loop)
  self:assert_equal(1, #seen)
  self:assert_equal("error", seen[1][1])
  self:assert_equal("hecate.problem.Conflict", seen[1][3].problem)
  -- Raised as an error, through `from_error` and returned by an action, the answer is the same.
  self:assert_equal(500, problems.from_error(p, { logger = logger }).status)
  self:assert_equal(500, results.serialise(p, request(), {}, { logger = logger }).status)
  self:assert_equal(3, #seen)
  for _, entry in ipairs(seen) do self:assert_equal("hecate.problem.Conflict", entry[3].problem) end
end

function T:test_define_declares_an_own_class()
  local Teapot = problem.define("OutOfTea", { status = 418, title = "Out of tea", type = "https://example.test/out-of-tea" })
  self:assert_equal(418, Teapot.status)
  local p = Teapot({ detail = "Refill." })
  self:assert_equal("https://example.test/out-of-tea", p.type)
  self:assert_true(core.is_instance_of(p, problem.Problem))
  local response = problems.from_error(p)
  self:assert_equal(418, response.status)
  self:assert_equal("https://example.test/out-of-tea", body(response).type)
end

function T:test_define_refuses_invalid_declarations()
  local bad = {
    { "", { status = 400, title = "t" } }, { "A", { status = 200, title = "t" } }, { "A", { status = 400 } },
    { "A", { status = 400, title = "" } }, { "A", { status = 400, title = "t", type = 3 } }, { "A", "x" },
    { "A", { status = 400.5, title = "t" } },
  }
  for _, case in ipairs(bad) do
    local err = self:assert_error(function() problem.define(case[1], case[2]) end)
    self:assert_equal("hecate.core.ArgumentError", err.code)
  end
end

function T:test_from_error_maps_a_raised_problem()
  local response = problems.from_error(problem.Conflict({ detail = "Taken.", extensions = { field = "email" } }))
  self:assert_equal(409, response.status)
  self:assert_equal("application/problem+json", response.fields:get("Content-Type"))
  local p = body(response)
  self:assert_equal("about:blank", p.type)
  self:assert_equal("Conflict", p.title)
  self:assert_equal(409, p.status)
  self:assert_equal("Taken.", p.detail)
  self:assert_equal("email", p.field)
  self:assert_nil(p.instance)
end

function T:test_a_problem_without_detail_has_no_detail_member()
  self:assert_nil(body(problems.from_error(problem.Gone())).detail)
end

function T:test_serialise_answers_a_returned_problem_like_from_error()
  local p = problem.NotFound({ detail = "No such user.", extensions = { id = 1 } })
  local response = results.serialise(p, request(), {})
  self:assert_equal(404, response.status)
  self:assert_equal("application/problem+json", response.fields:get("Content-Type"))
  self:assert_equal(problems.from_error(p).content, response.content)
end

function T:test_guard_maps_a_raised_problem()
  local serve = problems.guard(function() error(problem.Forbidden({ detail = "No." })) end)
  local response = serve(request())
  self:assert_equal(403, response.status)
  self:assert_equal("No.", body(response).detail)
end

function T:test_a_problems_own_members_are_shown_with_expose_details_off_and_on()
  local p = problem.Conflict({ detail = "Mine.", extensions = { k = "v" } })
  for _, expose in ipairs({ false, true }) do
    local b = body(problems.from_error(p, { expose_details = expose }))
    self:assert_equal("Mine.", b.detail)
    self:assert_equal("v", b.k)
    self:assert_nil(b.debug)
  end
end

function T:test_expose_details_adds_violation_messages_to_422_entries()
  local err = core.ValidationError("x", { context = { violations = { schema.Violation("/a", "type", "must be a string") } } })
  local off = body(problems.from_error(err, { input = true }))
  self:assert_nil(off.errors[1].message)
  self:assert_nil(body(problems.from_error(err, { input = true, expose_details = false })).errors[1].message)
  local on = body(problems.from_error(err, { input = true, expose_details = true }))
  self:assert_equal("must be a string", on.errors[1].message)
  self:assert_equal("/a", on.errors[1].pointer)
end

function T:test_expose_details_adds_debug_to_a_generic_500_only_when_on()
  local err = core.IoError(SECRET)
  local off = problems.from_error(err)
  self:assert_nil(string.find(off.content --[[@as string]], SECRET, 1, true))
  self:assert_nil(body(off).debug)
  self:assert_nil(body(problems.from_error(err, { expose_details = false })).debug)
  local on = body(problems.from_error(err, { expose_details = true }))
  self:assert_equal(500, on.status)
  self:assert_equal("IoError", on.debug.error)
  self:assert_true(string.find(on.debug.message, SECRET, 1, true) ~= nil)
  self:assert_nil(on.debug.traceback)
end

function T:test_debug_carries_the_traceback_when_the_error_has_one()
  local was = core.is_debug_mode()
  core.set_debug_mode(true)
  local err = core.Error(SECRET)
  core.set_debug_mode(was)
  local on = body(problems.from_error(err, { expose_details = true }))
  self:assert_equal("string", type(on.debug.traceback))
end

function T:test_debug_for_a_value_that_is_not_an_error()
  local on = body(problems.from_error(SECRET, { expose_details = true }))
  self:assert_equal("string", on.debug.error)
  self:assert_equal(SECRET, on.debug.message)
end

function T:test_expose_details_does_not_touch_a_client_error_of_http()
  local on = body(problems.from_error(http.ParseError(SECRET, { context = { status = 413 } }), { expose_details = true }))
  self:assert_equal(413, on.status)
  self:assert_nil(on.debug)
  self:assert_nil(string.find(on.detail, SECRET, 1, true))
end

function T:test_guard_honours_expose_details()
  local serve = problems.guard(function() error(core.Error(SECRET)) end, { expose_details = true })
  self:assert_true(string.find(body((serve(request()))).debug.message, SECRET, 1, true) ~= nil)
  local quiet = problems.guard(function() error(core.Error(SECRET)) end)
  self:assert_nil(body((quiet(request()))).debug)
end

function T:test_a_problem_class_is_a_route_response_declaration()
  -- The route table keeps the class; only `status` is needed from it.
  local responses = { [404] = problem.NotFound }
  self:assert_equal(404, responses[404].status)
  self:assert_true(problem.is_class(problem.NotFound))
  self:assert_false(problem.is_class(core.Error))
  self:assert_false(problem.is_class(problem.NotFound()))
end

return T
