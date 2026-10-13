-- Interfaces: named sets of required methods, checked when a class is finalised
-- (object-model.md, requirement 3).
global <const> type, ipairs, setmetatable, rawequal, tostring, require

local registry = require("hecate.core.internal.registry")
local raise = require("hecate.core.internal.raise")

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

--- Declares an interface: a set of method names a class must provide to implement it.
---
--- Raises `hecate.core.ArgumentError` if `name` is not a string or `methods` is not a list of names.
---@param name string  interface name, used in messages
---@param methods string[]  names of the required methods
---@param options? hecate.core.InterfaceOptions  extended interfaces
---@return table interface  the new interface
function M.interface(name, methods, options)
  if type(name) ~= "string" then raise.argument("interface name must be a string, got " .. type(name)) end
  if type(methods) ~= "table" then raise.argument("interface " .. name .. ": methods must be a list of names") end
  local record = { name = name, required = {}, order = {}, extends = {} }
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
  for _, extended in ipairs(options and options.extends or {}) do
    local extended_record = registry.interfaces[extended]
    if not extended_record then raise.argument("interface " .. name .. ": extends expects interfaces") end
    record.extends[#record.extends + 1] = extended
    for _, method in ipairs(extended_record.order) do add(method, extended_record.required[method]) end
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
