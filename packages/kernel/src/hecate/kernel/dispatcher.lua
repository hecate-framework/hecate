-- The dispatcher: turns a route table into the one function that serves a request (http-and-routing.md,
-- "Application and feature modules", "Filters", "Results and serialisation"). Everything that can be decided before the
-- first request is decided here, once: the router is compiled, every action is resolved to a function and every chain
-- is composed. A request then costs a route match, a service scope, the chain and the serialisation.
global <const> require, type, error, pairs, ipairs, table, tostring, pcall

local core = require("hecate.core")
local reactor = require("hecate.reactor")
local http = require("hecate.http")
local router_package = require("hecate.router")
local chain = require("hecate.kernel.chain")
local results = require("hecate.kernel.results")
local problems = require("hecate.kernel.problems")
local errors = require("hecate.kernel.errors")
local input = require("hecate.kernel.input")

--- Options of `dispatcher.build`.
---@class hecate.kernel.DispatcherOptions
---@field filters? hecate.kernel.Filter[]  global filters, outermost of all: they wrap the routing step, so they also see requests that match no route; the filters of a module come from `entry.module_filters`
---@field container? hecate.container.Container  a validated container: each request opens one service scope on it, bound to `request.services` (`request.scope` stays the reactor scope `http.Server` sets); required when a controller declares `dependencies`
---@field router? hecate.router.RouterOptions  options of the router
---@field expose_details? boolean  see `hecate.kernel.problems.GuardOptions`
---@field logger? { log: fun(self: any, severity: string, message: string, fields?: table) }  receives unhandled failures
---@field inputs? "lax"|"strict"  policy for undeclared query parameters, default `"strict"`: a request that carries one is refused with a 422 naming each (never its value); `"lax"` drops them. Undeclared header fields and cookies are always dropped. The kernel will bind it to `requests.inputs` (OQ-114 (8))
---@field serialisers? table<string, fun(plain: any): string>  media type to serialiser; default `results.serialisers`
---@field validate_responses? boolean  default false: validate each represented result against the schema declared for its status, a mismatch becomes a logged 500 (development and test, see `results.serialise`)

--- The dispatcher.
---@class hecate.kernel.dispatcher
local dispatcher = {}

--- Seconds the close of a service scope may take when it runs under `reactor.shield` (a cancelled request): the
--- `__close` of a scoped service may suspend (concurrency.md, rule 4). No value is decided by a specification; this
--- bound is the conservative choice of the kernel.
dispatcher.CLOSE_TIMEOUT = 5

--- Closes a service scope; under `reactor.shield` when `cancelled`, so that a `__close` that suspends completes.
---@param services hecate.container.ServiceScope
---@param cancelled boolean
local function close_services(services, cancelled)
  if cancelled then
    reactor.shield(dispatcher.CLOSE_TIMEOUT, services.close, services)
  else
    services:close()
  end
end

