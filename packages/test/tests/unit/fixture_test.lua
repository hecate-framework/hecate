-- Fixtures: an application booted for a test, with container overrides applied before validation.
global <const> require

local hecate_test = require("hecate.test")
local kernel = require("hecate.kernel")
local core = require("hecate.core")

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

return core.finalise(T)
