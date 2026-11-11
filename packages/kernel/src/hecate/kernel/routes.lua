-- Route modules: the lightweight declaration style (ADR 0006). `hecate.routes(name)` returns an object whose verbs
-- declare routes taking an action function; the normalised route list is read back with `RouteModule:routes()`.
global <const> require, type, error, ipairs, pairs, string, tostring, table

local core = require("hecate.core")
local route = require("hecate.kernel.route")

--- A route module: a named list of route declarations. Each verb validates its declaration at once, so a mistake is
--- reported where it is written.
---@class hecate.kernel.RouteModule
---@field name string
---@field private _entries hecate.kernel.RouteEntry[]
---@field private _prefix? string
---@field private _filters? hecate.kernel.Filter[]
---@field private _pending table<table, string>  curried verbs whose table of declarations is not given yet
---@field get fun(self: hecate.kernel.RouteModule, path: string, spec?: hecate.kernel.RouteSpec): hecate.kernel.RouteModule|fun(spec: hecate.kernel.RouteSpec): hecate.kernel.RouteModule
---@field post fun(self: hecate.kernel.RouteModule, path: string, spec?: hecate.kernel.RouteSpec): hecate.kernel.RouteModule|fun(spec: hecate.kernel.RouteSpec): hecate.kernel.RouteModule
---@field put fun(self: hecate.kernel.RouteModule, path: string, spec?: hecate.kernel.RouteSpec): hecate.kernel.RouteModule|fun(spec: hecate.kernel.RouteSpec): hecate.kernel.RouteModule
---@field patch fun(self: hecate.kernel.RouteModule, path: string, spec?: hecate.kernel.RouteSpec): hecate.kernel.RouteModule|fun(spec: hecate.kernel.RouteSpec): hecate.kernel.RouteModule
---@field delete fun(self: hecate.kernel.RouteModule, path: string, spec?: hecate.kernel.RouteSpec): hecate.kernel.RouteModule|fun(spec: hecate.kernel.RouteSpec): hecate.kernel.RouteModule
---@field head fun(self: hecate.kernel.RouteModule, path: string, spec?: hecate.kernel.RouteSpec): hecate.kernel.RouteModule|fun(spec: hecate.kernel.RouteSpec): hecate.kernel.RouteModule
---@field options fun(self: hecate.kernel.RouteModule, path: string, spec?: hecate.kernel.RouteSpec): hecate.kernel.RouteModule|fun(spec: hecate.kernel.RouteSpec): hecate.kernel.RouteModule
---@overload fun(name: string, options?: hecate.kernel.RouteModuleOptions): hecate.kernel.RouteModule
local RouteModule = core.class("RouteModule")

--- Options of a route module.
---@class hecate.kernel.RouteModuleOptions
---@field prefix? string  prepended to the path of every route, same rule as a controller prefix
---@field filters? hecate.kernel.Filter[]  the DEFAULT filters of each route: a route that declares `filters` (even an empty list) replaces them

local OPTION_FIELDS <const> = { prefix = true, filters = true }

--- Creates a route module. `name` is a non-empty string, used in diagnostics. `options.prefix` is prepended to every
--- route (the default route name includes it). `options.filters` are the default filters of each route: they are not
--- a layer of the chain, a route that declares its own `filters` replaces them (an empty list removes them), unlike
--- the filters of a controller, which always come before those of the route.
---
--- Raises `hecate.core.ArgumentError` for a bad `name` and `RouteDeclarationError` for a bad option.
---@param name string
---@param options? hecate.kernel.RouteModuleOptions
function RouteModule:init(name, options)
  if type(name) ~= "string" or name == "" then
    error(core.ArgumentError("kernel.routes: the name of a route module is a non-empty string"), 3)
  end
  self.name = name
  self._entries = {}
  self._pending = {}
  local origin = "route module " .. name
  if options ~= nil then
    if type(options) ~= "table" then
      route.refuse(origin, "invalid_options", nil, "the options of a route module are a table")
    end
    for key in pairs(options) do
      if type(key) ~= "string" or not OPTION_FIELDS[key] then
        route.refuse(origin, "unknown_field", tostring(key), "unknown option " .. tostring(key) .. " (prefix, filters)")
      end
    end
    if options.prefix ~= nil then
      if type(options.prefix) ~= "string" then
        route.refuse(origin, "invalid_path", "prefix", "prefix must be a string, got " .. type(options.prefix))
      end
      route.check_prefix(origin, options.prefix)
      self._prefix = options.prefix
    end
    if options.filters ~= nil then
      self._filters = route.check_filters(origin, options.filters, "the default filters")
    end
  end
end

local function declare(self, method, path, spec)
  if type(path) ~= "string" then
    error(core.ArgumentError(("route module %s: %s expects a path string, got %s"):format(self.name, method, type(path))), 3)
  end
  if type(spec) ~= "table" then
    error(core.ArgumentError(("route module %s: %s %s expects a table of declarations"):format(self.name, method, path)), 3)
  end
  -- `route.normalise` reads `path` from the spec: the verb gives it, the table must not repeat it.
  local copy = { path = path }
  for key, value in pairs(spec) do
    if key == "path" or key == "method" then
      error(core.ArgumentError(("route module %s: %s %s: %s is given by the verb"):format(self.name, method, path,
        tostring(key))), 3)
    end
    copy[key] = value
  end
  -- The module defaults apply when the route declares no list; a declared list (even empty) replaces them.
  if copy.filters == nil and self._filters ~= nil then
    local defaults = {}
    for index, filter in ipairs(self._filters) do defaults[index] = filter end
    copy.filters = defaults
  end
  local entries = self._entries
  entries[#entries + 1] = route.normalise(copy, {
    origin = "route module " .. self.name, method = method, prefix = self._prefix,
  })
  return self
end

for _, method in ipairs(route.METHODS) do
  --- Declares a route. Both spellings are the same: `module:get("/x", { ... })` and `module:get "/x" { ... }`.
  RouteModule[string.lower(method)] = function(self, path, spec)
    if spec ~= nil then return declare(self, method, path, spec) end
    -- `module:get "/x"` alone would drop the route silently: remember it until its declarations are given.
    local token = {}
    self._pending[token] = method .. " " .. tostring(path)
    return function(declared)
      self._pending[token] = nil
      return declare(self, method, path, declared)
    end
  end
end

--- The normalised route list, in declaration order. A new list on each call; the entries are shared.
---
--- Raises `RouteDeclarationError` with reason `incomplete_route` when a verb was called without its table of
--- declarations (`module:get "/x"` alone), so the mistake is reported at boot instead of dropping the route.
---@return hecate.kernel.RouteEntry[]
function RouteModule:routes()
  local incomplete = {}
  for _, label in pairs(self._pending) do incomplete[#incomplete + 1] = label end
  if #incomplete > 0 then
    table.sort(incomplete)
    route.refuse("route module " .. self.name, "incomplete_route", nil, "route " .. table.concat(incomplete, ", ")
      .. " has no table of declarations (write module:get \"/x\" { ... })")
  end
  local list = {}
  for index, entry in ipairs(self._entries) do list[index] = entry end
  return list
end

core.finalise(RouteModule)

return RouteModule
