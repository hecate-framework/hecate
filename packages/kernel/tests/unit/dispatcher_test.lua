---@diagnostic disable: param-type-mismatch, assign-type-mismatch
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

-- A recording filter: its own trace entries, and the status of the response that comes back through it.
local function recording(trace, name)
  return { handle = function(_, req, next)
    trace[#trace + 1] = name .. ">"
    local response = next(req)
    trace[#trace + 1] = "<" .. name .. ":" .. tostring(response.status)
    return response
  end }
end

function T:test_global_filters_also_see_the_routing_answers()
  local trace = {}
  local serve = serve_with(function(m) m:get("/a", { action = function() return nil end }) end,
    { filters = { recording(trace, "global") } })
  self:assert_equal(404, serve(request("GET", "/nope")).status)
  self:assert_equal(405, serve(request("POST", "/a")).status)
  self:assert_equal(204, serve(request("OPTIONS", "/a")).status)
  self:assert_equal("global> <global:404 global> <global:405 global> <global:204", table.concat(trace, " "))
end

function T:test_a_global_filter_sees_no_matched_route_before_the_action()
  local seen = {}
  local filter = { handle = function(_, req, next)
    local empty = true
    for _ in pairs(req.parameters.path) do empty = false end
    seen[#seen + 1] = empty and "empty" or "filled"
    return next(req)
  end }
  local serve = serve_with(function(m) m:get("/a/{id}", { parameters = { path = { id = schema.string() } },
    action = function() return nil end }) end, { filters = { filter } })
  self:assert_equal(404, serve(request("GET", "/nope")).status)
  self:assert_equal("empty", seen[1])
end

function T:test_an_error_in_an_action_flows_back_through_the_global_filters_as_a_problem()
  local trace = {}
  local serve = serve_with(function(m) m:get("/boom", { action = function() error("secret") end }) end,
    { filters = { recording(trace, "global") } })
  local response = serve(request("GET", "/boom"))
  self:assert_equal(500, response.status)
  self:assert_equal("global> <global:500", table.concat(trace, " "))
end

function T:test_an_error_in_a_global_filter_is_still_a_500_problem()
  local failing = { handle = function() error("secret") end }
  local serve = serve_with(function(m) m:get("/a", { action = function() return nil end }) end,
    { filters = { failing } })
  local response = serve(request("GET", "/a"))
  self:assert_equal(500, response.status)
  self:assert_nil(string.find(response.content, "secret", 1, true))
end

function T:test_the_layers_run_global_module_controller_route()
  local trace = {}
  local function filter(name)
    return { handle = function(_, req, next) trace[#trace + 1] = name; return next(req) end }
  end
  local Things = core.class("LayeredController", kernel.Controller)
  Things.prefix = "/c"
  Things.filters = { filter("controller") }
  kernel.Controller.route(Things, { method = "GET", path = "/", filters = { filter("route") }, action = "list" })
  function Things:list() return nil end
  core.finalise(Things)
  local serve = dispatcher.build(kernel.routing.collect({ Things }, { filter("module") }), { filters = { filter("global") } })
  serve(request("GET", "/c"))
  self:assert_equal("global,module,controller,route", table.concat(trace, ","))
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

function T:test_a_controller_gets_its_dependencies_from_the_request_services()
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

function T:test_request_services_is_the_service_scope_and_leaves_the_reactor_scope_alone()
  local Greeter = core.class("Greeter2")
  core.finalise(Greeter)
  local c = container.Container():bind("greeter", Greeter, { lifetime = "scoped" }):validate()
  local seen
  local serve = serve_with(function(m)
    m:get("/s", { action = function(r)
      seen = { services = r.services, reactor_scope = r.scope, first = r.services:resolve("greeter"),
        second = r.services:resolve("greeter") }
    end })
  end, { container = c })
  local req = request("GET", "/s")
  local marker = {}
  req.scope = marker -- what `http.Server` sets: the reactor scope of the request
  serve(req)
  self:assert_true(seen.services ~= nil)
  self:assert_true(seen.first == seen.second)
  self:assert_true(seen.reactor_scope == marker)
end

function T:test_the_dependencies_of_a_controller_are_resolved_in_sorted_key_order()
  local order = {}
  local function service(name)
    local class = core.class("Service_" .. name)
    function class:init() order[#order + 1] = name end
    return core.finalise(class)
  end
  local Hello = core.class("OrderedController", kernel.Controller)
  Hello.dependencies = { zeta = "z", alpha = "a", mid = "m" }
  kernel.Controller.route(Hello, { method = "GET", path = "/", action = "say" })
  function Hello:say() return nil end
  core.finalise(Hello)
  local c = container.Container():bind("z", service("z"), { lifetime = "transient" })
    :bind("a", service("a"), { lifetime = "transient" }):bind("m", service("m"), { lifetime = "transient" }):validate()
  local serve = dispatcher.build(kernel.routing.collect({ Hello }), { container = c })
  for _ = 1, 3 do
    order = {}
    serve(request("GET", "/"))
    self:assert_equal("a m z", table.concat(order, " "))
  end
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
