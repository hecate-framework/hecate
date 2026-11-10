-- Route modules: the lightweight declaration style (ADR 0006). `hecate.routes(name)` returns an object whose verbs
-- declare routes taking an action function; the normalised route list is read back with `RouteModule:routes()`.
global <const> require, type, error, ipairs, pairs, string, tostring

local core = require("hecate.core")
local route = require("hecate.kernel.route")

--- A route module: a named list of route declarations. Each verb validates its declaration at once, so a mistake is
--- reported where it is written.
---@class hecate.kernel.RouteModule
---@field name string
---@field private _entries hecate.kernel.RouteEntry[]
---@field get fun(self: hecate.kernel.RouteModule, path: string, spec?: hecate.kernel.RouteSpec): hecate.kernel.RouteModule|fun(spec: hecate.kernel.RouteSpec): hecate.kernel.RouteModule
---@field post fun(self: hecate.kernel.RouteModule, path: string, spec?: hecate.kernel.RouteSpec): hecate.kernel.RouteModule|fun(spec: hecate.kernel.RouteSpec): hecate.kernel.RouteModule
---@field put fun(self: hecate.kernel.RouteModule, path: string, spec?: hecate.kernel.RouteSpec): hecate.kernel.RouteModule|fun(spec: hecate.kernel.RouteSpec): hecate.kernel.RouteModule
---@field patch fun(self: hecate.kernel.RouteModule, path: string, spec?: hecate.kernel.RouteSpec): hecate.kernel.RouteModule|fun(spec: hecate.kernel.RouteSpec): hecate.kernel.RouteModule
---@field delete fun(self: hecate.kernel.RouteModule, path: string, spec?: hecate.kernel.RouteSpec): hecate.kernel.RouteModule|fun(spec: hecate.kernel.RouteSpec): hecate.kernel.RouteModule
---@field head fun(self: hecate.kernel.RouteModule, path: string, spec?: hecate.kernel.RouteSpec): hecate.kernel.RouteModule|fun(spec: hecate.kernel.RouteSpec): hecate.kernel.RouteModule
---@field options fun(self: hecate.kernel.RouteModule, path: string, spec?: hecate.kernel.RouteSpec): hecate.kernel.RouteModule|fun(spec: hecate.kernel.RouteSpec): hecate.kernel.RouteModule
---@overload fun(name: string): hecate.kernel.RouteModule
local RouteModule = core.class("RouteModule")

--- Creates a route module. `name` is a non-empty string, used in diagnostics.
---@param name string
function RouteModule:init(name)
  if type(name) ~= "string" or name == "" then
    error(core.ArgumentError("kernel.routes: the name of a route module is a non-empty string"), 3)
  end
  self.name = name
  self._entries = {}
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
  local entries = self._entries
  entries[#entries + 1] = route.normalise(copy, { origin = "route module " .. self.name, method = method })
  return self
end

for _, method in ipairs(route.METHODS) do
  --- Declares a route. Both spellings are the same: `module:get("/x", { ... })` and `module:get "/x" { ... }`.
  RouteModule[string.lower(method)] = function(self, path, spec)
    if spec ~= nil then return declare(self, method, path, spec) end
    return function(declared) return declare(self, method, path, declared) end
  end
end

--- The normalised route list, in declaration order. A new list on each call; the entries are shared.
---@return hecate.kernel.RouteEntry[]
function RouteModule:routes()
  local list = {}
  for index, entry in ipairs(self._entries) do list[index] = entry end
  return list
end

core.finalise(RouteModule)

return RouteModule
