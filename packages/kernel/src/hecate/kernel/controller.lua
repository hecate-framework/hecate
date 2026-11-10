-- Controllers: the object-oriented declaration style (ADR 0006, ADR 0007). A controller is a class that derives from
-- `Controller`, with a `prefix`, `dependencies`, `filters` and route declarations naming an action method.
global <const> require, type, error, ipairs, rawget, tostring

local core = require("hecate.core")
local route = require("hecate.kernel.route")
local errors = require("hecate.kernel.errors")

--- The superclass of controllers. A class may also set the field `routes = { spec, ... }` (a list of route
--- declarations, read by `Controller.routes` after those of `Controller.route`; errors surface at boot, not at the line).
--- It is not annotated as a field because `Controller.routes` is the function that reads it.
---@class hecate.kernel.Controller
---@field prefix? string  path prefix of every route of the class: empty, or starts with `/` and does not end with one
---@field dependencies? table<string, string>  field name to the name of a container binding
---@field filters? hecate.kernel.Filter[]  filters of every route of the class, outermost first, before those of a route
---@overload fun(): hecate.kernel.Controller
local Controller = core.class("Controller")

--- Tells whether a value is a class deriving from `Controller`.
local function derives(class)
  if not core.is_class(class) then return false end
  local current = core.superclass(class)
  while current ~= nil do
    if current == Controller then return true end
    current = core.superclass(current)
  end
  return false
end

-- The declarations of each class, apart from the class (a class cannot take members after it is finalised, and a
-- declaration comes before). Weak, so that a dropped class is collected. Not inherited: a subclass declares its own.
local declarations = core.weak_table("k")

--- Declares a route of a controller class. A function of the class, not a method: a class cannot answer `Class:route`
--- before it is finalised, so call `Controller.route(UserController, { ... })` (OQ-113). The declaration is validated
--- now (shape, path template, parameters, filters); that the action is a method is checked by `Controller.routes`,
--- because the methods are written after the declarations.
---
--- Raises `hecate.core.ArgumentError` if `class` is not a class deriving from `Controller` and
--- `RouteDeclarationError` for an invalid declaration.
---@param class table  a class deriving from `Controller`
---@param spec hecate.kernel.RouteSpec
function Controller.route(class, spec)
  if not derives(class) then
    error(core.ArgumentError("Controller.route: the first argument is a class deriving from Controller"), 2)
  end
  local list = declarations[class]
  if list == nil then
    list = {}
    declarations[class] = list
  end
  -- Prefix and filters are read when the routes are read (the class may set them after its first declaration); the
  -- shape is validated now with the declaration as given, against the current prefix.
  route.normalise(spec, {
    origin = "controller " .. core.name(class), prefix = rawget(class, "prefix"), controller = class,
  })
  list[#list + 1] = spec
end

--- Normalises a finalised controller class into route entries, in declaration order. Raises `RouteDeclarationError`
--- for a class that is not finalised (`invalid_controller`), a declaration that is invalid under the final prefix and
--- filters, and an action that is not a method of the class (`missing_action`).
---@param class table  a finalised class deriving from `Controller`
---@return hecate.kernel.RouteEntry[]
function Controller.routes(class)
  local origin = "controller " .. (core.is_class(class) and core.name(class) or tostring(class))
  if not derives(class) then
    error(errors.RouteDeclarationError("kernel: " .. origin .. ": not a controller class",
      { context = { reason = "invalid_controller", origin = origin } }))
  end
  if not core.is_finalised(class) then
    error(errors.RouteDeclarationError("kernel: " .. origin .. ": the class is not finalised; call core.finalise first",
      { context = { reason = "invalid_controller", origin = origin } }))
  end
  local specs = {}
  for _, spec in ipairs(declarations[class] or {}) do specs[#specs + 1] = spec end
  local field = rawget(class, "routes")
  -- A finalised class may carry the members it inherits: the method of `Controller`, or the list of a superclass.
  local parent = core.superclass(class)
  if field == Controller.routes or (parent ~= nil and field == rawget(parent, "routes")) then field = nil end
  if field ~= nil then
    if type(field) ~= "table" then
      error(errors.RouteDeclarationError("kernel: " .. origin .. ": `routes` is a list of route declarations",
        { context = { reason = "invalid_routes", origin = origin } }))
    end
    for _, spec in ipairs(field) do specs[#specs + 1] = spec end
  end
  local entries = {}
  for _, spec in ipairs(specs) do
    local entry = route.normalise(spec, {
      origin = origin, prefix = class.prefix, filters = class.filters, controller = class,
    })
    route.check_action(entry)
    entries[#entries + 1] = entry
  end
  return entries
end

core.finalise(Controller)

return Controller
