-- Enumerations: closed sets of named values (object-model.md, "Enumerations").
global <const> type, ipairs, next, setmetatable, tostring, require

local registry = require("hecate.core.internal.registry")
local raise = require("hecate.core.internal.raise")
local class_module = require("hecate.core.class")
local value_module = require("hecate.core.value_class")

-- Documented on `hecate.core` (module class completed here so that the LuaLS export lists the
-- function; coding-standards.md, "Annotations for the reference").

---@class hecate.core
local M = {}

-- Names of the operations of an enumeration; a value cannot take one of them.
local RESERVED = { values = true, names = true, contains = true, find = true, size = true, __name = true }

--- A value of an enumeration: a name and an ordinal.
---@class hecate.core.EnumerationValue
---@field name string
---@field ordinal integer  position in the declaration, from 1
---@field enumeration string  name of the enumeration

local EnumerationValue = value_module.value_class("EnumerationValue")

---@param name string
---@param ordinal integer
---@param enumeration string
function EnumerationValue:init(name, ordinal, enumeration)
  self.name, self.ordinal, self.enumeration = name, ordinal, enumeration
end

function EnumerationValue:__tostring() return self.name end

class_module.finalise(EnumerationValue)

--- Declares an enumeration: a closed set of values with membership tests.
--- Values are read as fields (`Status.active`); the enumeration itself is immutable.
---
--- Raises `hecate.core.ArgumentError` if `name` is not a non-empty string or `names` is empty.
---@param name string  enumeration name, used in messages
---@param names string[]  value names, in declaration order
---@return table enumeration  the new enumeration
function M.enumeration(name, names)
  if type(name) ~= "string" or name == "" then
    raise.argument("enumeration name must be a non-empty string, got " .. tostring(name))
  end
  if type(names) ~= "table" or #names == 0 then
    raise.argument(("enumeration %s: expects a non-empty list of value names"):format(name))
  end
  local record = { name = name, order = {}, values = {}, set = {} }
  for ordinal, value_name in ipairs(names) do
    if type(value_name) ~= "string" or value_name == "" then
      raise.argument(("enumeration %s: value names must be non-empty strings, got %s"):format(
        name, tostring(value_name)))
    end
    if RESERVED[value_name] then
      raise.argument(("enumeration %s: %s is reserved for an operation of enumerations"):format(
        name, value_name))
    end
    if record.values[value_name] ~= nil then
      raise.argument(("enumeration %s: duplicate value %s"):format(name, value_name))
    end
    local value = EnumerationValue(value_name, ordinal, name)
    record.order[ordinal] = value
    record.values[value_name] = value
    record.set[value] = true
  end

  -- `lookup` holds the values and the operations; the enumeration is an empty proxy over
  -- it, so reading a value is a plain table access and the set cannot be modified.
  local lookup = { __name = name }
  for value_name, value in next, record.values do lookup[value_name] = value end
  local count = #record.order

  ---@return hecate.core.EnumerationValue[]
  function lookup.values()
    local copy = {}
    for i, value in ipairs(record.order) do copy[i] = value end
    return copy
  end
  ---@return string[]
  function lookup.names()
    local copy = {}
    for i, value in ipairs(record.order) do copy[i] = value.name end
    return copy
  end
  ---@return boolean
  function lookup.contains(_, candidate) return record.set[candidate] == true end
  ---@return hecate.core.EnumerationValue?
  function lookup.find(_, value_name)
    if type(value_name) ~= "string" then return nil end
    return record.values[value_name]
  end
  ---@return integer
  function lookup.size() return count end

  local proxy = {}
  registry.enumerations[proxy] = record
  setmetatable(proxy, { -- hecate: raw-metatable enumeration proxy
    __index = lookup,
    __newindex = function(_, key)
      raise.conformance(("enumeration %s is closed; cannot set %s"):format(name, tostring(key)),
        { enumeration = name })
    end,
    __len = function() return count end,
    __pairs = function()
      local i = 0
      return function()
        i = i + 1
        local value = record.order[i]
        if value then return value.name, value end
        return nil
      end, proxy, nil
    end,
    __tostring = function() return "enumeration " .. name end,
  })
  return proxy
end

return { enumeration = M.enumeration, EnumerationValue = EnumerationValue }
