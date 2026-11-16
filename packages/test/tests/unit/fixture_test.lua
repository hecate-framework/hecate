global <const> require, table, rawget, error
global <const> require, table

local hecate_test = require("hecate.test")
local kernel = require("hecate.kernel")
local core = require("hecate.core")
local schema = require("hecate.schema")

local T = hecate_test.Case("FixtureTest")

local function options()
  local routes = kernel.routes("greeting")
  routes:get("/greeting", { name = "greeting", action = function(request)
    return { greeting = request.services:resolve("greeter") }
  end })
  return {
    routes = { routes },
    modules = { { name = "greetings",
      services = function(c) c:bind("greeter", function() return "real" end, { lifetime = "scoped" }) end } },
  }
end

function T:test_an_instance_replaces_a_service_bound_by_a_module()
  local client, application = hecate_test.boot(options(), { { key = "greeter", value = "fake" } })
  self:assert_equal("fake", application.container:resolve("greeter"))
  local response = client:get("/greeting")
  self:assert_equal(200, response.status)
  self:assert_match('"fake"', response:read_content())
end

function T:test_a_definition_with_options_replaces_the_binding()
  local _, application = hecate_test.boot(options(), {
    { key = "greeter", definition = function() return "built" end, options = { lifetime = "singleton" } } })
  self:assert_equal("built", application.container:resolve("greeter"))
end

function T:test_without_overrides_the_application_is_unchanged()
  local client = hecate_test.boot(options())
  self:assert_match('"real"', client:get("/greeting"):read_content())
end

function T:test_overriding_an_unbound_key_fails_naming_it()
  self:assert_error(function() hecate_test.boot(options(), { { key = "missing", value = 1 } }) end,
    { class = require("hecate.container").MissingBindingError })
end

function T:test_bad_overrides_raise_argument_error()
  ---@type any
  local text, entry = "x", { value = 1 }
  self:assert_error(function() hecate_test.boot(options(), text) end, { class = core.ArgumentError })
  self:assert_error(function() hecate_test.boot(options(), { entry }) end, { class = core.ArgumentError })
  self:assert_error(function() hecate_test.boot(options(), { { key = "greeter" } }) end, { class = core.ArgumentError })
end

local function api()
  local routes = kernel.routes("api")
  routes:get("/users", { name = "list_users", action = function() return { users = {} } end })
  routes:get("/users/{id}", { name = "show_user", parameters = { path = { id = schema.string() } }, action = function(request) return { id = request.parameters.path.id } end })
  routes:delete("/users/{id}", { name = "delete_user", parameters = { path = { id = schema.string() } }, action = function() return { deleted = true } end })
  return { routes = { routes } }
end

function T:test_the_coverage_lists_the_routes_a_test_exercised_and_those_it_missed()
  local client, _, coverage = hecate_test.boot(api())
  self:assert_equal(0, #coverage:exercised())
  self:assert_equal("delete_user,list_users,show_user", table.concat(coverage:missed(), ","))
  client:get("/users")
  client:get("/users/42")
  client:get("/users/43")
  client:get("/nowhere")
  self:assert_equal("list_users,show_user", table.concat(coverage:exercised(), ","))
  self:assert_equal("delete_user", table.concat(coverage:missed(), ","))
  self:assert_match("2 of 3 routes exercised", coverage:report())
  self:assert_match("not exercised: delete_user", coverage:report())
end

function T:test_a_405_does_not_exercise_the_route()
  local client, _, coverage = hecate_test.boot(api())
  self:assert_equal(405, (client:post("/users")).status)
  self:assert_equal(0, #coverage:exercised())
end

local function typed(declared)
  local routes = kernel.routes("typed")
  routes:get("/item", { name = "item", responses = { [200] = schema.object({ id = schema.integer() }) },
    action = function() return { id = "not an integer" } end })
  return { routes = { routes }, validate_responses = declared }
end

function T:test_responses_are_validated_against_their_schema_by_default()
  local client = hecate_test.boot(typed(nil))
  self:assert_equal(500, client:get("/item").status)
  local lenient = hecate_test.boot(typed(false))
  self:assert_equal(200, lenient:get("/item").status)
end

function T:test_a_failed_boot_leaves_a_given_container_as_it_was()
  local container = require("hecate.container").Container()
  local raw = rawget(container, "validate")
  local broken = options()
  broken.container = container
  broken.modules = { { name = "broken", services = function() error("services failed", 0) end } }
  self:assert_error(function() hecate_test.boot(broken, { { key = "greeter", value = "x" } }) end)
  self:assert_equal(raw, rawget(container, "validate"))
end

function T:test_a_validate_of_the_given_container_is_kept()
  local container = require("hecate.container").Container()
  local original = container.validate
  local calls = 0
  local own = function(self) calls = calls + 1 return original(self) end
  container.validate = own
  local given = options()
  given.container = container
  hecate_test.boot(given, { { key = "greeter", value = "fake" } })
  self:assert_equal(own, rawget(container, "validate"))
  self:assert_equal(1, calls)
end

return core.finalise(T)
