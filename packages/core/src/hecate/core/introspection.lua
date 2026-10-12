-- Introspection used by the container, the kernel, the ORM and the documentation
-- generator (object-model.md, requirement 6).
global <const> type, ipairs, getmetatable, rawequal, table, require

local registry = require("hecate.core.internal.registry")
local raise = require("hecate.core.internal.raise")
local interface_module = require("hecate.core.interface")
local trait_module = require("hecate.core.trait")

---@class hecate.core.introspection
local introspection = {}

--- Returns true when `value` is a class created with `core.class`.
---@param value any
---@return boolean
function introspection.is_class(value)
  return type(value) == "table" and registry.classes[value] ~= nil
end

--- Returns true when `value` is a trait created with `core.trait`.
---@param value any
---@return boolean
function introspection.is_trait(value)
  return type(value) == "table" and registry.traits[value] ~= nil
end

--- Returns true when `value` is an interface created with `core.interface`.
---@param value any
---@return boolean
function introspection.is_interface(value)
  return type(value) == "table" and registry.interfaces[value] ~= nil
end

--- Returns true when `value` is an enumeration created with `core.enumeration`.
---@param value any
---@return boolean
function introspection.is_enumeration(value)
  return type(value) == "table" and registry.enumerations[value] ~= nil
end

--- Returns true when the class has been finalised.
---@param class table
---@return boolean
function introspection.is_finalised(class)
  local record = registry.classes[class]
  if record == nil then raise.argument("is_finalised expects a class") end
  return record.finalised
end

--- Returns the class of an object, or nil when `value` is not an instance of a class.
---@param value any
---@return table?
function introspection.class_of(value)
  if type(value) ~= "table" then return nil end
  local metatable = getmetatable(value)
  if metatable == nil then return nil end
  if registry.classes[metatable] ~= nil then return metatable end
  return registry.frozen_metatables[metatable]
end

--- Returns the name of a class, trait, interface or enumeration, or of an instance's class.
---@param value any
---@return string
function introspection.name(value)
  if type(value) == "table" then
    local record = registry.classes[value] or registry.traits[value] or registry.interfaces[value]
      or registry.enumerations[value]
    if record then return record.name end
    local class = introspection.class_of(value)
    if class then return registry.classes[class].name end
  end
  raise.argument("name expects a class, trait, interface, enumeration or instance, got " .. type(value))
  return ""
end

--- Returns the superclass of a class, or nil for a root class.
---@param class table
---@return table?
function introspection.superclass(class)
  local record = registry.classes[class]
  if record == nil then raise.argument("superclass expects a class") end
  return record.parent
end

local function copy_list(list)
  local copy = {}
  for i, v in ipairs(list) do copy[i] = v end
  return copy
end

--- Returns the traits composed directly into a class, in declaration order (a copy).
---@param class table
---@return table[]
function introspection.traits(class)
  local record = registry.classes[class]
  if record == nil then raise.argument("traits expects a class") end
  local list = {}
  for i, entry in ipairs(record.uses) do list[i] = trait_module.normalise("class", entry) end
  return list
end

--- Returns the interfaces a class declares directly, in declaration order (a copy).
---@param class table
---@return table[]
function introspection.interfaces(class)
  local record = registry.classes[class]
  if record == nil then raise.argument("interfaces expects a class") end
  return copy_list(record.interfaces)
end

--- Returns true when `value` is an instance of `class` or of one of its subclasses.
---@param value any
---@param class table
---@return boolean
function introspection.is_instance_of(value, class)
  local current = introspection.class_of(value)
  while current ~= nil do
    if rawequal(current, class) then return true end
    current = registry.classes[current].parent
  end
  return false
end

--- Returns true when a class (or the class of an instance) conforms to an interface or
--- composes a trait, directly, through a superclass, or through composed traits and
--- extended interfaces.
---@param subject any  a class or an instance
---@param abstraction table  an interface or a trait
---@return boolean
function introspection.implements(subject, abstraction)
  local is_interface = registry.interfaces[abstraction] ~= nil
  if not is_interface and registry.traits[abstraction] == nil then
    raise.argument("implements expects an interface or a trait")
  end
  local current = registry.classes[subject] and subject or introspection.class_of(subject)
  while current ~= nil do
    local record = registry.classes[current]
    if is_interface then
      for _, declared in ipairs(record.interfaces) do
        if interface_module.conforms_to(declared, abstraction) then return true end
      end
    else
      for _, entry in ipairs(record.uses) do
        if trait_module.composes(trait_module.normalise("class", entry), abstraction) then return true end
      end
    end
    current = record.parent
  end
  return false
end

--- Returns where a member of a finalised class comes from ("class A", "trait T"), or nil.
---@param class table
---@param member string
---@return string?
function introspection.origin(class, member)
  local record = registry.classes[class]
  if record == nil then raise.argument("origin expects a class") end
  return record.origins[member]
end

return introspection
