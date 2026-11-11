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
  self:assert_false(pcall(from, { [-1] = "lua" })) -- no script (interactive, -e): the caller gives worker_command
  self:assert_false(pcall(from, {}))
end

function T:test_a_bare_interpreter_name_is_resolved_through_the_search_path()
  local from = kernel.Application.worker_command_from
  local file = os.tmpname()
  local directory, name = file:match("^(.*)[/\\]([^/\\]+)$")
  if directory == nil or directory == "" then os.remove(file) return end
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
    reactor.fork(function() reactor.sleep(0.01); app:shutdown(1) end)
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

return T
