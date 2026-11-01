-- The router: a route table compiled at boot into a radix tree (see tree.lua), with 404/405 handling, automatic HEAD
-- and OPTIONS, and reverse routing.
global <const> require, type, error, pairs, ipairs, string, table, next, tostring

local core = require("hecate.core")
local errors = require("hecate.router.errors")
local path = require("hecate.router.path")
local template = require("hecate.router.template")
local tree = require("hecate.router.tree")

local RouteTableError = errors.RouteTableError

--- A route declaration as the router reads it; every other key is metadata the router keeps and gives back untouched.
---@class hecate.router.Route
---@field method string|string[]  one method or a non-empty list of methods (RFC 9110 section 9.1, case-sensitive tokens)
---@field path string  a path template: `/users/{id}`, `/static/{path...}`
---@field name? string  unique among the routes; the key of reverse routing
---@field [string] any

--- Options of a router.
---@class hecate.router.Options
---@field trailing_slash? "strict"|"ignore"  `strict` (default): `/a` and `/a/` are different paths; `ignore`: both are `/a`
---@field automatic_head? boolean  default `true`: `HEAD` is served by the `GET` route unless a `HEAD` route exists
---@field automatic_options? boolean  default `true`: `OPTIONS` answers 204 with `Allow` unless an `OPTIONS` route exists

--- The result of matching a request.
---@class hecate.router.Match
---@field status 200|204|400|404|405  200: `route` serves the request; 204: automatic `OPTIONS`; 400: the path is
---  unreadable (`reason`); 404: no route has this path; 405: the path exists, not for this method
---@field route? hecate.router.Route  the route table as declared (status 200)
---@field parameters? table<string, string>  path parameter name to decoded value (status 200)
---@field allow? string[]  the methods the path serves, sorted (status 204 and 405)
---@field allow_field? string  `allow` as the value of the `Allow` field: `GET, HEAD, OPTIONS` (status 204 and 405)
---@field reason? string  `not_absolute`, `malformed_percent_encoding` or `encoded_nul` (status 400)

--- A compiled route table. It is built once, at boot, and never changes; matching is a walk down a radix tree over the
--- decoded segments of the path, in the order static, parameter, wildcard, so its cost depends on the length of the
--- path and not on the number of routes.
---@class hecate.router.Router
---@overload fun(routes: hecate.router.Route[], options?: hecate.router.Options): hecate.router.Router
local Router = core.class("Router")

local OPTION_NAMES <const> = { "trailing_slash", "automatic_head", "automatic_options" }
local METHOD_TOKEN <const> = "^[%w!#$%%&'*+%-.^_`|~]+$"

local function argument_error(message) error(core.ArgumentError("router.Router: " .. message), 3) end

local function route_error(reason, index, message, context)
  context = context or {}
  context.reason = reason
  context.index = index
  error(RouteTableError("router.Router: route " .. index .. ": " .. message, { context = context }), 3)
end

--- How a route is named in a diagnostic.
local function describe(route)
  local methods = type(route.method) == "table" and table.concat(route.method, ",") or tostring(route.method)
  return (route.name and ("%q "):format(route.name) or "") .. methods .. " " .. route.path
end

local function check_options(options)
  if options == nil then return { trailing_slash = "strict", automatic_head = true, automatic_options = true } end
  if type(options) ~= "table" then argument_error("options must be a table") end
  for key in pairs(options) do
    local known = false
    for _, name in ipairs(OPTION_NAMES) do if name == key then known = true end end
    if not known then argument_error(("unknown option %s (known: %s)"):format(tostring(key), table.concat(OPTION_NAMES, ", "))) end
  end
  local slash = options.trailing_slash or "strict"
  if slash ~= "strict" and slash ~= "ignore" then argument_error("option trailing_slash must be \"strict\" or \"ignore\"") end
  for _, flag in ipairs({ "automatic_head", "automatic_options" }) do
    if options[flag] ~= nil and type(options[flag]) ~= "boolean" then argument_error(("option %s must be a boolean"):format(flag)) end
  end
  return {
    trailing_slash = slash,
    automatic_head = options.automatic_head ~= false,
    automatic_options = options.automatic_options ~= false,
  }
end

--- The methods of a route as a list, checked: a token (RFC 9110 section 5.6.2), no repeat.
local function methods_of(route, index)
  local declared = route.method
  if type(declared) == "string" then declared = { declared } end
  if type(declared) ~= "table" or #declared == 0 then
    route_error("invalid_method", index, "method must be a string or a non-empty list of strings")
  end
  local seen = {}
  for _, method in ipairs(declared) do
    if type(method) ~= "string" or not string.find(method, METHOD_TOKEN) then
      route_error("invalid_method", index, "a method is a token of letters, digits and !#$%&'*+-.^_`|~ (RFC 9110 section 5.6.2)")
    end
    if seen[method] then route_error("invalid_method", index, ("the method %s is listed twice"):format(method)) end
    seen[method] = true
  end
  return declared
end

