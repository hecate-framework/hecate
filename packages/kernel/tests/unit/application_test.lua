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

function T:test_local_address_is_known_only_while_serving()
  local reactor = require("hecate.reactor")
  local app = kernel.Application({
    logger = log.Logger({ sinks = { log.MemorySink() } }), server = { host = "127.0.0.1", port = 0 },
    signals = false, routes = { kernel.routes("empty") },
  })
  self:assert_nil(app:local_address())
  local seen
  reactor.run(function()
    reactor.fork(function()
      while not app:local_address() do reactor.sleep(0.005) end
      seen = app:local_address()
      app:shutdown(0)
    end)
    reactor.deadline(10, app.serve, app)
  end)
  self:assert_equal("number", type(seen.port))
  self:assert_equal("127.0.0.1", seen.ip)
  self:assert_nil(app:local_address())
end

function T:test_configuration_binds_the_grace_timeout()
  local app = kernel.Application({ configuration = configuration({ HECATE_SERVER__GRACE_TIMEOUT = "2" }) })
  app:boot()
  self:assert_equal(2, app._resolved.grace_timeout)
  local default = kernel.Application({ configuration = configuration({}) })
  default:boot()
  self:assert_equal(30, default._resolved.grace_timeout)
  local explicit = kernel.Application({ grace_timeout = 5, configuration = configuration({ HECATE_SERVER__GRACE_TIMEOUT = "2" }) })
  explicit:boot()
  self:assert_equal(5, explicit._resolved.grace_timeout)
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

local reactor = require("hecate.reactor")
local uv = require("luv")

-- Raises `name` on this process repeatedly (a signal sent before the watcher listens is lost) until `done()`.
local function raise_until(name, done)
  reactor.fork(function()
    while not done() do
      uv.kill(uv.os_getpid(), name)
      reactor.sleep(0.005)
    end
  end)
end

local function codes(memory)
  local found = {}
  for _, record in ipairs(memory:records()) do
    if record.fields and record.fields.code then found[record.fields.code] = record.fields end
  end
  return found
end

function T:test_a_signal_shuts_the_server_down_gracefully()
  if uv.os_uname().sysname:match("Windows") then return end -- only console signals are delivered there
  -- The guard keeps a signal sent before the watcher is installed from ending the process.
  local guard = uv.new_signal()
  guard:start("sigterm", function() end)
  local memory = log.MemorySink()
  local app = kernel.Application({
    logger = log.Logger({ sinks = { memory } }), grace_timeout = 1,
    server = { host = "127.0.0.1", port = 0 },
  })
  reactor.run(function()
    local done = false
    raise_until("sigterm", function() return done end)
    reactor.deadline(5, app.serve, app)
    done = true
  end)
  guard:close()
  local found = codes(memory)
  self:assert_equal("sigterm", found.shutdown_signal.signal)
  self:assert_nil(found.shutdown_forced)
end

function T:test_a_second_signal_forces_the_stop()
  if uv.os_uname().sysname:match("Windows") then return end
  local guard = uv.new_signal()
  guard:start("sigterm", function() end)
  local memory = log.MemorySink()
  local routes = kernel.routes("slow")
  local started, cancelled = false, false
  routes:get("/slow", { action = function()
    started = true
    local ok, err = pcall(reactor.sleep, 60)
    if not ok then cancelled = true; error(err, 0) end
    return {}
  end })
  local app = kernel.Application({
    logger = log.Logger({ sinks = { memory } }), grace_timeout = 60, routes = { routes },
    server = { host = "127.0.0.1", port = 0 },
  })
  local began = uv.hrtime()
  reactor.run(function()
    local done = false
    reactor.fork(function()
      while not app:local_address() do reactor.sleep(0.005) end
      local port = app:local_address().port
      reactor.fork(function() pcall(http.Client().get, http.Client(), "http://127.0.0.1:" .. port .. "/slow") end)
      while not started do reactor.sleep(0.005) end
      raise_until("sigterm", function() return done or codes(memory).shutdown_forced ~= nil end)
    end)
    reactor.deadline(10, app.serve, app) -- a hang fails here instead of waiting for the 60 s grace
    done = true
  end)
  guard:close()
  self:assert_true((uv.hrtime() - began) / 1e9 < 10)
  self:assert_true(cancelled)
  local found = codes(memory)
  self:assert_equal("sigterm", found.shutdown_signal.signal)
  self:assert_equal("sigterm", found.shutdown_forced.signal)
end

function T:test_signals_false_serves_until_shutdown()
  local app = kernel.Application({ signals = false, server = { host = "127.0.0.1", port = 0 } })
  reactor.run(function()
    reactor.fork(function() reactor.sleep(0.01); app:shutdown(1) end)
    reactor.deadline(5, app.serve, app)
  end)
  self:assert_nil(app._server)
end

function T:test_invalid_signal_options_are_refused()
  for _, value in ipairs({ {}, { "sigint" }, { "sigusr2" }, "sigterm", true, 15 }) do
    local ok, err = pcall(kernel.Application, { signals = value })
    self:assert_false(ok)
    self:assert_true(tostring(err):find("signal set is fixed", 1, true) ~= nil)
  end
  self:assert_false(pcall(kernel.Application, { grace_timeout = -1 }))
  self:assert_false(pcall(kernel.Application, { grace_timeout = math.huge }))
end

local function secret_options(extra)
  local options = {
    properties = { database = require("hecate.schema").object({ password = require("hecate.schema").string() }) },
    environment = "development", secrets = { "database.password" },
    getenv = function(name) if name == "HECATE_DATABASE__PASSWORD" then return "s3cret" end end,
    read_file = function(path)
      if path == "config/development.lua" then return "return {}" end
      return nil, "no such file: " .. path, true
    end,
  }
  for key, value in pairs(extra or {}) do options[key] = value end
  return options
end

function T:test_load_configuration_wraps_secrets_with_the_log_secret()
  -- Hide hecate.log from config's own look-up: the kernel must pass log.Secret itself (roadmap kernel (c)).
  local loaded = package.loaded["hecate.log"]
  package.loaded["hecate.log"] = nil
  local ok, result = pcall(kernel.load_configuration, secret_options())
  package.loaded["hecate.log"] = loaded
  self:assert_true(ok, tostring(result))
  local password = result:get("database.password")
  self:assert_true(require("hecate.core").is_instance_of(password, log.Secret))
  self:assert_equal("s3cret", password:reveal())
end

function T:test_load_configuration_keeps_an_explicit_wrapper()
  local function wrap(value) return { wrapped = value } end
  local configuration = kernel.load_configuration(secret_options({ wrap_secret = wrap }))
  self:assert_equal("s3cret", configuration:get("database.password").wrapped)
end

function T:test_load_configuration_refuses_a_non_table()
  self:assert_false(pcall(kernel.load_configuration, "config"))
end

return T
