-- The application: the composition root (http-and-routing.md, "Application and feature modules"). `boot` decides
-- everything that can be decided before the first request (module order, container graph, route table, filter chains);
-- `serve` binds a server on the result.
global <const> require, type, error, ipairs, pairs, tostring, pcall, table, math, arg, package, os, io

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

--- `sighup` starts the rolling reload in a primary and is ignored elsewhere (OQ-115 (4)); libuv does not deliver it on
--- Windows, where it is not watched.
local IS_WINDOWS <const> = package.config:sub(1, 1) == "\\"
---@return string[]
local function watched_signals()
  local names = { table.unpack(SIGNALS) }
  if not IS_WINDOWS then names[#names + 1] = "sighup" end
  return names
end

--- Options of `Application`.
---@class hecate.kernel.ApplicationOptions
---@field modules? hecate.kernel.FeatureModule[]  the feature modules
---@field routes? (hecate.kernel.RouteModule|table)[]  route modules and controllers that belong to no feature
---@field services? fun(container: hecate.container.Container)  binds services of the application itself, before those of the modules
---@field filters? hecate.kernel.Filter[]  global filters, outermost: they also see the requests that match no route (404, 405, 400, automatic `OPTIONS`); the filters of a module apply to its own routes only
---@field container? hecate.container.Container  an existing container (not yet validated); default: a new one
---@field configuration? hecate.config.Configuration  binds `limits.max_depth`, `errors.expose_details`, `requests.inputs`, `server.grace_timeout`, `server.workers`, `server.strategy` and the logging keys; the options below override it
---@field max_depth? integer  nesting depth limit of `json` and `schema` (`json.set_max_depth`, OQ-92)
---@field expose_details? boolean  see `hecate.kernel.DispatcherOptions`
---@field inputs? "lax"|"strict"  see `hecate.kernel.DispatcherOptions`
---@field validate_responses? boolean  validate each result against the schema declared for its status (see `hecate.kernel.DispatcherOptions`); default true when the environment of `configuration` is `development` or `test`, else false (OQ-117)
---@field logger? hecate.log.Logger  receives unhandled failures and the container warnings
---@field router? hecate.router.RouterOptions
---@field server? hecate.http.ServerOptions  options of the HTTP server made by `serve` (`logger` defaults to the application's)
---@field signals? boolean  `true` (default) handles signals, `false` disables signal handling (tests, embedding); the set (`sigint`, `sigterm` stop; `sighup` reloads a primary, and is ignored elsewhere) is fixed and cannot be listed
---@field grace_timeout? number  seconds a signal-driven shutdown lets requests in flight finish (default 30)
---@field workers? integer  number of worker processes, at least 1 (default 1: the process serves by itself); above 1 the primary runs a `hecate.kernel.Supervisor` (ADR 0023)
---@field strategy? "auto"|"reuseport"|"round_robin"  how connections reach the workers (default `auto`, `listening.select`); used only when `workers` is above 1
---@field worker_command? string[]  the program and arguments that start a worker (default: the running interpreter, main program and arguments, `Application.worker_command_from(arg)`)
---@field ready_timeout? number  seconds a worker may take to report `ready` after it starts or restarts (default 30); a worker not ready in time is killed and counted as a crash (see `hecate.kernel.SupervisorOptions`); used only when `workers` is above 1; no configuration key; `reload` has its own `ready_timeout`
---@field on_crash_loop? "stop"|"degrade"  what the primary does when its workers keep crashing (see `hecate.kernel.SupervisorOptions`); default `stop`; used only when `workers` is above 1

--- The composition root.
---@class hecate.kernel.Application
---@field container hecate.container.Container?  the validated container, after `boot`
---@field router hecate.router.Router?  the router, after `boot`
---@field _supervisor hecate.kernel.Supervisor?  the supervisor, while serving as the primary of several workers
---@field _served boolean?  set by the first `serve` that booted
---@field _signalled boolean?  set by the signal watcher once it started `shutdown`
---@overload fun(options?: hecate.kernel.ApplicationOptions): hecate.kernel.Application
local Application = core.class("Application")

local KNOWN = {
  modules = true, routes = true, configuration = true, services = true, filters = true, container = true, max_depth = true,
  expose_details = true, inputs = true, validate_responses = true, logger = true, router = true, server = true, signals = true, grace_timeout = true,
  workers = true, strategy = true, worker_command = true, on_crash_loop = true, ready_timeout = true,
}

local STRATEGIES <const> = { auto = true, reuseport = true, round_robin = true }

--- Creates an application; nothing is checked or built until `boot`.
---
--- Raises `hecate.core.ArgumentError` for an unknown option.
---@param options? hecate.kernel.ApplicationOptions
function Application:init(options)
  options = options or {}
  if type(options) ~= "table" then error(core.ArgumentError("hecate.kernel.application.init: options must be a table, got " .. type(options)), 2) end
  for key in pairs(options) do
    if not KNOWN[key] then
      local names = {}
      for name in pairs(KNOWN) do names[#names + 1] = name end
      table.sort(names)
      error(core.ArgumentError(("hecate.kernel.application.init: unknown option '%s' (valid: %s)"):format(
        tostring(key), table.concat(names, ", "))), 2)
    end
  end
  if options.signals ~= nil and type(options.signals) ~= "boolean" then
    error(core.ArgumentError(("hecate.kernel.application.init: signals is true (default handling) or false (off), got %s; "
      .. "the signal set is fixed (sigint, sigterm stop; sighup reloads a primary)"):format(type(options.signals))), 2)
  end
  local grace = options.grace_timeout
  if grace ~= nil and (type(grace) ~= "number" or grace ~= grace or grace < 0 or grace == math.huge) then
    error(core.ArgumentError("hecate.kernel.application.init: grace_timeout must be a non-negative finite number of seconds, got "
      .. tostring(grace)), 2)
  end
  if options.workers ~= nil and (math.type(options.workers) ~= "integer" or options.workers < 1) then
    error(core.ArgumentError("hecate.kernel.application.init: workers must be an integer of at least 1, got "
      .. tostring(options.workers)), 2)
  end
  if options.strategy ~= nil and not STRATEGIES[options.strategy] then
    error(core.ArgumentError("hecate.kernel.application.init: strategy must be one of auto, reuseport, round_robin, got "
      .. tostring(options.strategy)), 2)
  end
  if options.on_crash_loop ~= nil and options.on_crash_loop ~= "stop" and options.on_crash_loop ~= "degrade" then
    error(core.ArgumentError(("hecate.kernel.application.init: on_crash_loop must be \"stop\" or \"degrade\", got %s"):format(
      type(options.on_crash_loop) == "string" and ("%q"):format(options.on_crash_loop) or type(options.on_crash_loop))), 2)
  end
  local ready_timeout = options.ready_timeout
  if ready_timeout ~= nil and (type(ready_timeout) ~= "number" or ready_timeout ~= ready_timeout or ready_timeout < 0 or ready_timeout == math.huge) then
    error(core.ArgumentError("hecate.kernel.application.init: ready_timeout must be a non-negative finite number of seconds, got "
      .. tostring(ready_timeout)), 2)
  end
  local command = options.worker_command
  if command ~= nil then
    local valid = type(command) == "table" and type(command[1]) == "string"
    for i = 1, valid and #command or 0 do if type(command[i]) ~= "string" then valid = false end end
    if not valid then error(core.ArgumentError("hecate.kernel.application.init: worker_command must be a list of strings, the program first, got "
      .. type(command)), 2) end
  end
  self._options = options
  self._booted = false
end

--- Resolves a bare program name (no path separator) against a search path; any other name is returned unchanged.
---@param program string
---@param search_path? string  default the `PATH` environment variable
---@return string
local function resolve_interpreter(program, search_path)
  if program:find("[/\\]") then return program end
  search_path = search_path or os.getenv("PATH")
  if search_path == nil or search_path == "" then return program end
  local separator = IS_WINDOWS and ";" or ":"
  local names = IS_WINDOWS and { program, program .. ".exe" } or { program }
  for entry in (search_path .. separator):gmatch("([^" .. separator .. "]*)" .. separator) do
    local directory = entry:gsub("[/\\]$", "")
    if directory ~= "" then
      -- Only an absolute directory yields an absolute path.
      if directory:match("^/") or directory:match("^%a:") then
        for _, name in ipairs(names) do
          local candidate = directory .. "/" .. name
          local file = io.open(candidate, "rb")
          if file ~= nil then
            file:close()
            return candidate
          end
        end
      end
    end
  end
  return program
end

--- The command that starts the running program again, from the `arg` table of the standalone interpreter: the
--- interpreter and its options (the negative indices), the main program (`arg[0]`) and its arguments. A worker is that
--- program started with the worker role in its environment (ADR 0023, Decision 1).
---
--- An interpreter named without a path separator (`lua`, started through the search path) is replaced by the absolute
--- path of the first file of that name found in the search path, so that a worker does not depend on the `PATH` of the
--- primary's children; when none is found the name is kept as it is.
---
--- Raises `hecate.core.ArgumentError` when there is no main program (interactive use, `-e`, embedding): give `worker_command`.
---@param arguments? table  default the global `arg`
---@param search_path? string  the directories to search for a bare interpreter name, separated like `PATH`; default the `PATH` environment variable
---@return string[] command
function Application.worker_command_from(arguments, search_path)
  arguments = arguments or arg
  local lowest = 0
  if type(arguments) == "table" then
    for index in pairs(arguments) do
      if math.type(index) == "integer" and index < lowest then lowest = index end
    end
  end
  if type(arguments) ~= "table" or lowest == 0 or type(arguments[0]) ~= "string" then
    error(core.ArgumentError("hecate.kernel.application.worker_command_from: cannot tell how to start a worker (no main program in `arg`); give the worker_command option"), 2)
  end
  local command = {}
  for index = lowest, #arguments do
    local part = arguments[index]
    if type(part) ~= "string" then
      error(core.ArgumentError("hecate.kernel.application.worker_command_from: cannot tell how to start a worker (`arg` has a gap); give the worker_command option"), 2)
    end
    command[#command + 1] = part
  end
  command[1] = resolve_interpreter(command[1], search_path)
  return command
end

--- Boots the application: orders the modules (rejecting duplicates, missing dependencies and cycles), binds the
--- services (application first, then each module in order), validates the container graph, gathers the route table and
--- builds the function that serves a request; only then applies `max_depth` (`json.set_max_depth`) and, when the
--- logger comes from `configuration`, installs it as the default logger (`log.set_default`). Container warnings go to
--- the logger.
---
--- A failed boot changes no process-wide setting and leaves the application unbooted (`container`, `router` and the
--- resolved options stay unset). What it can leave behind: the services already bound into a container given with the
--- `container` option (a container made by `boot` is discarded), and the warnings already logged. Boot such an
--- application again only with a new container.
---
--- Raises `hecate.kernel.ModuleError` (including `already_booted`), `hecate.container.GraphError`,
--- `hecate.kernel.RouteDeclarationError`, the errors of `hecate.router.Router` and `hecate.core.ArgumentError`.
---@return fun(request: hecate.http.Request): hecate.http.Response action  the function given to `http.Server`: serves one request
function Application:boot()
  if self._booted then
    error(errors.ModuleError("hecate.kernel.application.boot: the application is already booted", { context = { reason = "already_booted" } }), 2)
  end
  local options = {}
  for key, value in pairs(self._options) do options[key] = value end
  local configuration = options.configuration
  local built_logger = false -- the logger comes from the configuration: it becomes the default once boot succeeded
  if configuration ~= nil then
    if options.max_depth == nil then options.max_depth = configuration:get("limits.max_depth") end
    if options.expose_details == nil then options.expose_details = configuration:get("errors.expose_details") end
    if options.inputs == nil then options.inputs = configuration:get("requests.inputs") end
    if options.validate_responses == nil then
      local environment = configuration:environment()
      options.validate_responses = environment == "development" or environment == "test"
    end
    if options.grace_timeout == nil then options.grace_timeout = configuration:get("server.grace_timeout") end
    if options.workers == nil then options.workers = configuration:get("server.workers") end
    if options.strategy == nil then options.strategy = configuration:get("server.strategy") end
    if options.logger == nil then
      options.logger = logging.build(configuration)
      built_logger = true
    end
    if options.expose_details and configuration:environment() == "production" then
      options.logger:warning("errors.expose_details is true in the production environment: internal details reach clients",
        { code = "expose_details_in_production" })
    end
  end
  if options.validate_responses == nil then options.validate_responses = false end
  if options.workers == nil then options.workers = 1 end
  if options.strategy == nil then options.strategy = "auto" end
  local ordered = modules.order(options.modules or {})
  local container = options.container or container_package.Container()
  if options.services then options.services(container) end
  local sources, filters = {}, {}
  for _, source in ipairs(options.routes or {}) do sources[#sources + 1] = source end
  for _, filter in ipairs(options.filters or {}) do filters[#filters + 1] = filter end
  -- The filters of a feature module are not global: they are kept with the routes of that module (second layer).
  local module_sources = {}
  for _, module in ipairs(ordered) do
    if module.services then module.services(container) end
    module_sources[#module_sources + 1] = { sources = module.routes or {}, filters = module.filters }
  end
  local _, warnings = container:validate()
  local logger = options.logger
  if logger ~= nil then
    for _, warning in ipairs(warnings) do
      logger:log("warning", "container: " .. tostring(warning.message), { code = warning.code })
    end
  end
  local entries = routing.collect(sources)
  for _, owned in ipairs(module_sources) do
    for _, entry in ipairs(routing.collect(owned.sources, owned.filters)) do entries[#entries + 1] = entry end
  end
  local serve, router = dispatcher.build(entries, {
    filters = filters, container = container, router = options.router, expose_details = options.expose_details,
    logger = logger, inputs = options.inputs, validate_responses = options.validate_responses,
  })
  -- Everything succeeded: only now do the process-wide settings and the application state change.
  if options.max_depth ~= nil then json.set_max_depth(options.max_depth) end
  if built_logger then log.set_default(options.logger) end
  self._resolved = options
  self.container, self.router, self._serve, self._booted = container, router, serve, true
  return serve
end

--- The reason, the cause and the message of a failed reload (nil and nil for an error that is not a `SupervisorError`).
---@param err any
---@return string? reason
---@return string? cause
---@return string message
local function describe_failure(err)
  if core.is_instance_of(err, errors.SupervisorError) then
    local failure = err --[[@as hecate.kernel.SupervisorError]]
    return failure.context.reason, failure.context.cause, tostring(failure.message)
  end
  return nil, nil, tostring(err)
end

--- Runs a reload for `sighup`: logs, never raises (a failed reload leaves the primary serving). Not started once a
--- shutdown began; a reload already running makes the signal a no-op with a warning.
---@async
---@param self hecate.kernel.Application
---@param logger? hecate.log.Logger
local function reload_on_signal(self, logger)
  if self._signalled then return end
  local ok, err = pcall(self.reload, self)
  if ok then return end
  if core.is_instance_of(err, core.CancellationError) then error(err, 0) end
  local reason, _, message = describe_failure(err)
  if logger ~= nil and (reason == "reload_in_progress" or reason == "stopping" or reason == "not_running") then
    logger:warning("kernel.Application: reload refused: " .. message, { code = "reload_refused", reason = reason })
  end
end

--- Waits for `sigint` or `sigterm`, then shuts the application down gracefully. `sighup` starts the rolling reload of
--- the workers in a primary (in a computation of its own, so that a stop signal during the reload is heard) and is ignored in a
--- single process. While the shutdown drains, a second signal forces the stop: the requests still in flight are
--- cancelled at once (`Server:shutdown(0)`, OQ-115). A signal the platform cannot watch is logged once and the
--- application serves without signal handling.
---@async
---@param self hecate.kernel.Application
---@param watcher hecate.reactor.SignalWatcher
---@param logger? hecate.log.Logger
local function watch_signals(self, watcher, logger)
  reactor.scope(function(reloads)
    local name
    while true do
      local ok, received = pcall(watcher.wait, watcher)
      if not ok then
        if core.is_instance_of(received, core.CancellationError) then error(received, 0) end
        return
      end
      if received ~= "sighup" then
        name = received
        break
      end
      if self._supervisor ~= nil then
        reloads:fork(reload_on_signal, self, logger)
      elseif logger ~= nil then
        logger:debug("kernel.Application: sighup ignored; only a primary of several workers reloads", { code = "reload_ignored" })
      end
    end
    self._signalled = true
    if logger ~= nil then
      logger:notice("kernel.Application: signal received, shutting down gracefully",
        { code = "shutdown_signal", signal = name })
    end
    -- The drain runs in this scope's body; the forked computation waits for the second signal and ends with the scope (ADR 0003).
    reactor.scope(function(scope)
      local forcer = scope:fork(function()
        while true do
          local second_ok, second = pcall(watcher.wait, watcher)
          if not second_ok then
            if core.is_instance_of(second, core.CancellationError) then error(second, 0) end
            return
          end
          if second ~= "sighup" then
            if logger ~= nil then
              logger:warning("kernel.Application: second signal received, stopping now", { code = "shutdown_forced", signal = second })
            end
            -- The primary cannot wait for the workers' own drain any more: it kills them (`Supervisor:force`).
            if self._supervisor ~= nil then self._supervisor:force() else self:shutdown(0) end
            return
          end
        end
      end)
      self:shutdown((self._resolved or self._options).grace_timeout)
      forcer:cancel()
    end)
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
    local watching, watcher
    -- One persistent watcher for the whole run: a signal delivered between two waits is queued, never lost (a worker
    -- would take the default action and die). It is closed once the body has ended, after the watching computation is cancelled.
    if self._options.signals ~= false then
      local created, handle = pcall(reactor.watch_signals, table.unpack(watched_signals()))
      if created then
        watcher = handle
        watching = scope:fork(watch, self, handle, logger or log.default())
      elseif logger ~= nil then
        logger:warning("kernel.Application: signals cannot be watched; serving without graceful shutdown on signals",
          { code = "signals_unavailable" })
      end
    end
    local body_ok, body_err = pcall(body)
    -- A watcher that received its signal is inside `shutdown` and ends by itself.
    if watching ~= nil and not self._signalled then watching:cancel() end
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
    on_crash_loop = resolved.on_crash_loop, ready_timeout = resolved.ready_timeout,
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
--- An application is served once: `serve` closes the container when it returns, so a second call (while serving or
--- after the shutdown) raises `hecate.kernel.ModuleError` with `context.reason = "already_served"`; build a new
--- application to serve again. A `serve` whose `boot` failed does not count.
---
--- Raises what `boot` and `hecate.http.Server:serve` raise, `hecate.kernel.ModuleError` (`already_served`) and
--- `hecate.kernel.SupervisorError` in a primary.
---@async
function Application:serve()
  if self._served then
    error(errors.ModuleError("hecate.kernel.application.serve: the application has already been served (serve runs once, the container is closed when it returns)",
      { context = { reason = "already_served" } }), 2)
  end
  local serve = self._serve or self:boot()
  self._served = true
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

--- Replaces the workers one at a time with fresh processes that run the code on disk now (`Supervisor:reload`, the
--- rolling reload of ADR 0023), and returns when every worker has been replaced. In a primary, `sighup` (not on Windows)
--- starts the same reload; this method is for programmatic use. Logs `reload_started` and `reload_done` (`notice`) and
--- `reload_failed` (`error`, with the reason); a failed reload leaves the old workers serving.
---
--- Raises `hecate.kernel.SupervisorError` (`reload_failed`, `reload_in_progress`, `stopping`; see `Supervisor:reload`)
--- and `hecate.core.ArgumentError` when the application is not a primary of several workers that is serving.
---@async
---@param options? { grace_timeout?: number, ready_timeout?: number }  `grace_timeout`: seconds the old workers drain, default the `grace_timeout` option, else 30; `ready_timeout`: seconds a replacement may take to become ready, default 30
function Application:reload(options)
  local sup = self._supervisor
  if sup == nil then
    error(core.ArgumentError("hecate.kernel.application.reload: only a serving primary of several workers can reload"), 2)
  end
  if options ~= nil and type(options) ~= "table" then
    error(core.ArgumentError("hecate.kernel.application.reload: options must be a table { grace_timeout?, ready_timeout? }, got " .. type(options)), 2)
  end
  local given = options or {}
  options = { grace_timeout = given.grace_timeout, ready_timeout = given.ready_timeout }
  if options.grace_timeout == nil then options.grace_timeout = (self._resolved or self._options).grace_timeout end
  local logger = (self._resolved or self._options).logger or log.default()
  logger:notice("kernel.Application: reloading the workers", { code = "reload_started" })
  local ok, err = pcall(sup.reload, sup, options)
  if not ok then
    if core.is_instance_of(err, core.CancellationError) then error(err, 0) end
    local reason, cause, message = describe_failure(err)
    if reason ~= "reload_in_progress" and reason ~= "stopping" and reason ~= "not_running" then
      logger:error("kernel.Application: reload failed: " .. message,
        { code = "reload_failed", reason = reason, cause = cause })
    end
    error(err, 0)
  end
  logger:notice("kernel.Application: workers reloaded", { code = "reload_done" })
end

core.finalise(Application)

return Application
