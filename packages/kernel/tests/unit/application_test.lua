---@diagnostic disable: need-check-nil, param-type-mismatch, missing-fields, undefined-field, assign-type-mismatch, inject-field
local test = require("harness.test")
local http = require("hecate.http")
local kernel = require("hecate.kernel")
local T = test.Case("ApplicationTest")

local function get(serve, path)
  return serve(http.Request({ method = "GET", target = path, fields = http.Fields() }))
end

local function route_module(name, path)
  local m = kernel.routes(name)
  m:get(path, { action = function() return { ok = name } end })
  return m
end

function T:test_modules_are_ordered_after_their_requirements()
  local order = {}
  local function mod(name, requires)
    return { name = name, requires = requires, services = function() order[#order + 1] = name end }
  end
  local app = kernel.Application({ modules = { mod("a", { "b" }), mod("b", { "c" }), mod("c") } })
  app:boot()
  self:assert_equal("c,b,a", table.concat(order, ","))
end

function T:test_boot_gathers_routes_services_and_serves()
  local app = kernel.Application({
    routes = { route_module("health", "/health") },
    modules = { { name = "users", routes = { route_module("users", "/users") },
      services = function(c) c:bind("answer", function() return 42 end, { lifetime = "singleton" }) end } },
  })
  local serve = app:boot()
  self:assert_equal(200, get(serve, "/health").status)
  self:assert_equal(200, get(serve, "/users").status)
  self:assert_equal(404, get(serve, "/nope").status)
  self:assert_equal(42, app.container:resolve("answer"))
end

function T:test_module_errors_have_stable_reasons()
  local function reason(list)
    local ok, err = pcall(function() kernel.Application({ modules = list }):boot() end)
    self:assert_false(ok)
    self:assert_true(require("hecate.core").is_instance_of(err, kernel.ModuleError))
    return err.context.reason
  end
  self:assert_equal("duplicate_module", reason({ { name = "a" }, { name = "a" } }))
  self:assert_equal("missing_dependency", reason({ { name = "a", requires = { "x" } } }))
  self:assert_equal("dependency_cycle", reason({ { name = "a", requires = { "b" } }, { name = "b", requires = { "a" } } }))
  self:assert_equal("invalid_module", reason({ { name = "a", bogus = 1 } }))
  self:assert_equal("invalid_module", reason({ "a" }))
end

function T:test_a_second_boot_and_unknown_options_are_refused()
  local app = kernel.Application()
  app:boot()
  local ok, err = pcall(app.boot, app)
  self:assert_false(ok)
  self:assert_equal("already_booted", err.context.reason)
  self:assert_false(pcall(kernel.Application, { bogus = true }))
end

function T:test_filters_of_the_application_wrap_those_of_modules()
  local seen = {}
  local function filter(name)
    return { handle = function(_, request, next) seen[#seen + 1] = name; return next(request) end }
  end
  local app = kernel.Application({
    filters = { filter("app") },
    routes = { route_module("r", "/r") },
    modules = { { name = "m", filters = { filter("module") } } },
  })
  get(app:boot(), "/r")
  self:assert_equal("app,module", table.concat(seen, ","))
end

local config = require("hecate.config")
local log = require("hecate.log")

local function configuration(env, environment)
  return config.load({
    properties = {}, environment = environment or "development",
    getenv = function(name) return env[name] end,
    read_file = function(path)
      if path:match("^config/.+%.lua$") and not path:match("default") then return "return {}" end
      return nil, "no such file: " .. path, true
    end,
  })
end

function T:test_configuration_binds_inputs_and_exposure()
  local app = kernel.Application({ configuration = configuration({
    HECATE_REQUESTS__INPUTS = "lax", HECATE_ERRORS__EXPOSE_DETAILS = "true",
  }) })
  app:boot()
  self:assert_equal("lax", app._resolved.inputs)
  self:assert_equal(true, app._resolved.expose_details)
  log.set_default(nil)
end

function T:test_explicit_options_override_the_configuration()
  local app = kernel.Application({ inputs = "strict", configuration = configuration({ HECATE_REQUESTS__INPUTS = "lax" }) })
  app:boot()
  self:assert_equal("strict", app._resolved.inputs)
  log.set_default(nil)
end

function T:test_configuration_builds_and_installs_the_default_logger()
  local app = kernel.Application({ configuration = configuration({
    HECATE_LOGGING__SEVERITY = "debug", HECATE_LOGGING__SINKS = "",
  }) })
  app:boot()
  self:assert_equal(app._resolved.logger, log.default())
  log.set_default(nil)
end

function T:test_file_sink_without_path_is_refused()
  local logging = require("hecate.kernel.logging")
  local ok = pcall(logging.build, { get = function() return { sinks = { "file" }, redact = {}, severities = {}, severity = "debug" } end })
  self:assert_false(ok)
end

function T:test_expose_details_in_production_warns_at_boot()
  local memory = log.MemorySink()
  local app = kernel.Application({
    logger = log.Logger({ sinks = { memory } }),
    configuration = configuration({ HECATE_ERRORS__EXPOSE_DETAILS = "true" }, "production"),
  })
  app:boot()
  local found
  for _, record in ipairs(memory:records()) do
    if record.fields and record.fields.code == "expose_details_in_production" then found = true end
  end
  self:assert_true(found)
  log.set_default(nil)
end

return T
