-- The route table of an application: the route entries of all its route modules and controllers, in one flat list.
global <const> require, type, error, ipairs, tostring

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
--- Raises `RouteDeclarationError` (`invalid_source`) for a source that is neither, and the errors of
--- `Controller.routes`.
---@param sources (hecate.kernel.RouteModule|table)[]
---@return hecate.kernel.RouteEntry[]
function routing.collect(sources)
  if type(sources) ~= "table" then error(core.ArgumentError("kernel.routing.collect: sources is a list"), 2) end
  local entries = {}
  for index, source in ipairs(sources) do
    local list
    if core.is_instance_of(source, RouteModule) then
      list = source:routes()
    elseif core.is_class(source) then
      list = Controller.routes(source)
    else
      error(errors.RouteDeclarationError(
        ("kernel: sources[%d] is neither a route module nor a controller class (%s)"):format(index, type(source)),
        { context = { reason = "invalid_source", origin = "sources[" .. index .. "]" } }))
    end
    for _, entry in ipairs(list) do entries[#entries + 1] = entry end
  end
  return entries
end

return routing
