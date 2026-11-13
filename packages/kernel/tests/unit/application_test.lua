---@diagnostic disable: need-check-nil, missing-fields, undefined-field, param-type-mismatch, assign-type-mismatch
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
  self:assert_equal("invalid_module", reason({ { name = "m", filters = { 42 } } })) -- no routes: still refused at boot
  self:assert_equal("invalid_module", reason({ { name = "m", filters = { {} } } }))
end

function T:test_a_malformed_module_filter_names_the_module()
  local ok, err = pcall(function() kernel.Application({ modules = { { name = "billing", filters = { { handle = function() end }, 42 } } } }):boot() end)
  self:assert_false(ok)
  self:assert_equal("invalid_module", err.context.reason)
  self:assert_equal("billing", err.context.module)
  self:assert_true(tostring(err.message):find("element 2", 1, true) ~= nil, tostring(err.message))
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
    modules = { { name = "m", routes = { route_module("r", "/r") }, filters = { filter("module") } } },
  })
  get(app:boot(), "/r")
  self:assert_equal("app,module", table.concat(seen, ","))
end

function T:test_the_filters_of_a_module_apply_only_to_the_routes_of_that_module()
  local seen = {}
  local function filter(name)
    return { handle = function(_, request, next) seen[#seen + 1] = name; return next(request) end }
  end
  local app = kernel.Application({
    filters = { filter("app") },
    routes = { route_module("health", "/health") },
    modules = {
      { name = "a", routes = { route_module("a", "/a") }, filters = { filter("a") } },
      { name = "b", routes = { route_module("b", "/b") }, filters = { filter("b") } },
    },
  })
  local serve = app:boot()
  get(serve, "/b")
  self:assert_equal("app,b", table.concat(seen, ","))
  seen = {}
  get(serve, "/a")
  self:assert_equal("app,a", table.concat(seen, ","))
  seen = {}
  get(serve, "/health")
  self:assert_equal("app", table.concat(seen, ","))
end

function T:test_global_filters_see_a_request_with_no_matching_route()
  local statuses = {}
  local app = kernel.Application({
    filters = { { handle = function(_, request, next)
      local response = next(request)
      statuses[#statuses + 1] = response.status
      return response
    end } },
    modules = { { name = "m", routes = { route_module("r", "/r") } } },
  })
  get(app:boot(), "/missing")
  self:assert_equal("404", table.concat(statuses, ","))
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

function T:test_a_failed_boot_changes_no_process_wide_setting()
  local json = require("hecate.json")
  local sentinel = log.Logger({ sinks = {} })
  log.set_default(sentinel)
  local depth = json.DEFAULT_MAX_DEPTH
  local missing = { { name = "a", requires = { "x" } } } -- a missing dependency fails the boot
  local app = kernel.Application({ modules = missing, max_depth = 7, configuration = configuration({}) })
  local ok = pcall(app.boot, app)
  local after_depth, after_logger = json.DEFAULT_MAX_DEPTH, log.default()
  log.set_default(nil)
  self:assert_false(ok)
  self:assert_equal(depth, after_depth)
  self:assert_true(rawequal(sentinel, after_logger))
  self:assert_nil(app.container)
  self:assert_nil(app._resolved)
  -- A successful boot applies both.
  local good = kernel.Application({ max_depth = 7, configuration = configuration({}) })
  good:boot()
  local applied_depth, applied_logger = json.DEFAULT_MAX_DEPTH, log.default()
  json.set_max_depth(depth)
  log.set_default(nil)
  self:assert_equal(7, applied_depth)
  self:assert_true(rawequal(good._resolved.logger, applied_logger))
end

function T:test_serve_runs_once()
  local core = require("hecate.core")
  local reactor = require("hecate.reactor")
  local app = kernel.Application({ signals = false, server = { host = "127.0.0.1", port = 0 } })
  local failures = {}
  reactor.run(function()
    reactor.fork(function()
      while not app:local_address() do reactor.sleep(0.005) end
      local ok, err = pcall(app.serve, app) -- while serving
      failures[#failures + 1] = not ok and err or false
      app:shutdown(1)
    end)
    reactor.deadline(10, app.serve, app)
    local ok, err = pcall(app.serve, app) -- after the shutdown
    failures[#failures + 1] = not ok and err or false
  end)
  self:assert_equal(2, #failures)
  for _, err in ipairs(failures) do
    self:assert_true(core.is_instance_of(err, kernel.ModuleError), tostring(err))
    self:assert_equal("already_served", err.context.reason)
  end
end

function T:test_a_serve_that_fails_before_the_run_leaves_the_application_servable()
  local core = require("hecate.core")
  local reactor = require("hecate.reactor")
  local app = kernel.Application({ signals = false, server = { host = "127.0.0.1", port = 0, bogus = true } })
  reactor.run(function()
    local ok, err = pcall(app.serve, app)
    self:assert_false(ok)
    self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
    -- Not served: the same failure again, never `already_served`, and the container is still open.
    local again, second = pcall(app.serve, app)
    self:assert_false(again)
    self:assert_true(core.is_instance_of(second, core.ArgumentError), tostring(second))
    self:assert_nil(app._served)
  end)
  -- With corrected options (a new application: the options are fixed at creation) serving works.
  local fixed = kernel.Application({ signals = false, server = { host = "127.0.0.1", port = 0 } })
  reactor.run(function()
    reactor.fork(function()
      while not fixed:local_address() do reactor.sleep(0.005) end
      fixed:shutdown(1)
    end)
    reactor.deadline(10, fixed.serve, fixed)
  end)
end

function T:test_serve_without_the_native_module_of_http_names_the_build_command()
  local core = require("hecate.core")
  local reactor = require("hecate.reactor")
  -- Simulates an `http` whose native module is not built: `Server` is nil and `available` says why.
  local saved_server, saved_available = http.Server, http.available
  http.Server = nil
  http.available = function()
    return false, "module 'hecate.http.native' not found (run `lua tools/run.lua build-native http`)"
  end
  local app = kernel.Application({ signals = false, server = { host = "127.0.0.1", port = 0 } })
  local primary = kernel.Application({ signals = false, workers = 2, server = { host = "127.0.0.1", port = 0 } })
  local ok, err, ok2, err2
  reactor.run(function()
    ok, err = pcall(app.serve, app)
    ok2, err2 = pcall(primary.serve, primary)
  end)
  http.Server, http.available = saved_server, saved_available
  for _, case in ipairs({ { ok, err }, { ok2, err2 } }) do
    self:assert_false(case[1])
    self:assert_true(core.is_instance_of(case[2], kernel.ModuleError), tostring(case[2]))
    self:assert_equal("http_unavailable", case[2].context.reason)
    self:assert_true(tostring(case[2].message):find("lua tools/run.lua build-native http", 1, true) ~= nil,
      tostring(case[2].message))
  end
  -- Not served: the application can be served once the module is there.
  self:assert_nil(app._served)
  self:assert_nil(primary._served)
end

function T:test_a_primary_that_cannot_tell_how_to_start_a_worker_stays_servable()
  local core = require("hecate.core")
  local reactor = require("hecate.reactor")
  local saved = _G.arg
  _G.arg = nil -- no main program: `worker_command_from` raises
  local app = kernel.Application({ signals = false, workers = 2, server = { host = "127.0.0.1", port = 0 } })
  local ok, err
  reactor.run(function() ok, err = pcall(app.serve, app) end)
  _G.arg = saved
  self:assert_false(ok)
  self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
  self:assert_nil(app._served)
  self:assert_nil(app._supervisor)
end

--- An application that believes it serves as a primary, with a supervisor whose `reload` is `behaviour`.
local function reloading_application(behaviour)
  local memory = log.MemorySink()
  local app = kernel.Application({ logger = log.Logger({ sinks = { memory } }) })
  app._supervisor = { reload = behaviour }
  return app, memory
end

--- The first record of `memory` whose `code` field is `code`.
local function record_with(memory, code)
  for _, record in ipairs(memory:records()) do
    if record.fields and record.fields.code == code then return record end
  end
end

local function codes_logged(memory)
  local codes = {}
  for _, record in ipairs(memory:records()) do codes[#codes + 1] = record.fields and record.fields.code end
  return codes
end

function T:test_a_refused_reload_logs_reload_refused_and_never_reload_started()
  local reactor = require("hecate.reactor")
  for _, reason in ipairs({ "reload_in_progress", "stopping", "not_running" }) do
    local app, memory = reloading_application(function()
      error(kernel.SupervisorError("refused", { context = { reason = reason } }), 0)
    end)
    reactor.run(function()
      local err = self:assert_error(function() app:reload() end)
      self:assert_equal(reason, err.context.reason)
    end)
    self:assert_equal(1, #codes_logged(memory), reason)
    self:assert_equal("reload_refused", codes_logged(memory)[1], reason)
  end
end

function T:test_an_accepted_reload_logs_started_before_done_or_failed()
  local reactor = require("hecate.reactor")
  local app, memory = reloading_application(function(_, options) options.on_accepted() end)
  reactor.run(function() app:reload() end)
  self:assert_equal("reload_started", codes_logged(memory)[1])
  self:assert_equal("reload_done", codes_logged(memory)[2])
  -- Documented in website/en/how-to/before-going-to-production.md (Logging): the workers reloaded are `notice`.
  self:assert_true(record_with(memory, "reload_started").severity == log.Severity.notice)
  self:assert_true(record_with(memory, "reload_done").severity == log.Severity.notice)
  local failing, failed = reloading_application(function(_, options)
    options.on_accepted()
    error(kernel.SupervisorError("failed", { context = { reason = "reload_failed", cause = "not_ready" } }), 0)
  end)
  reactor.run(function() self:assert_error(function() failing:reload() end) end)
  self:assert_equal("reload_started", codes_logged(failed)[1])
  self:assert_equal("reload_failed", codes_logged(failed)[2])
end

function T:test_responses_are_validated_in_development_and_test_only()
  for environment, expected in pairs({ development = true, test = true, production = false, staging = false }) do
    local app = kernel.Application({ configuration = configuration({}, environment) })
    app:boot()
    self:assert_equal(expected, app._resolved.validate_responses, environment)
  end
  local explicit = kernel.Application({ validate_responses = true, configuration = configuration({}, "production") })
  explicit:boot()
  self:assert_equal(true, explicit._resolved.validate_responses)
  local bare = kernel.Application({})
  bare:boot()
  self:assert_equal(false, bare._resolved.validate_responses)
  log.set_default(nil)
end

function T:test_a_booted_application_in_development_refuses_a_nonconforming_response()
  local schema = require("hecate.schema")
  local http = require("hecate.http")
  local module = kernel.routes("v")
  module:get("/v", { responses = { [200] = schema.object({ id = schema.integer() }) }, action = function() return { id = "x" } end })
  local app = kernel.Application({ routes = { module }, configuration = configuration({}, "development") })
  local serve = app:boot()
  self:assert_equal(500, serve(http.Request({ method = "GET", target = "/v", fields = http.Fields() })).status)
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
  local found = record_with(memory, "expose_details_in_production")
  self:assert_not_nil(found)
  -- Documented in website/en/how-to/before-going-to-production.md (Error details): the boot warning is a `warning`.
  self:assert_true(found.severity == log.Severity.warning)
  log.set_default(nil)
end

-- Documented in website/en/how-to/before-going-to-production.md (Error details).
function T:test_expose_details_in_staging_gives_no_boot_warning()
  local memory = log.MemorySink()
  local app = kernel.Application({
    logger = log.Logger({ sinks = { memory }, severity = "debug" }),
    configuration = configuration({ HECATE_ERRORS__EXPOSE_DETAILS = "true" }, "staging"),
  })
  app:boot()
  log.set_default(nil)
  self:assert_equal(true, app._resolved.expose_details) -- the key applies
  self:assert_nil(record_with(memory, "expose_details_in_production"))
end

-- Documented in website/en/how-to/before-going-to-production.md (Error details).
function T:test_expose_details_as_an_option_without_a_configuration_gives_no_boot_warning()
  local memory = log.MemorySink()
  local app = kernel.Application({ expose_details = true, logger = log.Logger({ sinks = { memory }, severity = "debug" }) })
  app:boot()
  self:assert_equal(true, app._resolved.expose_details)
  self:assert_nil(record_with(memory, "expose_details_in_production"))
end

-- Documented in website/en/how-to/before-going-to-production.md (Logging).
function T:test_an_explicit_logger_replaces_the_logger_built_from_the_logging_keys()
  local memory = log.MemorySink()
  local explicit = log.Logger({ sinks = { memory } }) -- no `redact` of its own
  local saved = log.default()
  local app = kernel.Application({
    logger = explicit,
    configuration = configuration({ HECATE_LOGGING__REDACT = "pin", HECATE_LOGGING__SEVERITY = "debug" }),
  })
  app:boot()
  local default_after = log.default()
  log.set_default(nil)
  self:assert_true(rawequal(explicit, app._resolved.logger))
  self:assert_true(rawequal(saved, default_after)) -- the explicit logger is not installed as the default
  -- No `logging.*` key applies to it: neither `logging.severity` nor `logging.redact`.
  self:assert_false(explicit:is_enabled("debug"))
  app._resolved.logger:notice("signed in", { pin = "1234" })
  self:assert_equal("1234", memory:records()[1].fields.pin)
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
  -- Documented in website/en/how-to/before-going-to-production.md (Logging): the signals received are `notice`.
  self:assert_true(record_with(memory, "shutdown_signal").severity == log.Severity.notice)
end

-- Documented in website/en/how-to/before-going-to-production.md (Workers and shutdown).
function T:test_sigint_shuts_the_server_down_gracefully()
  if uv.os_uname().sysname:match("Windows") then return end -- `uv.kill` cannot raise a console signal there
  local guard = uv.new_signal()
  guard:start("sigint", function() end)
  local memory = log.MemorySink()
  local routes = kernel.routes("slow")
  local started, finished, cancelled = false, false, false
  local release = reactor.Channel(1)
  routes:get("/slow", { action = function()
    started = true
    local ok, err = pcall(release.receive, release)
    if not ok then cancelled = true; error(err, 0) end
    finished = true
    return { done = true }
  end })
  local app = kernel.Application({
    logger = log.Logger({ sinks = { memory } }), grace_timeout = 30, routes = { routes },
    server = { host = "127.0.0.1", port = 0 },
  })
  local status
  reactor.run(function()
    local done = false
    reactor.fork(function()
      while not app:local_address() do reactor.sleep(0.005) end
      local port = app:local_address().port
      reactor.fork(function()
        local client = http.Client()
        local ok, response = pcall(client.get, client, "http://127.0.0.1:" .. port .. "/slow")
        status = ok and response.status or response
        -- A response whose content is not read holds its connection: `client:close()` closes only the idle ones, so the
        -- response is closed first (`leaks kernel`).
        if ok then response:close() end
        client:close()
      end)
      while not started do reactor.sleep(0.005) end
      raise_until("sigint", function() return done or codes(memory).shutdown_signal ~= nil end)
      while codes(memory).shutdown_signal == nil do reactor.sleep(0.005) end
      release:send(true) -- the request in flight finishes within the grace period
    end)
    reactor.deadline(10, app.serve, app)
    done = true
  end)
  guard:close()
  local found = codes(memory)
  self:assert_equal("sigint", found.shutdown_signal.signal)
  self:assert_true(record_with(memory, "shutdown_signal").severity == log.Severity.notice)
  self:assert_nil(found.shutdown_forced) -- graceful: drained, not forced
  self:assert_true(finished)
  self:assert_false(cancelled)
  self:assert_equal(200, status)
  self:assert_nil(app:local_address())
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
      reactor.fork(function()
        local client = http.Client()
        pcall(client.get, client, "http://127.0.0.1:" .. port .. "/slow")
        client:close()
      end)
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

--- Waits (at most 10 s) until the application listens.
local function wait_for_address(app)
  reactor.deadline(10, function()
    while app:local_address() == nil do reactor.sleep(0.005) end
  end)
end

function T:test_a_served_writer_uses_open_scoped_services_and_they_close_after_the_response()
  local core = require("hecate.core")
  local net = require("hecate.net")
  local trace = {}
  local Session = core.class("ServedSession")
  function Session:init() self.open = true end
  function Session:__close() self.open = false; trace[#trace + 1] = "closed" end
  core.finalise(Session)
  local module = kernel.routes("stream")
  module:get("/stream", { action = function(request)
    local session = request.services:resolve("session")
    return http.Response(200, { content = function(write)
      trace[#trace + 1] = session.open and "open" or "already closed"
      write("streamed")
    end })
  end })
  local app = kernel.Application({
    signals = false, routes = { module }, logger = log.Logger({ sinks = {} }),
    server = { host = "127.0.0.1", port = 0, on_request_end = function() trace[#trace + 1] = "hook" end },
    services = function(c) c:bind("session", Session, { lifetime = "scoped" }) end,
  })
  local answer
  reactor.run(function()
    reactor.fork(function()
      wait_for_address(app)
      local stream = net.connect("127.0.0.1", app:local_address().port)
      stream:write("GET /stream HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n")
      local parts = {}
      while true do
        local chunk = stream:read()
        if chunk == nil then break end
        parts[#parts + 1] = chunk
      end
      stream:close()
      answer = table.concat(parts)
      reactor.deadline(5, function() while #trace < 3 do reactor.sleep(0.005) end end)
      app:shutdown(1)
    end)
    reactor.deadline(10, app.serve, app)
  end)
  self:assert_not_nil(answer:find("streamed", 1, true), answer)
  self:assert_equal("open,closed,hook", table.concat(trace, ","), "the hook of the server option runs after the close")
end

function T:test_signals_false_serves_until_shutdown()
  local app = kernel.Application({ signals = false, server = { host = "127.0.0.1", port = 0 } })
  reactor.run(function()
    reactor.fork(function() wait_for_address(app); app:shutdown(1) end)
    reactor.deadline(5, app.serve, app)
  end)
  self:assert_nil(app._server)
  self:assert_nil(app:local_address())
end

--- Serves `options` until it listens, then shuts it down; returns the argument lists `reactor.watch_signals` was called with.
local function signal_watchers_installed(options)
  local original = reactor.watch_signals
  local calls = {}
  reactor.watch_signals = function(...)
    calls[#calls + 1] = { ... }
    return original(...)
  end
  local app = kernel.Application(options)
  local ok, err = pcall(reactor.run, function()
    reactor.fork(function() wait_for_address(app); app:shutdown(1) end)
    reactor.deadline(5, app.serve, app)
  end)
  reactor.watch_signals = original
  if not ok then error(err, 0) end
  return calls
end

-- Documented in website/en/how-to/before-going-to-production.md (Workers and shutdown).
function T:test_signals_false_installs_no_signal_watcher()
  local logger = log.Logger({ sinks = {} })
  local server = { host = "127.0.0.1", port = 0 }
  -- The spy sees the watcher of the default handling: `sigint` and `sigterm` (and `sighup` outside Windows).
  local watched = signal_watchers_installed({ logger = logger, server = server })
  self:assert_equal(1, #watched)
  local names = table.concat(watched[1], ",")
  self:assert_true(names:find("sigint", 1, true) ~= nil, names)
  self:assert_true(names:find("sigterm", 1, true) ~= nil, names)
  self:assert_equal(0, #signal_watchers_installed({ signals = false, logger = logger, server = { host = "127.0.0.1", port = 0 } }))
end

function T:test_invalid_signal_options_are_refused()
  for _, value in ipairs({ {}, { "sigint" }, { "sigusr2" }, "sigterm", 15 }) do
    local ok, err = pcall(kernel.Application, { signals = value })
    self:assert_false(ok)
    self:assert_true(require("hecate.core").is_instance_of(err, require("hecate.core").ArgumentError))
    self:assert_true(tostring(err):find("true (default handling) or false (off)", 1, true) ~= nil)
  end
  self:assert_true(pcall(kernel.Application, { signals = true }))
  self:assert_true(pcall(kernel.Application, { signals = false }))
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

-- Multi-process serving (ADR 0023): options, configuration keys, the command of a worker, the primary --------------------

function T:test_workers_and_strategy_are_validated()
  local core = require("hecate.core")
  local function refused(options)
    local ok, err = pcall(kernel.Application, options)
    self:assert_false(ok)
    self:assert_true(core.is_instance_of(err, core.ArgumentError))
  end
  refused({ workers = 0 })
  refused({ workers = -1 })
  refused({ workers = 1.5 })
  refused({ workers = "2" })
  refused({ strategy = "fork" })
  refused({ strategy = 1 })
  refused({ worker_command = "lua main.lua" })
  refused({ worker_command = {} })
  refused({ worker_command = { "lua", 1 } })
  refused({ on_crash_loop = "restart" })
  refused({ on_crash_loop = true })
  for _, bad in ipairs({ -1, 0 / 0, math.huge, "30", true }) do refused({ ready_timeout = bad }) end
  self:assert_true(pcall(kernel.Application, { ready_timeout = 5 }))
  self:assert_true(pcall(kernel.Application, { on_crash_loop = "degrade" }))
  self:assert_true(pcall(kernel.Application, { on_crash_loop = "stop" }))
  self:assert_true(pcall(kernel.Application, { workers = 4, strategy = "round_robin", worker_command = { "lua", "main.lua" } }))
end

function T:test_workers_and_strategy_default_to_one_process_and_auto()
  local app = kernel.Application({})
  app:boot()
  self:assert_equal(1, app._resolved.workers)
  self:assert_equal("auto", app._resolved.strategy)
end

function T:test_configuration_binds_workers_and_strategy_and_options_win()
  local env = { HECATE_SERVER__WORKERS = "3", HECATE_SERVER__STRATEGY = "round_robin" }
  local app = kernel.Application({ configuration = configuration(env) })
  app:boot()
  self:assert_equal(3, app._resolved.workers)
  self:assert_equal("round_robin", app._resolved.strategy)
  local explicit = kernel.Application({ configuration = configuration(env), workers = 1, strategy = "reuseport" })
  explicit:boot()
  self:assert_equal(1, explicit._resolved.workers)
  self:assert_equal("reuseport", explicit._resolved.strategy)
end

function T:test_the_worker_command_restarts_the_running_program()
  local from = kernel.Application.worker_command_from
  -- An empty search path keeps the interpreter name as it is.
  self:assert_equal("lua,main.lua,--port,80", table.concat(from({ [-1] = "lua", [0] = "main.lua", "--port", "80" }, ""), ","))
  self:assert_equal("lua,-W,main.lua", table.concat(from({ [-2] = "lua", [-1] = "-W", [0] = "main.lua" }, ""), ","))
  self:assert_false(pcall(from, { [-1] = "lua" })) -- no main program (interactive, -e): the caller gives worker_command
  self:assert_false(pcall(from, {}))
end

function T:test_a_bare_interpreter_name_is_resolved_through_the_search_path()
  local from = kernel.Application.worker_command_from
  local file = os.tmpname()
  local directory, name = file:match("^(.*)[/\\]([^/\\]+)$")
  if directory == nil or directory == "" then os.remove(file) return end
  -- On Windows `os.tmpname` only returns a name: the file has to be created.
  local created = assert(io.open(file, "wb"))
  created:close()
  local arguments = { [-1] = name, [0] = "main.lua" }
  local found = from(arguments, "/no/such/directory" .. (package.config:sub(1, 1) == "\\" and ";" or ":") .. directory)
  local missing = from({ [-1] = name .. "-absent", [0] = "main.lua" }, directory)
  local separator_kept = from({ [-1] = "./" .. name, [0] = "main.lua" }, directory)
  os.remove(file)
  self:assert_equal(directory .. "/" .. name, found[1])
  self:assert_equal("main.lua", found[2])
  self:assert_equal(name .. "-absent", missing[1]) -- not found: kept
  self:assert_equal("./" .. name, separator_kept[1]) -- already a path: untouched
end

function T:test_a_single_process_has_no_supervisor()
  local app = kernel.Application({ signals = false, server = { host = "127.0.0.1", port = 0 }, worker_command = { "no-such-program" } })
  reactor.run(function()
    reactor.fork(function() wait_for_address(app); app:shutdown(1) end)
    reactor.deadline(5, app.serve, app)
  end)
  self:assert_nil(app._supervisor)
end

function T:test_the_primary_runs_a_supervisor_instead_of_a_server()
  local core = require("hecate.core")
  local memory = log.MemorySink()
  local app = kernel.Application({
    workers = 2, strategy = "round_robin", signals = false, logger = log.Logger({ sinks = { memory } }),
    server = { host = "127.0.0.1", port = 0 }, worker_command = { "hecate-no-such-program" },
  })
  local ok, err
  reactor.run(function() ok, err = pcall(reactor.deadline, 10, app.serve, app) end)
  self:assert_false(ok)
  self:assert_true(core.is_instance_of(err, kernel.SupervisorError))
  self:assert_equal("start_failed", err.context.reason)
  self:assert_nil(app._server)
  self:assert_nil(app:local_address())
  self:assert_equal(2, codes(memory).workers_starting.workers)
  -- Documented in website/en/how-to/before-going-to-production.md (Logging): the workers started are `notice`.
  self:assert_true(record_with(memory, "workers_starting").severity == log.Severity.notice)
end

function T:test_bad_server_options_fail_the_primary_once_before_any_worker_starts()
  local core = require("hecate.core")
  local memory = log.MemorySink()
  local app = kernel.Application({
    workers = 2, strategy = "round_robin", signals = false, logger = log.Logger({ sinks = { memory } }),
    server = { host = "127.0.0.1", port = 0, max_connections = -1 }, worker_command = { "hecate-no-such-program" },
  })
  local ok, err
  reactor.run(function() ok, err = pcall(reactor.deadline, 10, app.serve, app) end)
  self:assert_false(ok)
  self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
  self:assert_nil(app._served, "a serve that fails before the run does not count")
  self:assert_nil(app._supervisor)
  self:assert_nil(codes(memory).workers_starting, "no worker was started")
end

function T:test_a_worker_gets_the_logger_of_the_application()
  local core = require("hecate.core")
  local logger = log.Logger({ sinks = {} })
  local app = kernel.Application({ signals = false, logger = logger, server = { host = "127.0.0.1", port = 0 } })
  local real, given = kernel.supervisor.worker_role, nil
  kernel.supervisor.worker_role = function(options)
    given = options
    error(core.ArgumentError("stop here"))
  end
  local ok = pcall(function() reactor.run(function() app:serve() end) end)
  kernel.supervisor.worker_role = real
  self:assert_false(ok)
  self:assert_true(given ~= nil and given.logger == logger, "worker_role receives the application's logger")
end

function T:test_the_primary_logs_through_the_default_logger_without_a_logger_option()
  local memory = log.MemorySink()
  local saved = log.default()
  log.set_default(log.Logger({ sinks = { memory } }))
  local app = kernel.Application({
    workers = 2, strategy = "round_robin", signals = false,
    server = { host = "127.0.0.1", port = 0 }, worker_command = { "hecate-no-such-program" },
  })
  local ok
  reactor.run(function() ok = pcall(reactor.deadline, 10, app.serve, app) end)
  log.set_default(saved)
  self:assert_false(ok) -- no worker program
  self:assert_equal(2, codes(memory).workers_starting.workers)
end

function T:test_load_configuration_refuses_a_non_table()
  self:assert_false(pcall(kernel.load_configuration, "config"))
end

-- Boot rejections, before any request ------------------------------------------------------------------------------------

--- Boots `options` and returns the error it raises; asserts that the application stays unbooted.
local function boot_failure(case, options)
  local app = kernel.Application(options)
  local err = case:assert_error(function() app:boot() end)
  case:assert_true(require("hecate.core").is_instance_of(err, kernel.RouteDeclarationError), tostring(err))
  case:assert_nil(app.router)
  case:assert_nil(app.container)
  case:assert_nil(app._serve)
  case:assert_false(app._booted)
  return err, app
end

local function controller_with(declaration)
  local core = require("hecate.core")
  local Controller = core.class("BootController", kernel.Controller)
  Controller.routes = { declaration }
  core.finalise(Controller)
  return Controller
end

function T:test_boot_rejects_a_route_that_names_a_missing_action()
  local err = boot_failure(self, { routes = { controller_with({ method = "GET", path = "/x", action = "nothing" }) } })
  self:assert_equal("missing_action", err.context.reason)
  self:assert_equal("hecate.kernel.RouteDeclarationError.missing_action", err.code)
  self:assert_equal("controller BootController", err.context.origin)
  -- The same through a feature module, which gathers its routes at boot too.
  local through_module = boot_failure(self, { modules = { { name = "m", routes = { controller_with({ method = "GET", path = "/x", action = "nothing" }) } } } })
  self:assert_equal("missing_action", through_module.context.reason)
end

function T:test_boot_rejects_a_controller_dependency_that_names_no_binding()
  local core = require("hecate.core")
  local Hello = core.class("BootTypoController", kernel.Controller)
  Hello.dependencies = { repository = "users.UserRepositry" }
  kernel.Controller.route(Hello, { method = "GET", path = "/h", action = "say" })
  function Hello:say() return nil end
  core.finalise(Hello)
  local app = kernel.Application({
    routes = { Hello }, logger = log.Logger({ sinks = {} }),
    services = function(c) c:bind("users.UserRepository", core.finalise(core.class("UserRepository")), { lifetime = "scoped" }) end,
  })
  local err = self:assert_error(function() app:boot() end)
  self:assert_equal("unknown_dependency", err.context.reason)
  self:assert_nil(app.router, "the boot failed: nothing is served")
end

function T:test_boot_rejects_a_malformed_route_schema()
  local err = boot_failure(self, { routes = { controller_with({ method = "GET", path = "/x", action = "a", responses = { [200] = {} } }) } })
  self:assert_equal("invalid_responses", err.context.reason)
  self:assert_equal("hecate.kernel.RouteDeclarationError.invalid_responses", err.code)
  local parameters = boot_failure(self, { routes = { controller_with({
    method = "GET", path = "/x", action = "a", parameters = { query = { q = "string" } } }) } })
  self:assert_equal("invalid_parameters", parameters.context.reason)
  local content = boot_failure(self, { routes = { controller_with({
    method = "POST", path = "/x", action = "a", content = { ["application/json"] = 1 } }) } })
  self:assert_equal("invalid_content", content.context.reason)
end

function T:test_boot_rejects_content_declared_for_an_unsupported_media_type()
  local schema = require("hecate.schema")
  local module = kernel.routes("xml")
  module:post("/x", { action = function() return nil end, content = { ["application/xml"] = schema.any() } })
  local err = boot_failure(self, { routes = { module } })
  self:assert_equal("unsupported_content_type", err.context.reason)
  self:assert_equal("hecate.kernel.RouteDeclarationError.unsupported_content_type", err.code)
  self:assert_equal("route module xml", err.context.origin)
  self:assert_equal("content", err.context.field)
end

function T:test_serve_fails_at_boot_before_it_listens_or_answers_anything()
  local core = require("hecate.core")
  local app = kernel.Application({
    signals = false, server = { host = "127.0.0.1", port = 0 },
    routes = { controller_with({ method = "GET", path = "/x", action = "nothing" }) },
  })
  local err
  reactor.run(function()
    local ok, failure = pcall(reactor.deadline, 5, app.serve, app)
    err = not ok and failure or nil
  end)
  self:assert_true(core.is_instance_of(err, kernel.RouteDeclarationError), tostring(err))
  self:assert_equal("missing_action", err.context.reason)
  self:assert_nil(app:local_address()) -- nothing was bound
  self:assert_nil(app._server)
  self:assert_nil(app._served) -- a serve whose boot failed does not count
end

-- Errors of an action are not exposed ------------------------------------------------------------------------------------

local function failing_application(options)
  local module = kernel.routes("boom")
  module:get("/boom", { action = function() error("secret") end })
  options = options or {}
  options.routes = { module }
  return kernel.Application(options)
end

function T:test_a_plain_error_of_an_action_is_not_exposed_by_default()
  local json = require("hecate.json")
  local memory = log.MemorySink()
  local serve = failing_application({ logger = log.Logger({ sinks = { memory } }) }):boot()
  local response = get(serve, "/boom")
  self:assert_equal(500, response.status)
  self:assert_equal("application/problem+json", response.fields:get("Content-Type"))
  local body = json.decode(response.content)
  self:assert_equal(500, body.status)
  self:assert_nil(body.debug)
  for _, leak in ipairs({ "secret", "traceback", "stack", ".lua", "error(" }) do
    self:assert_nil(response.content:find(leak, 1, true), "the body leaks " .. leak)
  end
  -- The failure is in the log, with its traceback, and nowhere else.
  local record = memory:records()[1]
  self:assert_not_nil(record)
  self:assert_true(record.fields.error:find("secret", 1, true) ~= nil)
  self:assert_true(record.fields.traceback:find("stack traceback", 1, true) ~= nil)
end

function T:test_a_plain_error_of_an_action_carries_the_debug_member_when_details_are_exposed()
  local json = require("hecate.json")
  local serve = failing_application({ expose_details = true, logger = log.Logger({ sinks = {} }) }):boot()
  local response = get(serve, "/boom")
  self:assert_equal(500, response.status)
  local body = json.decode(response.content)
  self:assert_equal("table", type(body.debug))
  self:assert_equal("string", body.debug.error)
  self:assert_true(body.debug.message:find("secret", 1, true) ~= nil)
end

function T:test_the_exposure_of_details_follows_the_configuration_unless_overridden()
  local json = require("hecate.json")
  local function body_of(options)
    options.logger = log.Logger({ sinks = {} })
    return json.decode(get(failing_application(options):boot(), "/boom").content)
  end
  self:assert_nil(body_of({ configuration = configuration({}) }).debug)
  self:assert_not_nil(body_of({ configuration = configuration({ HECATE_ERRORS__EXPOSE_DETAILS = "true" }) }).debug)
  self:assert_nil(body_of({ expose_details = false, configuration = configuration({ HECATE_ERRORS__EXPOSE_DETAILS = "true" }) }).debug)
  log.set_default(nil)
end

-- Documented in website/en/how-to/before-going-to-production.md (Logging).
function T:test_an_unhandled_error_is_logged_at_error_without_the_query()
  local memory = log.MemorySink()
  -- `lax`: in `strict` mode the undeclared query parameter is refused (422) before the action runs.
  local serve = failing_application({ inputs = "lax", logger = log.Logger({ sinks = { memory } }) }):boot()
  self:assert_equal(500, get(serve, "/boom?access_token=abc123").status)
  local records = memory:records()
  self:assert_equal(1, #records)
  local record = records[1]
  self:assert_true(record.severity == log.Severity.error)
  self:assert_equal("unhandled error while serving a request", record.message)
  self:assert_equal("GET", record.fields.method)
  self:assert_equal("/boom", record.fields.path)
  self:assert_equal("string", record.fields.error_class) -- a plain Lua error: its type
  self:assert_true(record.fields.error:find("secret", 1, true) ~= nil)
  self:assert_true(record.fields.traceback:find("stack traceback", 1, true) ~= nil)
  for name, value in pairs(record.fields) do
    self:assert_nil(tostring(value):find("abc123", 1, true), "the query leaks into " .. name)
  end
end

-- Documented in website/en/how-to/before-going-to-production.md (Logging).
function T:test_a_problem_below_500_that_an_action_returns_or_raises_is_not_logged()
  local problem = kernel.problem
  local module = kernel.routes("problems")
  module:get("/returned", { action = function() return problem.NotFound({ detail = "no such order" }) end })
  module:get("/conflict", { action = function() return problem.Conflict() end })
  module:get("/raised", { action = function() error(problem.Forbidden()) end })
  local memory = log.MemorySink()
  local serve = kernel.Application({
    routes = { module }, logger = log.Logger({ sinks = { memory }, severity = "debug" }),
  }):boot()
  self:assert_equal(404, get(serve, "/returned").status)
  self:assert_equal(409, get(serve, "/conflict").status)
  self:assert_equal(403, get(serve, "/raised").status)
  self:assert_equal(0, #memory:records())
end

-- Documented in website/en/how-to/before-going-to-production.md (Logging; Listening and limits).
function T:test_an_expired_deadline_gives_a_500_and_the_server_record_without_traceback()
  local memory = log.MemorySink()
  local module = kernel.routes("late")
  module:get("/late", { action = function()
    reactor.deadline(0.01, reactor.sleep, 5) -- not caught by the action
    return { never = true }
  end })
  local app = kernel.Application({
    routes = { module }, signals = false, logger = log.Logger({ sinks = { memory } }), inputs = "lax",
    server = { host = "127.0.0.1", port = 0 },
  })
  local status, problem_type
  reactor.run(function()
    reactor.fork(function()
      wait_for_address(app)
      local port = app:local_address().port
      local client = http.Client()
      local ok, response = pcall(client.get, client, "http://127.0.0.1:" .. port .. "/late?access_token=abc123")
      if ok then
        status, problem_type = response.status, response.fields:get("Content-Type")
        response:close() -- its unread content holds the connection; `client:close()` closes only idle ones (`leaks kernel`)
      end
      client:close()
      app:shutdown(1)
    end)
    reactor.deadline(10, app.serve, app)
  end)
  self:assert_equal(500, status)
  self:assert_equal("application/problem+json", problem_type)
  -- Beside the `listening` record (`informational`), one record only: the guard of the kernel logged nothing.
  local records = {}
  for _, candidate in ipairs(memory:records()) do
    if candidate.severity ~= log.Severity.informational then records[#records + 1] = candidate end
  end
  self:assert_equal(1, #records)
  local record = records[1]
  self:assert_true(record.severity == log.Severity.error)
  self:assert_equal("http.Server: the action failed", record.message)
  self:assert_equal("GET", record.fields.method)
  self:assert_equal("/late", record.fields.path)
  self:assert_true(record.fields.error:find("deadline", 1, true) ~= nil, record.fields.error)
  self:assert_nil(record.fields.traceback)
  for name, value in pairs(record.fields) do
    self:assert_nil(tostring(value):find("abc123", 1, true), "the query leaks into " .. name)
  end
end

-- A filter and a streaming response --------------------------------------------------------------------------------------

function T:test_every_layer_of_filters_sees_a_streaming_response_unchanged()
  local schema = require("hecate.schema")
  local chunks_written = 0
  local function writer(write)
    chunks_written = chunks_written + 1
    write("chunk one, ")
    write("chunk two")
  end
  local produced = http.Response(200, { content = writer })
  local seen = {}
  local function observer(name)
    return { handle = function(_, request, next)
      local response = next(request)
      seen[#seen + 1] = {
        name = name, same = rawequal(response, produced), function_content = type(response.content) == "function",
        same_writer = response.content == writer, written = chunks_written,
      }
      return response
    end }
  end
  local module = kernel.routes("stream")
  module:get("/stream", {
    action = function() return produced end, responses = { [200] = schema.string() }, filters = { observer("route") },
  })
  local app = kernel.Application({
    filters = { observer("global") }, validate_responses = true,
    modules = { { name = "m", routes = { module }, filters = { observer("module") } } },
  })
  local response = get(app:boot(), "/stream")
  self:assert_equal(3, #seen)
  for _, entry in ipairs(seen) do
    self:assert_true(entry.same, entry.name .. ": the filter got another response")
    self:assert_true(entry.function_content, entry.name .. ": the content is no longer a writer")
    self:assert_true(entry.same_writer, entry.name)
    self:assert_equal(0, entry.written, entry.name .. ": the writer ran before the server consumed it")
  end
  self:assert_equal("route,module,global", seen[1].name .. "," .. seen[2].name .. "," .. seen[3].name)
  self:assert_true(rawequal(response, produced), "the application returned another response")
  -- The server runs the writer: it still produces the content, once.
  local parts = {}
  response.content(function(data) parts[#parts + 1] = data end, function() end)
  self:assert_equal("chunk one, chunk two", table.concat(parts))
  self:assert_equal(1, chunks_written)
end

function T:test_a_filter_may_add_a_field_to_a_streaming_response_and_it_keeps_streaming()
  local function writer(write) write("x") end
  local module = kernel.routes("stream")
  module:get("/s", { action = function() return http.Response(200, { content = writer }) end })
  local app = kernel.Application({
    routes = { module },
    filters = { { handle = function(_, request, next)
      local response = next(request)
      response.fields:set("X-Seen", "yes")
      return response
    end } },
  })
  local response = get(app:boot(), "/s")
  self:assert_equal("yes", response.fields:get("X-Seen"))
  self:assert_true(response.content == writer)
end

return T
