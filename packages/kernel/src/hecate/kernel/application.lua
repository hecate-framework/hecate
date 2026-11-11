-- The application: the composition root (http-and-routing.md, "Application and feature modules"). `boot` decides
-- everything that can be decided before the first request (module order, container graph, route table, filter chains);
-- `serve` binds a server on the result.
global <const> require, type, error, ipairs, pairs, tostring, pcall, table, math, arg

local core = require("hecate.core")
local json = require("hecate.json")
local http = require("hecate.http")
local container_package = require("hecate.container")
local modules = require("hecate.kernel.modules")
local routing = require("hecate.kernel.routing")
local dispatcher = require("hecate.kernel.dispatcher")
local errors = require("hecate.kernel.errors")
local logging = require("hecate.kernel.logging")
local log = require("hecate.log")
local reactor = require("hecate.reactor")
local listening = require("hecate.kernel.listening")
local supervisor = require("hecate.kernel.supervisor")

--- The fixed set of signals that stop `serve` (concurrency.md, "Signals and shutdown"; OQ-115). On Windows libuv
--- delivers `sigint` for Ctrl+C; `sigterm` is accepted there and never delivered.
local SIGNALS <const> = { "sigint", "sigterm" }

--- Options of `Application`.
---@class hecate.kernel.ApplicationOptions
---@field modules? hecate.kernel.FeatureModule[]  the feature modules
---@field routes? (hecate.kernel.RouteModule|table)[]  route modules and controllers that belong to no feature
---@field services? fun(container: hecate.container.Container)  binds services of the application itself, before those of the modules
---@field filters? hecate.kernel.Filter[]  global filters, outermost, before those of the modules
---@field container? hecate.container.Container  an existing container (not yet validated); default: a new one
---@field configuration? hecate.config.Configuration  binds `limits.max_depth`, `errors.expose_details`, `requests.inputs`, `server.grace_timeout`, `server.workers`, `server.strategy` and the logging keys; the options below override it
---@field max_depth? integer  nesting depth limit of `json` and `schema` (`json.set_max_depth`, OQ-92)
---@field expose_details? boolean  see `hecate.kernel.DispatcherOptions`
---@field inputs? "lax"|"strict"  see `hecate.kernel.DispatcherOptions`
---@field logger? hecate.log.Logger  receives unhandled failures and the container warnings
---@field router? hecate.router.RouterOptions
---@field server? hecate.http.ServerOptions  options of the HTTP server made by `serve` (`logger` defaults to the application's)
---@field signals? false  `false` disables signal handling (tests, embedding); the set (`sigint`, `sigterm`) is fixed and cannot be listed
---@field grace_timeout? number  seconds a signal-driven shutdown lets requests in flight finish (default 30)
---@field workers? integer  number of worker processes, at least 1 (default 1: the process serves by itself); above 1 the primary runs a `hecate.kernel.Supervisor` (ADR 0023)
---@field strategy? "auto"|"reuseport"|"round_robin"  how connections reach the workers (default `auto`, `listening.select`); used only when `workers` is above 1
---@field worker_command? string[]  the program and arguments that start a worker (default: the running interpreter, script and arguments, `Application.worker_command_from(arg)`)

--- The composition root.
---@class hecate.kernel.Application
---@field container hecate.container.Container?  the validated container, after `boot`
---@field router hecate.router.Router?  the router, after `boot`
---@field _supervisor hecate.kernel.Supervisor?  the supervisor, while serving as the primary of several workers
---@field _signalled boolean?  set by the signal watcher once it started `shutdown`
---@overload fun(options?: hecate.kernel.ApplicationOptions): hecate.kernel.Application
local Application = core.class("Application")

local KNOWN = {
  modules = true, routes = true, configuration = true, services = true, filters = true, container = true, max_depth = true,
  expose_details = true, inputs = true, logger = true, router = true, server = true, signals = true, grace_timeout = true,
  workers = true, strategy = true, worker_command = true,
}

local STRATEGIES <const> = { auto = true, reuseport = true, round_robin = true }

--- Creates an application; nothing is checked or built until `boot`.
---
--- Raises `hecate.core.ArgumentError` for an unknown option.
---@param options? hecate.kernel.ApplicationOptions
function Application:init(options)
  options = options or {}
  if type(options) ~= "table" then error(core.ArgumentError("kernel.Application: options is a table"), 2) end
  for key in pairs(options) do
    if not KNOWN[key] then error(core.ArgumentError(("kernel.Application: unknown option %q"):format(tostring(key))), 2) end
  end
  if options.signals ~= nil and options.signals ~= false then
    error(core.ArgumentError("kernel.Application: the signal set is fixed (sigint, sigterm); signals = false disables signal handling"), 2)
  end
  local grace = options.grace_timeout
  if grace ~= nil and (type(grace) ~= "number" or grace ~= grace or grace < 0 or grace == math.huge) then
    error(core.ArgumentError("kernel.Application: grace_timeout is a non-negative finite number of seconds"), 2)
  end
  if options.workers ~= nil and (math.type(options.workers) ~= "integer" or options.workers < 1) then
    error(core.ArgumentError("kernel.Application: workers is an integer of at least 1"), 2)
  end
  if options.strategy ~= nil and not STRATEGIES[options.strategy] then
    error(core.ArgumentError("kernel.Application: strategy is auto, reuseport or round_robin"), 2)
  end
  local command = options.worker_command
  if command ~= nil then
    local valid = type(command) == "table" and type(command[1]) == "string"
    for i = 1, valid and #command or 0 do if type(command[i]) ~= "string" then valid = false end end
    if not valid then error(core.ArgumentError("kernel.Application: worker_command is a list of strings, the program first"), 2) end
  end
  self._options = options
  self._booted = false
end

--- The command that starts the running program again, from the `arg` table of the standalone interpreter: the
--- interpreter and its options (the negative indices), the script (index 0) and the script arguments. A worker is that
--- program started with the worker role in its environment (ADR 0023, Decision 1).
---
--- Raises `hecate.core.ArgumentError` when there is no script (interactive use, `-e`, embedding): give `worker_command`.
---@param arguments? table  default the global `arg`
---@return string[] command
function Application.worker_command_from(arguments)
  arguments = arguments or arg
  local lowest = 0
  if type(arguments) == "table" then
    for index in pairs(arguments) do
      if math.type(index) == "integer" and index < lowest then lowest = index end
    end
  end
  if type(arguments) ~= "table" or lowest == 0 or type(arguments[0]) ~= "string" then
    error(core.ArgumentError("kernel.Application: cannot tell how to start a worker (no script in `arg`); give the worker_command option"), 2)
  end
  local command = {}
  for index = lowest, #arguments do
    local part = arguments[index]
    if type(part) ~= "string" then
      error(core.ArgumentError("kernel.Application: cannot tell how to start a worker (`arg` has a gap); give the worker_command option"), 2)
    end
    command[#command + 1] = part
  end
  return command
end

--- Boots the application: applies `max_depth`, orders the modules (rejecting duplicates, missing dependencies and
--- cycles), binds the services (application first, then each module in order), validates the container graph, gathers
--- the route table and builds the function that serves a request. Container warnings go to the logger. Idempotent
--- failure: a failed boot leaves nothing half-built (call again on a new application).
---
--- Raises `hecate.kernel.ModuleError` (including `already_booted`), `hecate.container.GraphError`,
--- `hecate.kernel.RouteDeclarationError`, the errors of `hecate.router.Router` and `hecate.core.ArgumentError`.
---@return fun(request: hecate.http.Request): hecate.http.Response serve  runs one request
function Application:boot()
  if self._booted then
    error(errors.ModuleError("kernel: the application is already booted", { context = { reason = "already_booted" } }), 2)
  end
  local options = {}
  for key, value in pairs(self._options) do options[key] = value end
  local configuration = options.configuration
  if configuration ~= nil then
    if options.max_depth == nil then options.max_depth = configuration:get("limits.max_depth") end
    if options.expose_details == nil then options.expose_details = configuration:get("errors.expose_details") end
    if options.inputs == nil then options.inputs = configuration:get("requests.inputs") end
    if options.grace_timeout == nil then options.grace_timeout = configuration:get("server.grace_timeout") end
    if options.workers == nil then options.workers = configuration:get("server.workers") end
    if options.strategy == nil then options.strategy = configuration:get("server.strategy") end
    if options.logger == nil then
      options.logger = logging.build(configuration)
      log.set_default(options.logger)
    end
    if options.expose_details and configuration:environment() == "production" then
      options.logger:warning("errors.expose_details is true in the production environment: internal details reach clients",
        { code = "expose_details_in_production" })
    end
  end
  if options.workers == nil then options.workers = 1 end
  if options.strategy == nil then options.strategy = "auto" end
  self._resolved = options
  if options.max_depth ~= nil then json.set_max_depth(options.max_depth) end
  local ordered = modules.order(options.modules or {})
  local container = options.container or container_package.Container()
  if options.services then options.services(container) end
  local sources, filters = {}, {}
  for _, source in ipairs(options.routes or {}) do sources[#sources + 1] = source end
  for _, filter in ipairs(options.filters or {}) do filters[#filters + 1] = filter end
  for _, module in ipairs(ordered) do
    if module.services then module.services(container) end
    for _, source in ipairs(module.routes or {}) do sources[#sources + 1] = source end
    for _, filter in ipairs(module.filters or {}) do filters[#filters + 1] = filter end
  end
  local _, warnings = container:validate()
  local logger = options.logger
  if logger ~= nil then
    for _, warning in ipairs(warnings) do
      logger:log("warning", "container: " .. tostring(warning.message), { code = warning.code })
    end
  end
  local entries = routing.collect(sources)
  local serve, router = dispatcher.build(entries, {
    filters = filters, container = container, router = options.router, expose_details = options.expose_details,
    logger = logger, inputs = options.inputs,
  })
  self.container, self.router, self._serve, self._booted = container, router, serve, true
  return serve
end

--- Waits for `sigint` or `sigterm`, then shuts the application down gracefully. While that shutdown drains, a second
--- signal forces the stop: the requests still in flight are cancelled at once (`Server:shutdown(0)`, OQ-115). A signal
--- the platform cannot watch is logged once and the application serves without signal handling.
---@async
---@param self hecate.kernel.Application
---@param watcher hecate.reactor.SignalWatcher
---@param logger? hecate.log.Logger
local function watch_signals(self, watcher, logger)
  local ok, name = pcall(watcher.wait, watcher)
  if not ok then
    if core.is_instance_of(name, core.CancellationError) then error(name, 0) end
    return
  end
  self._signalled = true
  if logger ~= nil then
    logger:notice("kernel.Application: signal received, shutting down gracefully",
      { code = "shutdown_signal", signal = name })
  end
  -- The drain runs in this scope's body; the child waits for the second signal and ends with the scope (ADR 0003).
  reactor.scope(function(scope)
    local forcer = scope:fork(function()
      local second_ok, second = pcall(watcher.wait, watcher)
      if not second_ok then
        if core.is_instance_of(second, core.CancellationError) then error(second, 0) end
        return
      end
      if logger ~= nil then
        logger:warning("kernel.Application: second signal received, stopping now", { code = "shutdown_forced", signal = second })
      end
      -- The primary cannot wait for the workers' own drain any more: it kills them (`Supervisor:force`).
      if self._supervisor ~= nil then self._supervisor:force() else self:shutdown(0) end
    end)
    self:shutdown((self._resolved or self._options).grace_timeout)
    forcer:cancel()
  end)
end

--- In a worker the signals of the terminal (Ctrl+C reaches the whole process group) must not end the process before
--- its drain: the primary decides, and sends `stop` (ADR 0023, Decision 5). The worker therefore swallows them.
---@async
---@param self hecate.kernel.Application
---@param watcher hecate.reactor.SignalWatcher
---@param logger? hecate.log.Logger
local function swallow_signals(self, watcher, logger)
  while true do
    local ok, name = pcall(watcher.wait, watcher)
    if not ok then
      if core.is_instance_of(name, core.CancellationError) then error(name, 0) end
      return
    end
    if logger ~= nil then
      logger:debug("kernel.Application: worker ignores a signal; the primary stops it", { code = "worker_signal_ignored", signal = name })
    end
  end
end

--- Runs `body` with `watch` (the signal handling) beside it, unless `signals = false`; closes the container afterwards.
---@async
---@param self hecate.kernel.Application
---@param watch async fun(self: hecate.kernel.Application, watcher: hecate.reactor.SignalWatcher, logger?: hecate.log.Logger)
---@param body async fun()
local function run_watched(self, watch, body)
  local logger = self._resolved.logger
  local ok, err = pcall(reactor.scope, function(scope)
    local task, watcher
    -- One persistent watcher for the whole run: a signal delivered between two waits is queued, never lost (a worker
    -- would take the default action and die). It is closed once the body has ended, after the task is cancelled.
    if self._options.signals ~= false then
      local created, handle = pcall(reactor.watch_signals, table.unpack(SIGNALS))
      if created then
        watcher = handle
        task = scope:fork(watch, self, handle, logger or log.default())
      elseif logger ~= nil then
        logger:warning("kernel.Application: signals cannot be watched; serving without graceful shutdown on signals",
          { code = "signals_unavailable" })
      end
    end
    local body_ok, body_err = pcall(body)
    -- A watcher that received its signal is inside `shutdown` and ends by itself.
    if task ~= nil and not self._signalled then task:cancel() end
    if watcher ~= nil then watcher:close() end
    if not body_ok then error(body_err, 0) end
  end)
  self._server, self._supervisor = nil, nil
  self.container:close()
  if not ok then error(err, 0) end
end

--- The options of the HTTP server of this process.
---@param self hecate.kernel.Application
---@return hecate.http.ServerOptions
local function server_options_of(self)
  local server_options = {}
  for key, value in pairs(self._options.server or {}) do server_options[key] = value end
  if server_options.logger == nil then server_options.logger = self._resolved.logger end
  return server_options
end

--- Serves as the primary of several workers: runs a `Supervisor` on the endpoint of the `server` option.
---@async
---@param self hecate.kernel.Application
local function serve_as_primary(self)
  -- Like the signal watcher and `http.Server`, the primary falls back to the default logger (OQ-79).
  local resolved, logger = self._resolved, self._resolved.logger or log.default()
  local server_options = self._options.server or {}
  local defaults = http.Server.DEFAULTS
  local endpoint = {
    host = server_options.host or defaults.host, port = server_options.port or defaults.port,
    backlog = server_options.backlog,
  }
  local strategy, fallback = listening.select(resolved.strategy, { logger = logger })
  local command = resolved.worker_command or Application.worker_command_from()
  local sup = supervisor.Supervisor({
    command = command, count = resolved.workers, endpoint = endpoint, strategy = strategy, logger = logger,
  })
  self._supervisor = sup
  if fallback ~= nil then logger:warning("kernel.Application: " .. fallback, { code = "strategy_fallback" }) end
  logger:notice(("kernel.Application: starting %d workers (strategy %s)"):format(resolved.workers, strategy.name),
    { code = "workers_starting", workers = resolved.workers, strategy = strategy.name, host = endpoint.host, port = endpoint.port })
  run_watched(self, watch_signals, function() sup:run() end)
end

--- Boots when needed, then serves HTTP until `shutdown` completes. Returns when the server has stopped; closes the
--- container afterwards. While serving, `sigint` or `sigterm` (unless `signals = false`) starts `shutdown` with the
--- `grace_timeout` option: accepting stops and the requests in flight finish (ADR 0023). A second signal during that
--- drain cancels the remaining requests at once.
---
--- Multi-process serving (ADR 0023): with `workers` above 1 the process is the primary and runs a `Supervisor` of
--- worker processes started from `worker_command`; the signals stop the supervisor (a second one kills the workers).
--- A process started by a supervisor (`supervisor.worker_role()`) boots the application like any other and serves
--- through `WorkerRole:serve`, ignoring signals (the primary sends `stop`). With `workers = 1` and no worker role
--- nothing changes: one process, one `http.Server`.
---
--- Raises what `boot` and `hecate.http.Server:serve` raise, and `hecate.kernel.SupervisorError` in a primary.
---@async
function Application:serve()
  local serve = self._serve or self:boot()
  local role = supervisor.worker_role()
  if role == nil and self._resolved.workers > 1 then
    serve_as_primary(self)
    return
  end
  local server = http.Server(serve, server_options_of(self))
  self._server = server
  if role ~= nil then
    run_watched(self, swallow_signals, function() role:serve(server, self._resolved.grace_timeout) end)
    return
  end
  run_watched(self, watch_signals, function() server:serve() end)
end

--- The address the application listens on, `{ ip, port, family }`, or nil when it is not serving (with `port = 0` this
--- is how a caller learns the port the system chose). In a primary it is the address its own socket is bound to
--- (`round_robin`), or the configured endpoint (`reuseport`, where each worker binds it), once the supervisor runs;
--- with `port = 0` it stays nil until that socket is bound.
---@return hecate.reactor.SocketAddress?
function Application:local_address()
  if self._supervisor ~= nil then
    local address = self._supervisor:local_address()
    if address == nil then return nil end
    if address.ip ~= nil then return address --[[@as hecate.reactor.SocketAddress]] end
    return { ip = address.host, port = address.port, family = address.host:find(":", 1, true) and "inet6" or "inet" }
  end
  return self._server and self._server:local_address() or nil
end

--- Stops accepting and lets the requests in flight finish (see `hecate.http.Server:shutdown`). Does nothing when the
--- application is not serving.
---@async
---@param grace_timeout? number  seconds, default the `grace_timeout` option, else 30
function Application:shutdown(grace_timeout)
  if grace_timeout == nil then grace_timeout = (self._resolved or self._options).grace_timeout end
  if self._supervisor ~= nil then
    self._supervisor:stop(grace_timeout)
  elseif self._server ~= nil then
    self._server:shutdown(grace_timeout)
  end
end

core.finalise(Application)

return Application
