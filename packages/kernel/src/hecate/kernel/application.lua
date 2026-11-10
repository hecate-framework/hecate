-- The application: the composition root (http-and-routing.md, "Application and feature modules"). `boot` decides
-- everything that can be decided before the first request (module order, container graph, route table, filter chains);
-- `serve` binds a server on the result.
global <const> require, type, error, ipairs, pairs, tostring, pcall, table, math

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
---@field configuration? hecate.config.Configuration  binds `limits.max_depth`, `errors.expose_details`, `requests.inputs`, `server.grace_timeout` and the logging keys; the options below override it
---@field max_depth? integer  nesting depth limit of `json` and `schema` (`json.set_max_depth`, OQ-92)
---@field expose_details? boolean  see `hecate.kernel.DispatcherOptions`
---@field inputs? "lax"|"strict"  see `hecate.kernel.DispatcherOptions`
---@field logger? hecate.log.Logger  receives unhandled failures and the container warnings
---@field router? hecate.router.RouterOptions
---@field server? hecate.http.ServerOptions  options of the HTTP server made by `serve` (`logger` defaults to the application's)
---@field signals? false  `false` disables signal handling (tests, embedding); the set (`sigint`, `sigterm`) is fixed and cannot be listed
---@field grace_timeout? number  seconds a signal-driven shutdown lets requests in flight finish (default 30)

--- The composition root.
---@class hecate.kernel.Application
---@field container hecate.container.Container?  the validated container, after `boot`
---@field router hecate.router.Router?  the router, after `boot`
---@field _signalled boolean?  set by the signal watcher once it started `shutdown`
---@overload fun(options?: hecate.kernel.ApplicationOptions): hecate.kernel.Application
local Application = core.class("Application")

local KNOWN = {
  modules = true, routes = true, configuration = true, services = true, filters = true, container = true, max_depth = true,
  expose_details = true, inputs = true, logger = true, router = true, server = true, signals = true, grace_timeout = true,
}

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
  self._options = options
  self._booted = false
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
    if options.logger == nil then
      options.logger = logging.build(configuration)
      log.set_default(options.logger)
    end
    if options.expose_details and configuration:environment() == "production" then
      options.logger:warning("errors.expose_details is true in the production environment: internal details reach clients",
        { code = "expose_details_in_production" })
    end
  end
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
---@param logger? hecate.log.Logger
local function watch_signals(self, logger)
  local ok, name = pcall(reactor.wait_signal, table.unpack(SIGNALS))
  if not ok then
    if core.is_instance_of(name, core.CancellationError) then error(name, 0) end
    if logger ~= nil then
      logger:warning("kernel.Application: signals cannot be watched; serving without graceful shutdown on signals",
        { code = "signals_unavailable" })
    end
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
      local second_ok, second = pcall(reactor.wait_signal, table.unpack(SIGNALS))
      if not second_ok then
        if core.is_instance_of(second, core.CancellationError) then error(second, 0) end
        return
      end
      if logger ~= nil then
        logger:warning("kernel.Application: second signal received, stopping now", { code = "shutdown_forced", signal = second })
      end
      self:shutdown(0)
    end)
    self:shutdown((self._resolved or self._options).grace_timeout)
    forcer:cancel()
  end)
end

--- Boots when needed, then serves HTTP until `shutdown` completes. Returns when the server has stopped; closes the
--- container afterwards. While serving, `sigint` or `sigterm` (unless `signals = false`) starts `shutdown` with the
--- `grace_timeout` option: accepting stops and the requests in flight finish (ADR 0023). A second signal during that
--- drain cancels the remaining requests at once.
---
--- Raises what `boot` and `hecate.http.Server:serve` raise.
---@async
function Application:serve()
  local serve = self._serve or self:boot()
  local server_options = {}
  for key, value in pairs(self._options.server or {}) do server_options[key] = value end
  local logger = self._resolved.logger
  if server_options.logger == nil then server_options.logger = logger end
  local server = http.Server(serve, server_options)
  self._server = server
  local watched = self._options.signals ~= false
  local ok, err = pcall(reactor.scope, function(scope)
    local watcher
    if watched then watcher = scope:fork(watch_signals, self, logger or log.default()) end
    server:serve()
    -- A watcher that received its signal is inside `shutdown` and ends by itself.
    if watcher ~= nil and not self._signalled then watcher:cancel() end
  end)
  self._server = nil
  self.container:close()
  if not ok then error(err, 0) end
end

--- Stops accepting and lets the requests in flight finish (see `hecate.http.Server:shutdown`). Does nothing when the
--- application is not serving.
---@async
---@param grace_timeout? number  seconds, default the `grace_timeout` option, else 30
function Application:shutdown(grace_timeout)
  if grace_timeout == nil then grace_timeout = (self._resolved or self._options).grace_timeout end
  if self._server ~= nil then self._server:shutdown(grace_timeout) end
end

core.finalise(Application)

return Application
