-- Controllers: the object-oriented declaration style (ADR 0006, ADR 0007). A controller is a class that derives from
-- `Controller`, with a `prefix`, `dependencies`, `filters` and route declarations naming an action method.
global <const> require, type, ipairs, pairs, rawget

local core = require("hecate.core")
local route = require("hecate.kernel.route")

--- The superclass of controllers. `prefix` and `routes` belong to the class that declares them: a subclass does not
--- inherit the prefix or the routes of its superclass (a finalised class carries copies of the members it inherits,
--- which are told apart from its own, see `own_member`). A class may also set the field `routes = { spec, ... }` (a list of route
--- declarations, read by `Controller.entries` after those of `Controller.route`; errors surface at boot, not at the line).
---@class hecate.kernel.Controller
---@field prefix? string  path prefix of every route of the class: empty, or starts with `/` and does not end with one; read from the class itself, never inherited from its superclass
---@field dependencies? table<string, string>  field name to the name of a container binding
---@field filters? hecate.kernel.Filter[]  filters of every route of the class, outermost first, before those of a route
---@field routes? hecate.kernel.RouteSpec[]  route declarations of the class, read after those of `Controller.route`; not inherited
---@overload fun(): hecate.kernel.Controller
local Controller = core.class("Controller")

--- How a value is named in a message: a class by its name, anything else by its type.
---@param value any
---@return string
local function describe(value)
  if core.is_class(value) then return "class " .. core.name(value) end
  return route.got(value)
end

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

--- The value of a member the class declares itself, nil when it only carries an inherited copy: `core.finalise`
--- flattens the members of the superclass into the class table, so `rawget` alone cannot tell them apart.
---@param class table
---@param member string
---@return any
local function own_member(class, member)
  if core.is_finalised(class) and core.origin(class, member) ~= "class " .. core.name(class) then return nil end
  return rawget(class, member)
end

-- The declarations of each class, apart from the class (a class cannot take members after it is finalised, and a
-- declaration comes before). Weak, so that a dropped class is collected. Not inherited: a subclass declares its own.
local declarations = core.weak_table("k")

--- Declares a route of a controller class. A function of the class, not a method: a class cannot answer `Class:route`
--- before it is finalised, so call `Controller.route(UserController, { ... })` (OQ-113). The declaration is validated
--- now (shape, path template, parameters, filters); that the action is a method is checked by `Controller.entries`,
--- because the methods are written after the declarations.
---
--- Raises `RouteDeclarationError`: `invalid_argument` if `class` is not a class deriving from `Controller`, and the
--- reason of the check for an invalid declaration.
---@param class table  a class deriving from `Controller`
---@param spec hecate.kernel.RouteSpec
function Controller.route(class, spec)
  if not derives(class) then
    route.refuse("hecate.kernel.controller.route", "controller " .. (core.is_class(class) and core.name(class) or "?"),
      "invalid_argument", nil, "the first argument must be a class deriving from Controller, got " .. describe(class))
  end
  local list = declarations[class]
  if list == nil then
    list = {}
    declarations[class] = list
  end
  -- Prefix and filters are read when the routes are read (the class may set them after its first declaration); the
  -- shape is validated now with the declaration as given, against the current prefix.
  local copy = {}
  if type(spec) == "table" then for key, value in pairs(spec) do copy[key] = value end else copy = spec end
  route.normalise(copy, {
    origin = "controller " .. core.name(class), prefix = own_member(class, "prefix"), controller = class,
  })
  list[#list + 1] = copy
end

--- Normalises a finalised controller class into route entries, in declaration order. Raises `RouteDeclarationError`
--- for a class that is not finalised (`invalid_controller`), a declaration that is invalid under the final prefix and
--- filters, and an action that is not a method of the class (`missing_action`).
---@param class table  a finalised class deriving from `Controller`
---@return hecate.kernel.RouteEntry[]
function Controller.entries(class)
  local where = "hecate.kernel.controller.entries"
  local origin = "controller " .. (core.is_class(class) and core.name(class) or describe(class))
  if not derives(class) then
    route.refuse(where, origin, "invalid_controller", nil, "not a controller class, got " .. describe(class))
  end
  if not core.is_finalised(class) then
    route.refuse(where, origin, "invalid_controller", nil, "the class is not finalised; call core.finalise first")
  end
  local specs = {}
  for _, spec in ipairs(declarations[class] or {}) do specs[#specs + 1] = spec end
  local field = own_member(class, "routes")
  if field ~= nil then
    if type(field) ~= "table" then
      route.refuse(where, origin, "invalid_routes", "routes",
        "`routes` must be a list of route declarations, got " .. describe(field))
    end
    for _, spec in ipairs(field) do specs[#specs + 1] = spec end
  end
  local entries = {}
  for _, spec in ipairs(specs) do
    local entry = route.normalise(spec, {
      origin = origin, prefix = own_member(class, "prefix"), filters = class.filters, controller = class,
    })
    route.check_action(entry)
    entries[#entries + 1] = entry
  end
  return entries
end

core.finalise(Controller)

return Controller
