-- The route table of an application: the route entries of all its route modules and controllers, in one flat list.
global <const> require, type, error, ipairs, pairs, tostring

local core = require("hecate.core")
local RouteModule = require("hecate.kernel.routes")
local Controller = require("hecate.kernel.controller")
local errors = require("hecate.kernel.errors")

--- Gathers the route entries of an application.
---@class hecate.kernel.routing
local routing = {}

--- Gathers the normalised route entries of `sources`, each a route module or a controller class, in the order given.
--- The result is a valid `hecate.router.Route[]`. Duplicate names and ambiguous routes are refused by
--- `hecate.router.Router`, which compiles the table; this function does not repeat that check.
---
--- With `module_filters` (the filters of the feature module that owns `sources`), each entry is a shallow copy tagged
--- with them (`entry.module_filters`), so that the dispatcher composes them as the second layer of that route and of no
--- other (global, module, controller, route). The entries of the route module itself are never modified: the same
--- route module may be gathered twice.
---
--- Raises `RouteDeclarationError` (`invalid_source`) for a source that is neither, `hecate.core.ArgumentError` for a
--- `module_filters` that is not a list, and the errors of `Controller.entries`.
---@param sources (hecate.kernel.RouteModule|table)[]
---@param module_filters? hecate.kernel.Filter[]  the filters of the owning feature module
---@return hecate.kernel.RouteEntry[]
function routing.collect(sources, module_filters)
  if type(sources) ~= "table" then error(core.ArgumentError("hecate.kernel.routing.collect: sources must be a list, got " .. type(sources)), 2) end
  if module_filters ~= nil and type(module_filters) ~= "table" then
    error(core.ArgumentError("hecate.kernel.routing.collect: module_filters must be a list of filters, got " .. type(module_filters)), 2)
  end
  local tag = module_filters ~= nil and #module_filters > 0
  local entries = {}
  for index, source in ipairs(sources) do
    local list
    if core.is_instance_of(source, RouteModule) then
      list = source:routes()
    elseif core.is_class(source) then
      list = Controller.entries(source)
    else
      error(errors.RouteDeclarationError(
        ("hecate.kernel.routing.collect: sources[%d] is neither a route module nor a controller class, got %s"):format(index, type(source)),
        { context = { reason = "invalid_source", origin = "sources[" .. index .. "]" } }))
    end
    for _, entry in ipairs(list) do
      local gathered = entry
      if tag then
        gathered = {}
        for key, value in pairs(entry) do gathered[key] = value end
        gathered.module_filters = module_filters
      end
      entries[#entries + 1] = gathered
    end
  end
  return entries
end

return routing