--- The action of a controller route: a new controller instance per request (its dependencies resolved in `request.services`,
--- so a scoped service is shared by the request), then the method named by the entry.
---@param entry hecate.kernel.RouteEntry
---@param container hecate.container.Container?
---@return fun(request: hecate.kernel.Request): any
local function controller_action(entry, container)
  local class, method = entry.controller --[[@as table]], entry.action --[[@as string]]
  local dependencies = class.dependencies
  if dependencies ~= nil and type(dependencies) ~= "table" then
    error(errors.RouteDeclarationError(
      ("hecate.kernel.dispatcher.build: %s: dependencies must be a table of field names to binding names, got %s"):format(entry.origin, type(dependencies)),
      { context = { reason = "invalid_dependencies", origin = entry.origin, field = "dependencies" } }))
  end
  -- Resolved in sorted order of the field names, so that two requests (and two runs) build the services in the same
  -- order: the list is computed once, here.
  local fields = {}
  for field, key in pairs(dependencies or {}) do
    if type(field) ~= "string" or field == "" or type(key) ~= "string" or key == "" then
      error(errors.RouteDeclarationError(
        ("hecate.kernel.dispatcher.build: %s: dependencies must map non-empty field names to non-empty binding names, got %s = %s"):format(
          entry.origin, type(field), type(key)),
        { context = { reason = "invalid_dependencies", origin = entry.origin, field = "dependencies" } }))
    end
    fields[#fields + 1] = field
  end
  table.sort(fields)
  if #fields > 0 and container == nil then
    error(errors.RouteDeclarationError(
      ("hecate.kernel.dispatcher.build: %s: the controller declares dependencies and the application has no container"):format(entry.origin),
      { context = { reason = "missing_container", origin = entry.origin } }))
  end
  -- Nothing is validated lazily at the first request: a binding name with a typo fails the boot.
  for _, field in ipairs(fields) do
    ---@cast container hecate.container.Container
    if not container:has(dependencies[field]) then
      error(errors.RouteDeclarationError(
        ("hecate.kernel.dispatcher.build: %s: the dependency %q names %q, which has no binding in the container"):format(
          entry.origin, field, dependencies[field]),
        { context = { reason = "unknown_dependency", origin = entry.origin, field = "dependencies." .. field } }))
    end
  end
  return function(request)
    local instance = class()
    for index = 1, #fields do
      local field = fields[index]
      instance[field] = request.services:resolve(dependencies[field])
    end
    return instance[method](instance, request)
  end
end

--- Resolves the action of an entry to a function of the request.
---@param entry hecate.kernel.RouteEntry
---@param container hecate.container.Container?
---@return fun(request: hecate.kernel.Request): any
local function resolve_action(entry, container)
  if type(entry.action) == "function" then return entry.action --[[@as function]] end
  return controller_action(entry, container)
end

--- Builds the function that serves a request from a route table: `fun(request): Response`. It never raises for a
--- failure of a request (an error becomes a problem details response, see `problems.guard`); cancellation and deadline
--- errors still propagate (ADR 0003).
---
--- Per request, in this order: the global filters (they wrap the routing step, so they also see the 404, 405, 400 and
--- automatic `OPTIONS` 204 answers; at that point `request` carries no route: `request.parameters.path` is still the
--- empty table the request was created with and `request.services` is not set); the guard (`problems.guard`: an error
--- becomes a problem response that flows back through the global filters); the route is matched (404, 405, an
--- unreadable path 400, and the automatic `OPTIONS` 204 with `Allow`); `request.parameters.path` receives the decoded
--- path parameters as strings; the service scope is opened (`request.services`) before the chain of the entry;
--- the chain runs the filters of the module of the entry (none for a route outside a feature module), then those of the controller and of the route, then the inputs are read, coerced and validated by the
--- schemas of the route (`hecate.kernel.input`: `request.parameters` and `request.content`, or a `422`, `400`, `415`
--- problem) and the action runs; its result is serialised by
--- `results.serialise` against the entry's `responses`.
---
--- The service scope of a request lives as long as the request (container.md, "Lifetimes"): a writer (a `Response`
--- whose content is a function) runs after `serve` has returned and may use its scoped services. So `serve` leaves the
--- service scope open when the request has a reactor scope (`request.scope`, set by `http.Server`) or when the
--- response has a writer, and `finish(request)` closes it: the application gives `finish` to the server as
--- `on_request_end`, called once the response is written and every computation of the request has ended, also when
--- the request was cancelled; an in-process caller that consumes a writer calls `finish` itself afterwards. Otherwise
--- (in-process, no writer) `serve` closes the service scope before it returns. A close in a cancelled request (the
--- reactor scope of the request was cancelled, or the chain raised a cancellation) runs under `reactor.shield`
--- (`dispatcher.CLOSE_TIMEOUT` seconds).
---
--- Raises `RouteDeclarationError` (`missing_container`) for a controller with dependencies and no container, the
--- errors of `hecate.router.Router` for a route table it refuses, and `hecate.core.ArgumentError` for a bad argument.
---@param entries hecate.kernel.RouteEntry[]
---@param options? hecate.kernel.DispatcherOptions
---@return fun(request: hecate.http.Request): hecate.http.Response serve
---@return hecate.router.Router router
---@return async fun(request: hecate.http.Request) finish  ends the service scope `serve` left open for `request` (see above); does nothing for any other request, and the second time
function dispatcher.build(entries, options)
  options = options or {}
  if type(entries) ~= "table" then error(core.ArgumentError("hecate.kernel.dispatcher.build: entries must be a list, got " .. type(entries)), 2) end
  local global_filters = options.filters or {}
  local container = options.container
  local router = router_package.Router(entries, options.router)
  local policy = options.inputs
  if policy == nil then policy = "strict" end
  if policy ~= "strict" and policy ~= "lax" then
    error(core.ArgumentError("hecate.kernel.dispatcher.build: options.inputs must be \"lax\" or \"strict\", got " .. tostring(policy)), 2)
  end
  local problem_options = { expose_details = options.expose_details, logger = options.logger }
  local input_options = { expose_details = options.expose_details, strict = policy == "strict" }
  local validate_responses = options.validate_responses
  if validate_responses ~= nil and type(validate_responses) ~= "boolean" then
    error(core.ArgumentError("hecate.kernel.dispatcher.build: options.validate_responses must be a boolean, got " .. type(validate_responses)), 2)
  end
  local serialise_options = { serialisers = options.serialisers, validate_responses = validate_responses == true, logger = options.logger }

  -- One compiled chain per entry, indexed by the entry itself: the router hands back the table it was given. The
  -- global filters are not part of it: they wrap the routing step (below). Layers here: module, controller, route.
  local chains = {}
  for _, entry in ipairs(entries) do
    local filters = {}
    for _, filter in ipairs(entry.module_filters or {}) do filters[#filters + 1] = filter end
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
    chains[entry] = function(request)
      return results.serialise(composed(request), request, entry.responses, serialise_options)
    end
  end

  -- The service scopes `serve` left open, until `finish`: weak keys, so that a request nobody finishes (an in-process
  -- caller that drops a writer) does not keep its service scope reachable for ever.
  local pending = core.weak_table("k")

  local function serve_matched(request)
    local match = router:match(request.method, request.path)
    local failure = problems.from_match(match)
    if failure ~= nil then return failure end
    if match.status == 204 then
      return http.Response(204, { fields = http.Fields({ Allow = match.allow_field }) })
    end
    request.parameters.path = match.parameters
    local run_chain = chains[match.route]
    if container == nil then return run_chain(request) end
    local services = container:open_scope()
    request.services = services
    local ok, response = pcall(run_chain, request)
    if request.scope ~= nil or (ok and type(response.content) == "function") then
      pending[request] = services -- closed by `finish`, when the request has ended
    else
      close_services(services, not ok and core.is_instance_of(response, core.CancellationError))
    end
    if not ok then error(response, 0) end
    return response
  end

  ---@async
  local function finish(request)
    local services = pending[request]
    if services == nil then return end
    pending[request] = nil
    local scope = request.scope
    close_services(services, type(scope) == "table" and type(scope.is_cancelled) == "function" and scope:is_cancelled())
  end

  -- Order (http-and-routing.md, "Filters"): global filters, then the guard, then match and dispatch. The guard is inside
  -- the global filters: an error of the routing step, of a module, controller or route filter or of the action becomes a
  -- problem response that flows back through them (their code after `next` runs).
  local guarded = problems.guard(serve_matched, problem_options)
  if #global_filters == 0 then return guarded, router, finish end
  -- The outer guard is a safety net for an error raised by a global filter itself: `serve` never raises for a failure
  -- of a request. It does not run for the failures the inner guard already turned into responses.
  local filtered = chain.compose(global_filters, guarded)
  return problems.guard(filtered, problem_options), router, finish
end

return dispatcher