--- Compiles a route table. The routes are read once: later changes to `routes` are not seen. Raises
--- `hecate.router.RouteTableError` for an invalid route, a duplicate name and an ambiguous table (two routes that
--- serve the same method for the same paths), and `hecate.core.ArgumentError` for bad arguments.
---@param routes hecate.router.Route[]
---@param options? hecate.router.Options
function Router:init(routes, options)
  if type(routes) ~= "table" then argument_error("routes must be a list of route tables") end
  local settings = check_options(options)
  self._trailing_slash = settings.trailing_slash
  self._head = settings.automatic_head
  self._options = settings.automatic_options
  self._root = tree.new()
  self._routes = {}
  self._by_name = {}
  local entries = {}
  for index, route in ipairs(routes) do
    if type(route) ~= "table" then route_error("invalid_route", index, "a route is a table") end
    if route.method == nil or route.path == nil then route_error("invalid_route", index, "a route declares a method and a path") end
    if route.name ~= nil and (type(route.name) ~= "string" or route.name == "") then
      route_error("invalid_route", index, "a route name is a non-empty string")
    end
    local methods = methods_of(route, index)
    local parsed, reason, detail = template.parse(route.path, self._trailing_slash)
    if parsed == nil then
      route_error("invalid_template", index, ("invalid path template %s (%s): %s"):format(tostring(route.path), reason, detail),
        { template_reason = reason })
    end
    ---@cast parsed hecate.router.Template
    if route.name ~= nil then
      local first = self._by_name[route.name]
      if first then
        route_error("duplicate_name", index, ("the name %q is already the name of route %d (%s)"):format(
          route.name, first.index, describe(entries[first.index].route)), { other_index = first.index })
      end
      self._by_name[route.name] = { index = index, template = parsed }
    end
    local entry = { route = route, names = parsed.names, index = index }
    entries[index] = entry
    for _, method in ipairs(methods) do
      local existing = tree.insert(self._root, parsed, method, entry)
      if existing then
        route_error("ambiguous_route", index, ("%s is ambiguous with route %d (%s): both serve %s for the same paths"):format(
          describe(route), existing.index, describe(existing.route), method), { other_index = existing.index, method = method })
      end
    end
    self._routes[index] = route
  end
end

--- The methods of `set` as a sorted list, with the automatic `HEAD` and `OPTIONS` added.
local function allowed(self, set)
  if self._head and set.GET then set.HEAD = true end
  if self._options then set.OPTIONS = true end
  local list = {}
  for method in pairs(set) do list[#list + 1] = method end
  table.sort(list)
  return list
end

--- Matches a request. `raw_path` is the path component of the request target as received (`http.Request.path`: not
--- decoded, not normalised); the router decodes each segment on its own and resolves dot segments first, so `%2F` is
--- data and `/a/../b` is `/b` (RFC 3986 sections 2.1 and 5.2.4).
---
--- Returns a `Match` in every case: status 200 with the route and its parameters; 404 when no route has the path; 405
--- with `Allow` when the path exists for other methods; 204 with `Allow` for an automatic `OPTIONS`; 400 with a
--- `reason` when the path is not readable. A static route wins over a parameter route, and that over a wildcard; a
--- route that does not serve the method is skipped in favour of a lower-precedence route that does.
---
--- Raises `hecate.core.ArgumentError` when an argument is not a string or the method is empty.
---@param method string  the request method, case-sensitive
---@param raw_path string
---@return hecate.router.Match
function Router:match(method, raw_path)
  if type(method) ~= "string" or method == "" then error(core.ArgumentError("router.Router:match: method must be a non-empty string"), 2) end
  if type(raw_path) ~= "string" then error(core.ArgumentError("router.Router:match: path must be a string"), 2) end
  local segments, reason = path.split(raw_path, self._trailing_slash)
  if segments == nil then return { status = 400, reason = reason } end
  local values = {}
  local entry = tree.find(self._root, segments, method, self._head, values)
  if entry then
    local parameters = {}
    for position, name in ipairs(entry.names) do parameters[name] = values[position] end
    return { status = 200, route = entry.route, parameters = parameters }
  end
  local set = tree.methods(self._root, segments)
  if next(set) == nil then return { status = 404 } end
  local list = allowed(self, set)
  local field = table.concat(list, ", ")
  if method == "OPTIONS" and self._options then return { status = 204, allow = list, allow_field = field } end
  return { status = 405, allow = list, allow_field = field }
end

--- Reverse routing: the path of the route called `name`, with each value percent-encoded (RFC 3986 section 2.1).
--- Values are strings or integers; a wildcard takes a string whose `/` separate its segments.
---
--- Raises `hecate.core.ArgumentError` for an unknown name, a missing or unknown parameter and a value no request path
--- could carry (empty, `.`, `..`, a NUL byte).
---@param name string
---@param parameters? table<string, string|integer>
---@return string path
function Router:url_for(name, parameters)
  if type(name) ~= "string" then error(core.ArgumentError("router.Router:url_for: the route name must be a string"), 2) end
  if parameters ~= nil and type(parameters) ~= "table" then
    error(core.ArgumentError("router.Router:url_for: parameters must be a table"), 2)
  end
  local named = self._by_name[name]
  if named == nil then error(core.ArgumentError(("router.Router:url_for: no route is named %q"):format(name)), 2) end
  return template.expand(named.template, parameters)
end

--- The routes in the order they were declared: a new list of the route tables as given, which are not to be modified
--- (route table introspection, for OpenAPI generation, documentation and the CLI).
---@return hecate.router.Route[] routes
function Router:routes()
  local copy = {}
  for index, route in ipairs(self._routes) do copy[index] = route end
  return copy
end

--- The route called `name`, or nil.
---@param name string
---@return hecate.router.Route?
function Router:route(name)
  local named = self._by_name[name]
  return named and self._routes[named.index] or nil
end

return core.finalise(Router)
