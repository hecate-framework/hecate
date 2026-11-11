-- The dispatcher: turns a route table into the one function that serves a request (http-and-routing.md,
-- "Application and feature modules", "Filters", "Results and serialisation"). Everything that can be decided before the
-- first request is decided here, once: the router is compiled, every action is resolved to a function and every chain
-- is composed. A request then costs a route match, a service scope, the chain and the serialisation.
global <const> require, type, error, pairs, ipairs, next

local core = require("hecate.core")
local http = require("hecate.http")
local router_package = require("hecate.router")
local chain = require("hecate.kernel.chain")
local results = require("hecate.kernel.results")
local problems = require("hecate.kernel.problems")
local errors = require("hecate.kernel.errors")
local input = require("hecate.kernel.input")

--- Options of `dispatcher.build`.
---@class hecate.kernel.DispatcherOptions
---@field filters? hecate.kernel.Filter[]  global filters, outermost of all, before those of a route
---@field container? hecate.container.Container  a validated container: each request opens one service scope on it, bound to `request.scope`; required when a controller declares `dependencies`
---@field router? hecate.router.RouterOptions  options of the router
---@field expose_details? boolean  see `hecate.kernel.problems.Options`
---@field logger? { log: fun(self: any, severity: string, message: string, fields?: table) }  receives unhandled failures
---@field inputs? "lax"|"strict"  policy for undeclared query parameters, default `"strict"`: a request that carries one is refused with a 422 naming each (never its value); `"lax"` drops them. Undeclared header fields and cookies are always dropped. The kernel will bind it to `requests.inputs` (OQ-114 (8))
---@field serialisers? table<string, fun(plain: any): string>  media type to serialiser; default `results.serialisers`
---@field validate_responses? boolean  default false: validate each represented result against the schema declared for its status, a mismatch becomes a logged 500 (development and test, see `results.serialise`)

--- The dispatcher.
---@class hecate.kernel.dispatcher
local dispatcher = {}

--- The action of a controller route: a new controller instance per request (its dependencies resolved in the request
--- scope, so a scoped service is shared by the request), then the method named by the entry.
---@param entry hecate.kernel.RouteEntry
---@param container hecate.container.Container?
---@return fun(request: hecate.http.Request): any
local function controller_action(entry, container)
  local class, method = entry.controller --[[@as table]], entry.action --[[@as string]]
  local dependencies = class.dependencies
  if dependencies ~= nil and next(dependencies) ~= nil and container == nil then
    error(errors.RouteDeclarationError(
      ("kernel: %s: the controller declares dependencies and the application has no container"):format(entry.origin),
      { context = { reason = "missing_container", origin = entry.origin } }))
  end
  return function(request)
    local instance = class()
    if dependencies ~= nil then
      for field, key in pairs(dependencies) do instance[field] = request.scope:resolve(key) end
    end
    return instance[method](instance, request)
  end
end

--- Resolves the action of an entry to a function of the request.
---@param entry hecate.kernel.RouteEntry
---@param container hecate.container.Container?
---@return fun(request: hecate.http.Request): any
local function resolve_action(entry, container)
  if type(entry.action) == "function" then return entry.action --[[@as function]] end
  return controller_action(entry, container)
end

--- Builds the function that serves a request from a route table: `fun(request): Response`. It never raises for a
--- failure of a request (an error becomes a problem details response, see `problems.guard`); cancellation and deadline
--- errors still propagate (ADR 0003).
---
--- Per request, in this order: the route is matched (404, 405, an unreadable path 400, and the automatic `OPTIONS` 204
--- with `Allow`); `request.parameters.path` receives the decoded path parameters as strings; the service scope is opened and closed around the chain;
--- the chain runs the global filters, then those of the entry, then the inputs are read, coerced and validated by the
--- schemas of the route (`hecate.kernel.input`: `request.parameters` and `request.content`, or a `422`, `400`, `415`
--- problem) and the action runs; its result is serialised by
--- `results.serialise` against the entry's `responses`.
---
--- Raises `RouteDeclarationError` (`missing_container`) for a controller with dependencies and no container, the
--- errors of `hecate.router.Router` for a route table it refuses, and `hecate.core.ArgumentError` for a bad argument.
---@param entries hecate.kernel.RouteEntry[]
---@param options? hecate.kernel.DispatcherOptions
---@return fun(request: hecate.http.Request): hecate.http.Response serve
---@return hecate.router.Router router
function dispatcher.build(entries, options)
  options = options or {}
  if type(entries) ~= "table" then error(core.ArgumentError("kernel.dispatcher.build: entries is a list"), 2) end
  local global_filters = options.filters or {}
  local container = options.container
  local router = router_package.Router(entries, options.router)
  local policy = options.inputs
  if policy == nil then policy = "strict" end
  if policy ~= "strict" and policy ~= "lax" then
    error(core.ArgumentError("kernel.dispatcher.build: options.inputs is \"lax\" or \"strict\""), 2)
  end
  local problem_options = { expose_details = options.expose_details, logger = options.logger }
  local input_options = { expose_details = options.expose_details, strict = policy == "strict" }
  local validate_responses = options.validate_responses
  if validate_responses ~= nil and type(validate_responses) ~= "boolean" then
    error(core.ArgumentError("kernel.dispatcher.build: options.validate_responses is a boolean"), 2)
  end
  local serialise_options = { serialisers = options.serialisers, validate_responses = validate_responses == true }

  -- One compiled handler per entry, indexed by the entry itself: the router hands back the table it was given.
  local handlers = {}
  for _, entry in ipairs(entries) do
    local filters = {}
    for _, filter in ipairs(global_filters) do filters[#filters + 1] = filter end
    for _, filter in ipairs(entry.filters) do filters[#filters + 1] = filter end
    local action = resolve_action(entry, container)
    -- The inputs are validated innermost, after the filters (authentication, rate limiting): a client refused by a filter
    -- costs no content read. A route that declares no input gets the action itself.
    local read_input = input.compile(entry, input_options)
    if read_input ~= nil then
      local serve_action = action
      action = function(request)
        return read_input(request) or serve_action(request)
      end
    end
    local composed = chain.compose(filters, action)
    handlers[entry] = function(request)
      return results.serialise(composed(request), request, entry.responses, serialise_options)
    end
  end

  local function serve_matched(request)
    local match = router:match(request.method, request.path)
    local failure = problems.from_match(match)
    if failure ~= nil then return failure end
    if match.status == 204 then
      return http.Response(204, { fields = http.Fields({ Allow = match.allow_field }) })
    end
    request.parameters.path = match.parameters
    local handle = handlers[match.route]
    if container == nil then return handle(request) end
    local scope <close> = container:open_scope()
    request.scope = scope
    return handle(request)
  end

  return problems.guard(serve_matched, problem_options), router
end

return dispatcher
