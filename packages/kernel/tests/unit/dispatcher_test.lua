---@diagnostic disable: need-check-nil, param-type-mismatch, missing-fields, undefined-field, assign-type-mismatch, inject-field
local test = require("harness.test")
local core = require("hecate.core")
local json = require("hecate.json")
local http = require("hecate.http")
local schema = require("hecate.schema")
local container = require("hecate.container")
local kernel = require("hecate.kernel")
local dispatcher = require("hecate.kernel.dispatcher")
local T = test.Case("DispatcherTest")

local function request(method, target)
  return http.Request({ method = method, target = target, fields = http.Fields() })
end

local function serve_with(setup, options)
  local module = kernel.routes("t")
  setup(module)
  local serve = dispatcher.build(module:routes(), options)
  return serve
end

function T:test_a_matched_route_serves_a_value_as_json_with_the_path_parameters()
  local serve = serve_with(function(m)
    m:get("/users/{id}", { parameters = { path = { id = schema.string() } },
      action = function(r) return { id = r.parameters.path.id } end })
  end)
  local response = serve(request("GET", "/users/42"))
  self:assert_equal(200, response.status)
  self:assert_equal("42", json.decode(response.content).id)
end

function T:test_routing_failures_are_problem_responses()
  local serve = serve_with(function(m) m:get("/a", { action = function() return nil end }) end)
  self:assert_equal(404, serve(request("GET", "/nope")).status)
  local not_allowed = serve(request("POST", "/a"))
  self:assert_equal(405, not_allowed.status)
  self:assert_equal("GET, HEAD, OPTIONS", not_allowed.fields:get("Allow"))
  local options = serve(request("OPTIONS", "/a"))
  self:assert_equal(204, options.status)
  self:assert_equal("GET, HEAD, OPTIONS", options.fields:get("Allow"))
end

function T:test_filters_run_global_first_then_the_route_and_wrap_the_action()
  local trace = {}
  local function filter(name)
    return { handle = function(_, req, next)
      trace[#trace + 1] = name .. ">"
      local result = next(req)
      trace[#trace + 1] = "<" .. name
      return result
    end }
  end
  local serve = serve_with(function(m)
    m:get("/x", { filters = { filter("route") }, action = function() trace[#trace + 1] = "action" end })
  end, { filters = { filter("global") } })
  serve(request("GET", "/x"))
  self:assert_equal("global> route> action <route <global", table.concat(trace, " "))
end

function T:test_an_error_in_an_action_becomes_a_500_problem_and_is_logged()
  local logged = {}
  local serve = serve_with(function(m) m:get("/boom", { action = function() error("secret") end }) end,
    { logger = { log = function(_, severity, message) logged[#logged + 1] = severity .. ": " .. message end } })
  local response = serve(request("GET", "/boom"))
  self:assert_equal(500, response.status)
  self:assert_nil(string.find(response.content, "secret", 1, true))
  self:assert_equal(1, #logged)
end

function T:test_a_controller_gets_its_dependencies_from_the_request_scope()
  local Greeter = core.class("Greeter")
  function Greeter:greet() return "hello" end
  core.finalise(Greeter)
  local Hello = core.class("HelloController", kernel.Controller)
  Hello.prefix = "/hello"
  Hello.dependencies = { greeter = "greeter" }
  kernel.Controller.route(Hello, { method = "GET", path = "/", action = "say" })
  function Hello:say() return { text = self.greeter:greet() } end
  core.finalise(Hello)
  local c = container.Container():bind("greeter", Greeter, { lifetime = "scoped" }):validate()
  local serve = dispatcher.build(kernel.routing.collect({ Hello }), { container = c })
  local response = serve(request("GET", "/hello"))
  self:assert_equal(200, response.status)
  self:assert_equal("hello", json.decode(response.content).text)
end

function T:test_a_controller_with_dependencies_and_no_container_is_refused_at_build()
  local Hello = core.class("HelloController2", kernel.Controller)
  Hello.dependencies = { greeter = "greeter" }
  kernel.Controller.route(Hello, { method = "GET", path = "/h", action = "say" })
  function Hello:say() return nil end
  core.finalise(Hello)
  local err = self:assert_error(function() dispatcher.build(kernel.routing.collect({ Hello })) end)
  self:assert_equal("missing_container", err.context.reason)
end
function T:test_validate_responses_turns_a_nonconforming_result_into_a_logged_500()
  local logged = {}
  local options = { validate_responses = true,
    logger = { log = function(_, severity, message) logged[#logged + 1] = severity .. ": " .. message end } }
  local serve = serve_with(function(m)
    m:get("/bad", { responses = { [200] = schema.object({ id = schema.integer() }) },
      action = function() return { id = "not-an-integer" } end })
  end, options)
  local response = serve(request("GET", "/bad"))
  self:assert_equal(500, response.status)
  self:assert_nil(string.find(response.content, "not-an-integer", 1, true))
  self:assert_equal(1, #logged)
end

function T:test_responses_are_not_validated_by_default()
  local serve = serve_with(function(m)
    m:get("/bad", { responses = { [200] = schema.object({ id = schema.integer() }) },
      action = function() return { id = "x" } end })
  end)
  self:assert_equal(200, serve(request("GET", "/bad")).status)
end

function T:test_validate_responses_must_be_a_boolean()
  local ok, err = pcall(dispatcher.build, {}, { validate_responses = "yes" })
  self:assert_false(ok)
  self:assert_true(core.is_instance_of(err, core.ArgumentError))
end

return T
