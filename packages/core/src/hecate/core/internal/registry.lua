-- Internal bookkeeping of the object model. Class, trait, interface and enumeration
-- metadata lives here, in weak-keyed tables, so that the tables handed to users contain
-- only their members and method lookup stays a single table access (object-model.md,
-- requirement 7).
global <const> setmetatable

local weak = { __mode = "k" } -- hecate: raw-metatable weak registry

---@class hecate.core.internal.registry
local registry = {
  ---@type table<table, table>  class table -> class record
  classes = setmetatable({}, weak),
  ---@type table<table, table>  trait table -> trait record
  traits = setmetatable({}, weak),
  ---@type table<table, table>  interface table -> interface record
  interfaces = setmetatable({}, weak),
  ---@type table<table, table>  enumeration table -> enumeration record
  enumerations = setmetatable({}, weak),
  ---@type table<table, table>  per-instance metatable of a value object -> class table
  frozen_metatables = setmetatable({}, weak),
  ---@type table<table, table>  value object -> table holding its fields
  frozen_fields = setmetatable({}, weak),
}

return registry
