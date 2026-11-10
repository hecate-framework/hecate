-- The application: the composition root (http-and-routing.md, "Application and feature modules"). `boot` decides
-- everything that can be decided before the first request (module order, container graph, route table, filter chains);
-- `serve` binds a server on the result.
global <const> require, type, error, ipairs, pairs, tostring, pcall

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

--- Options of `Application`.
---@class hecate.kernel.ApplicationOptions
---@field modules? hecate.kernel.FeatureModule[]  the feature modules
---@field routes? (hecate.kernel.RouteModule|table)[]  route modules and controllers that belong to no feature
---@field services? fun(container: hecate.container.Container)  binds services of the application itself, before those of the modules
---@field filters? hecate.kernel.Filter[]  global filters, outermost, before those of the modules
---@field container? hecate.container.Container  an existing container (not yet validated); default: a new one
---@field configuration? hecate.config.Configuration  binds `limits.max_depth`, `errors.expose_details`, `requests.inputs` and the logging keys; the options below override it
---@field max_depth? integer  nesting depth limit of `json` and `schema` (`json.set_max_depth`, OQ-92)
---@field expose_details? boolean  see `hecate.kernel.DispatcherOptions`
---@field inputs? "lax"|"strict"  see `hecate.kernel.DispatcherOptions`
---@field logger? hecate.log.Logger  receives unhandled failures and the container warnings
---@field router? hecate.router.RouterOptions
---@field server? hecate.http.ServerOptions  options of the HTTP server made by `serve` (`logger` defaults to the application's)

--- The composition root.
---@class hecate.kernel.Application
---@field container hecate.container.Container?  the validated container, after `boot`
---@field router hecate.router.Router?  the router, after `boot`
---@overload fun(options?: hecate.kernel.ApplicationOptions): hecate.kernel.Application
local Application = core.class("Application")

local KNOWN = {
  modules = true, routes = true, configuration = true, services = true, filters = true, container = true, max_depth = true,
  expose_details = true, inputs = true, logger = true, router = true, server = true,
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

--- Boots when needed, then serves HTTP until `shutdown` completes. Returns when the server has stopped; closes the
--- container afterwards.
---
--- Raises what `boot` and `hecate.http.Server:serve` raise.
---@async
function Application:serve()
  local serve = self._serve or self:boot()
  local server_options = {}
  for key, value in pairs(self._options.server or {}) do server_options[key] = value end
  if server_options.logger == nil then server_options.logger = self._resolved.logger end
  local server = http.Server(serve, server_options)
  self._server = server
  local ok, err = pcall(server.serve, server)
  self._server = nil
  self.container:close()
  if not ok then error(err, 0) end
end

--- Stops accepting and lets the requests in flight finish (see `hecate.http.Server:shutdown`). Does nothing when the
--- application is not serving.
---@async
---@param grace_timeout? number  seconds, default 30
function Application:shutdown(grace_timeout)
  if self._server ~= nil then self._server:shutdown(grace_timeout) end
end

core.finalise(Application)

return Application
