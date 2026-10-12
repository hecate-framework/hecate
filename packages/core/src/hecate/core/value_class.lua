-- Value classes: instances are frozen after construction and compared structurally
-- (object-model.md, "Value objects and immutability").
--
-- Freezing without a cost on reads: after `init` returns, the fields move into a hidden
-- table and the instance becomes an empty proxy whose per-instance metatable has a plain
-- table `__index` (the fields table, which itself falls back to the class table). Reads
-- are table lookups only; no function runs on the read path. The price is paid once, at
-- construction (three tables per instance).
global <const> type, next, setmetatable, getmetatable, rawget, rawset, tostring, require

local registry = require("hecate.core.internal.registry")
local raise = require("hecate.core.internal.raise")
local class_module = require("hecate.core.class")

local classes = registry.classes
local frozen_fields = registry.frozen_fields
local frozen_metatables = registry.frozen_metatables

-- Metamethod keys that are never copied into a per-instance metatable.
local NOT_COPIED = { __index = true, __newindex = true, __pairs = true }

local function class_of(object)
  local metatable = getmetatable(object)
  return frozen_metatables[metatable]
end

--- Default `__eq` of value classes: same class and equal fields, compared with `==`
--- so that nested value objects compare structurally too.
local function structural_equality(a, b)
  local class = class_of(a)
  if class == nil or class ~= class_of(b) then return false end
  local fields_a, fields_b = frozen_fields[a], frozen_fields[b]
  for key, value in next, fields_a do
    if fields_b[key] ~= value then return false end
  end
  for key in next, fields_b do
    if fields_a[key] == nil then return false end
  end
  return true
end

local function frozen_write(object, key)
  local class = class_of(object)
  raise.conformance(
    ("value object of class %s is immutable; cannot set field %s"):format(classes[class].name, tostring(key)),
    { class = classes[class].name, field = tostring(key) })
end

local function frozen_pairs(object) return next, frozen_fields[object], nil end

--- Hook run at finalisation: installs the structural `__eq` unless the class defines one,
--- and snapshots the metamethods copied into every instance metatable.
local function prepare(class, record)
  if rawget(class, "__eq") == nil then rawset(class, "__eq", structural_equality) end
  local template = {}
  for key, value in next, class do
    if type(key) == "string" and key:sub(1, 2) == "__" and not NOT_COPIED[key] then template[key] = value end
  end
  record.template = template
  record.fields_metatable = { __index = class } -- hecate: raw-metatable value object fields
end

--- Hook run after `init`: moves the fields out of the instance and freezes it.
local function freeze(object, class, record)
  local fields = {}
  for key, value in next, object do fields[key] = value end
  for key in next, fields do object[key] = nil end
  setmetatable(fields, record.fields_metatable) -- hecate: raw-metatable value object fields
  local metatable = {} -- hecate: raw-metatable value object
  for key, value in next, record.template do metatable[key] = value end
  metatable.__index = fields
  metatable.__newindex = frozen_write
  metatable.__pairs = frozen_pairs
  frozen_metatables[metatable] = class
  frozen_fields[object] = fields
  setmetatable(object, metatable) -- hecate: raw-metatable value object
end

--- Declares a value class. Same signature as `core.class`; the class must be finalised.
---@param name string
---@param superclass? table  a value class
---@param options? hecate.core.ClassOptions
---@return table class
local function value_class(name, superclass, options)
  if superclass ~= nil and classes[superclass] ~= nil and classes[superclass].freeze == nil then
    raise.argument(("value class %s: superclass %s is not a value class"):format(
      tostring(name), classes[superclass].name))
  end
  local declared = class_module.class(name, superclass, options)
  local record = classes[declared]
  record.freeze = freeze
  record.prepare = prepare
  return declared
end

return { value_class = value_class }
