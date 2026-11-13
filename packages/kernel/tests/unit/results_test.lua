local test = require("harness.test")
local core = require("hecate.core")
local json = require("hecate.json")
local schema = require("hecate.schema")
local http = require("hecate.http")
local results = require("hecate.kernel.results")
local T = test.Case("ResultsTest")

local User = core.class("ResultsUser", nil, { implements = { schema.Representable } })
function User.schema()
  return schema.object({ name = schema.string(), age = schema.optional(schema.integer()) })
end
function User:init(name, age, secret)
  self.name, self.age, self.secret = name, age, secret
end
core.finalise(User)

local Plain = core.class("ResultsPlain")
function Plain:init() self.x = 1 end
core.finalise(Plain)

--- The content of a response, decoded and encoded again in canonical form.
---@param response hecate.http.Response
---@return string
local function canonical(response)
  return json.encode(json.decode(response.content --[[@as string]]), { canonical = true })
end

---@param value any
---@return any
local function invalid(value) return value end

local user_schema = schema.of(User)

local function request(method, accept)
  local fields = http.Fields()
  if accept then fields:set("Accept", accept) end
  return http.Request({ method = method, target = "/users", fields = fields })
end

function T:test_response_is_returned_as_is()
  local response = http.Response(202)
  self:assert_true(results.serialise(response, request("GET"), {}) == response)
end

function T:test_problem_response_is_returned_as_is()
  local response = http.problem.response(404)
  self:assert_true(results.serialise(response, request("GET"), {}) == response)
end

function T:test_value_is_represented_with_the_schema_of_200_then_encoded()
  local response = results.serialise(User("ada", 36, "s3cret"), request("GET"), { [200] = user_schema })
  self:assert_equal(200, response.status)
  self:assert_equal("application/json", response.fields:get("Content-Type"))
  self:assert_equal(json.encode({ name = "ada", age = 36 }, { canonical = true }), canonical(response))
  self:assert_nil((response.content --[[@as string]]):find("s3cret", 1, true))
end

function T:test_post_with_only_201_declared_answers_201()
  local response = results.serialise(User("ada"), request("POST"), { [201] = user_schema })
  self:assert_equal(201, response.status)
  self:assert_equal(json.encode({ name = "ada" }, { canonical = true }), canonical(response))
end

function T:test_post_with_200_declared_answers_200_unless_created()
  local declared = { [200] = user_schema, [201] = user_schema }
  self:assert_equal(200, results.serialise(User("a"), request("POST"), declared).status)
  self:assert_equal(201, results.serialise(User("a"), request("GET"), declared, { created = true }).status)
end

function T:test_plain_value_without_schema_is_encoded_as_is()
  local response = results.serialise({ a = 1 }, request("GET"), {})
  self:assert_equal(json.encode({ a = 1 }, { canonical = true }), canonical(response))
  self:assert_equal("\"hi\"", results.serialise("hi", request("GET"), {}).content)
end

function T:test_instance_without_schema_raises_an_error()
  local err = self:assert_error(function() results.serialise(Plain(), request("GET"), {}) end)
  self:assert_equal("hecate.core.ArgumentError", err.code)
end

function T:test_nil_is_204_when_declared_else_200_empty()
  local declared = results.serialise(nil, request("DELETE"), { [204] = true })
  self:assert_equal(204, declared.status)
  self:assert_nil(declared.content)
  local other = results.serialise(nil, request("GET"), { [200] = user_schema })
  self:assert_equal(200, other.status)
  self:assert_nil(other.content)
end

function T:test_representation_failure_propagates_without_a_response()
  local Status = core.enumeration("ResultsStatus", { "on", "off" })
  local err = self:assert_error(function()
    results.serialise({ name = "s3cret" }, request("GET"), { [200] = schema.enumeration(Status) })
  end)
  self:assert_equal("hecate.core.ValidationError", err.code)
end

