-- Interfaces: named sets of required methods, and optionally of required class-level fields,
-- checked when a class is finalised (object-model.md, requirement 3 and "Interface fields").
global <const> type, ipairs, setmetatable, rawequal, tostring, require

local registry = require("hecate.core.internal.registry")
local raise = require("hecate.core.internal.raise")
local validate = require("hecate.core.internal.validate")

-- Documented on `hecate.core` (module class completed here so that the LuaLS export lists the
-- function; coding-standards.md, "Annotations for the reference").

---@class hecate.core
local M = {}

local interface_metatable = { -- hecate: raw-metatable opaque handle
  __tostring = function(self) return "interface " .. registry.interfaces[self].name end,
  __newindex = function(self)
    raise.conformance(("interface %s is immutable"):format(registry.interfaces[self].name))
  end,
  __call = function(self)
    raise.conformance(("interface %s cannot be instantiated"):format(registry.interfaces[self].name))
  end,
}

--- Options of `core.interface`.
---@class hecate.core.InterfaceOptions
---@field extends? table[]  interfaces whose requirements are inherited
---@field fields? hecate.core.FieldRequirement[]  class-level members that are not functions, checked by a predicate

--- A required class-level member that is not a function (a datum such as a `status`), checked at finalisation.
---@class hecate.core.FieldRequirement
---@field name string  the member name
---@field expected string  what a valid value is, in words, for the message ("an integer from 100 to 599")
---@field check fun(value: any): boolean  true when the value of the member is acceptable

--- Declares an interface: a set of method names a class must provide to implement it, and optionally class-level
--- fields (`options.fields`) whose value must satisfy a predicate (a datum such as a `status` is not a method).
---
--- Raises `hecate.core.ArgumentError` if `name` is not a non-empty string or `methods` is not a list of names
--- (a sequence of strings, with no other key).
---@param name string  interface name, used in messages
---@param methods string[]  names of the required methods
---@param options? hecate.core.InterfaceOptions  extended interfaces
---@return table interface  the new interface
function M.interface(name, methods, options)
  validate.name("interface", name)
  if not validate.is_sequence(methods) then
    raise.argument("interface " .. name .. ": methods must be a list of names")
  end
  local record = { name = name, required = {}, order = {}, extends = {}, fields = {}, field_order = {} }
  local function add(method, origin)
    if record.required[method] == nil then
      record.required[method] = origin
      record.order[#record.order + 1] = method
    end
  end
  for _, method in ipairs(methods) do
    if type(method) ~= "string" then
      raise.argument(("interface %s: method names must be strings, got %s"):format(name, type(method)))
    end
    add(method, name)
  end
  local function add_field(field, origin)
    if record.fields[field.name] == nil then
      record.fields[field.name] = { expected = field.expected, check = field.check, origin = origin }
      record.field_order[#record.field_order + 1] = field.name
    end
  end
  local declared_fields = options and options.fields
  if declared_fields ~= nil and not validate.is_sequence(declared_fields) then
    raise.argument("interface " .. name .. ": fields must be a list of field requirements")
  end
  for _, field in ipairs(declared_fields or {}) do
    if type(field) ~= "table" or type(field.name) ~= "string" or field.name == ""
      or type(field.expected) ~= "string" or type(field.check) ~= "function" then
      raise.argument("interface " .. name .. ": a field requirement is { name, expected, check }: "
        .. "a non-empty name, a description string and a predicate function")
    end
    if record.fields[field.name] ~= nil or record.required[field.name] ~= nil then
      raise.argument(("interface %s: member %s is declared twice (as a field or as a method)"):format(name, field.name))
    end
    add_field(field, name)
  end
  for _, extended in ipairs(options and options.extends or {}) do
    local extended_record = registry.interfaces[extended]
    if not extended_record then raise.argument("interface " .. name .. ": extends expects interfaces") end
    record.extends[#record.extends + 1] = extended
    for _, method in ipairs(extended_record.order) do add(method, extended_record.required[method]) end
    for _, field_name in ipairs(extended_record.field_order) do
      local inherited = extended_record.fields[field_name]
      add_field({ name = field_name, expected = inherited.expected, check = inherited.check }, inherited.origin)
    end
  end
  local handle = setmetatable({}, interface_metatable) -- hecate: raw-metatable opaque handle
  registry.interfaces[handle] = record
  return handle
end

--- Returns true when `candidate` is `target` or extends it, directly or transitively.
---@param candidate table
---@param target table
---@return boolean
local function conforms_to(candidate, target)
  if rawequal(candidate, target) then return true end
  for _, extended in ipairs(registry.interfaces[candidate].extends) do
    if conforms_to(extended, target) then return true end
  end
  return false
end

return { interface = M.interface, conforms_to = conforms_to }