function T:test_respond_uses_the_schema_of_its_status()
  local result = results.respond(201, User("ada", 1, "s3cret"))
  local response = results.serialise(result, request("GET"), { [200] = schema.string(), [201] = user_schema })
  self:assert_equal(201, response.status)
  self:assert_equal(json.encode({ name = "ada", age = 1 }, { canonical = true }), canonical(response))
end

function T:test_respond_accepts_an_explicit_schema_and_nil_value()
  local response = results.serialise(results.respond(202, User("a"), user_schema), request("GET"), {})
  self:assert_equal(json.encode({ name = "a" }, { canonical = true }), canonical(response))
  local empty = results.serialise(results.respond(204), request("GET"), {})
  self:assert_equal(204, empty.status)
  self:assert_nil(empty.content)
end

function T:test_respond_is_a_tagged_table_not_a_response()
  local result = results.respond(200, { a = 1 })
  self:assert_equal("table", type(result))
  self:assert_true(results.is_result(result))
  self:assert_false(results.is_result({ status = 200, value = 1 }))
end

function T:test_respond_refuses_a_bad_status()
  self:assert_error(function() results.respond(invalid("x"), 1) end)
  self:assert_error(function() results.respond(99, 1) end)
end

function T:test_accept_absent_star_and_json_are_served()
  for _, accept in ipairs({ "*/*", "application/*", "application/json", "text/html, application/json;q=0.5", "application/json; charset=utf-8" }) do
    self:assert_equal(200, results.serialise({ 1 }, request("GET", accept), {}).status, accept)
  end
end

function T:test_unacceptable_accept_is_a_406_problem_without_detail_of_the_value()
  local response = results.serialise({ secret = "s3cret" }, request("GET", "text/html"), {})
  self:assert_equal(406, response.status)
  self:assert_equal("application/problem+json", response.fields:get("Content-Type"))
  self:assert_nil((response.content --[[@as string]]):find("s3cret", 1, true))
  self:assert_equal(406, results.serialise({ 1 }, request("GET", "application/json;q=0"), {}).status)
end

function T:test_a_more_specific_range_overrides_a_wildcard_and_q_zero_excludes()
  -- RFC 9110, section 12.5.1: the most specific range that matches a media type gives its weight; q=0 is "not acceptable".
  for _, accept in ipairs({ "application/json;q=0, */*", "*/*, application/json;q=0", "application/*;q=0, */*",
    "*/*;q=0.5, application/json; q=0", "*/*;q=0" }) do
    self:assert_equal(406, results.serialise({ 1 }, request("GET", accept), {}).status, accept)
  end
  for _, accept in ipairs({ "text/*;q=0, */*", "application/json;q=0.2, */*", "*/*;q=0, application/json", "application/*;q=0, application/json" }) do
    local response = results.serialise({ 1 }, request("GET", accept), {})
    self:assert_equal(200, response.status, accept)
    self:assert_equal("application/json", response.fields:get("Content-Type"), accept)
  end
  local serialisers = { ["application/json"] = results.serialisers["application/json"], ["text/plain"] = function() return "plain" end }
  local function chosen(accept)
    return results.serialise({ a = 1 }, request("GET", accept), {}, { serialisers = serialisers }).fields:get("Content-Type")
  end
  self:assert_equal("text/plain", chosen("*/*, application/json;q=0"))
  self:assert_equal("text/plain", chosen("application/json;q=0.5, */*;q=0.8"))
  self:assert_equal("application/json", chosen("*/*")) -- equal weights: JSON is preferred
  self:assert_equal("text/plain", chosen("text/plain, */*")) -- equal weights: the range written first
end

function T:test_serialisers_table_plugs_in_a_media_type()
  local serialisers = { ["application/json"] = results.serialisers["application/json"], ["text/plain"] = function(plain) return "plain:" .. tostring(plain.a) end }
  local response = results.serialise({ a = 1 }, request("GET", "text/plain, application/json;q=0.1"), {}, { serialisers = serialisers })
  self:assert_equal("text/plain", response.fields:get("Content-Type"))
  self:assert_equal("plain:1", response.content)
end

function T:test_default_serialisers_hold_json_only()
  self:assert_equal("function", type(results.serialisers["application/json"]))
  local n = 0
  for _ in pairs(results.serialisers) do n = n + 1 end
  self:assert_equal(1, n)
end

function T:test_kernel_respond_is_results_respond()
  local kernel = require("hecate.kernel")
  self:assert_true(kernel.respond == results.respond)
  local result = kernel.respond(201, { id = 1 })
  self:assert_true(results.is_result(result))
  self:assert_equal(201, result.status)
end

-- Response validation in development and test (http-and-routing.md, "Results and serialisation").

local named = schema.object({ name = schema.string() })

function T:test_without_validation_a_nonconforming_value_is_encoded()
  local response = results.serialise({ name = 3 }, request("GET"), { [200] = named })
  self:assert_equal(200, response.status)
end

function T:test_validation_refuses_a_nonconforming_value_with_a_validation_error()
  local ok, err = pcall(results.serialise, { name = 3 }, request("GET"), { [200] = named }, { validate_responses = true })
  self:assert_false(ok)
  self:assert_true(core.is_instance_of(err, core.ValidationError))
  ---@cast err -hecate.http.Response, +hecate.core.ValidationError
  self:assert_equal(200, err.context.status)
  self:assert_equal("/name", err.context.violations[1].path)
  self:assert_not_nil(string.find(tostring(err), "status 200", 1, true))
end

function T:test_validation_accepts_a_conforming_representation_of_an_instance()
  local response = results.serialise(User("ada", 36, "s3cret"), request("GET"), { [200] = user_schema },
    { validate_responses = true })
  self:assert_equal(200, response.status)
  self:assert_equal(json.encode({ name = "ada", age = 36 }, { canonical = true }), canonical(response))
end

function T:test_validation_checks_a_result_of_respond_against_the_schema_of_its_status()
  local ok, err = pcall(results.serialise, results.respond(201, { name = false }), request("POST"),
    { [201] = named }, { validate_responses = true })
  self:assert_false(ok)
  ---@cast err -hecate.http.Response, +hecate.core.ValidationError
  self:assert_equal(201, err.context.status)
  local response = results.serialise(results.respond(201, { name = "x" }), request("POST"), { [201] = named },
    { validate_responses = true })
  self:assert_equal(201, response.status)
end

function T:test_validation_skips_a_status_without_schema_and_a_response()
  self:assert_equal(200, results.serialise({ any = 1 }, request("GET"), {}, { validate_responses = true }).status)
  self:assert_equal(204, results.serialise(nil, request("GET"), { [204] = true }, { validate_responses = true }).status)
  local response = http.Response(202)
  self:assert_true(results.serialise(response, request("GET"), { [202] = named }, { validate_responses = true }) == response)
end

function T:test_validation_message_names_the_code_and_never_the_pointer()
  local _, err = pcall(results.serialise, { name = 3 }, request("GET"), { [200] = named }, { validate_responses = true })
  local text = tostring(err)
  self:assert_nil(string.find(text, "/name", 1, true))
  self:assert_not_nil(string.find(text, "status 200", 1, true))
  ---@cast err -hecate.http.Response, +hecate.core.ValidationError
  self:assert_not_nil(string.find(text, err.context.violations[1].code, 1, true))
end

function T:test_validation_message_hides_a_map_key_of_the_data()
  local mapped = schema.object({ tags = schema.map(schema.string()) })
  local _, err = pcall(results.serialise, { tags = { ["ada@example.org"] = 1 } }, request("GET"), { [200] = mapped },
    { validate_responses = true })
  self:assert_nil(string.find(tostring(err), "ada@example.org", 1, true))
end

function T:test_validation_message_never_carries_the_value()
  local _, err = pcall(results.serialise, { name = 12345 }, request("GET"), { [200] = named }, { validate_responses = true })
  self:assert_nil(string.find(tostring(err), "12345", 1, true))
end

return T
