-- hecate.core: the single object model of Hecate (ADR 0007), the error hierarchy
-- (ADR 0018), enumerations, value classes and Lua-version shims.
global <const> ipairs, require
local class_module = require("hecate.core.class")
local trait_module = require("hecate.core.trait")
local interface_module = require("hecate.core.interface")
local introspection = require("hecate.core.introspection")
local value_module = require("hecate.core.value_class")
local enumeration_module = require("hecate.core.enumeration")
local errors = require("hecate.core.error")
local compat = require("hecate.core.compat")

--- The object model of hecate: classes, traits, interfaces, enumerations and value classes,
--- introspection, the error hierarchy and Lua-version shims.
---@class hecate.core
---@field Error hecate.core.Error
---@field ConfigurationError hecate.core.Error
---@field ConformanceError hecate.core.Error
---@field ArgumentError hecate.core.Error
---@field CancellationError hecate.core.Error
---@field DeadlineExceededError hecate.core.Error
---@field NonYieldableContextError hecate.core.Error
---@field ClosedChannelError hecate.core.Error
---@field NetworkError hecate.core.Error
---@field ProtocolError hecate.core.Error
---@field ValidationError hecate.core.Error
---@field DatabaseError hecate.core.DatabaseError
---@field compat hecate.core.compat  Lua-version shims (ADR 0001)
local core = {
  Error = errors.Error --[[@as hecate.core.Error]],
  compat = compat,
}
core.class = class_module.class
core.finalise = class_module.finalise
core.value_class = value_module.value_class
core.enumeration = enumeration_module.enumeration
core.trait = trait_module.trait
core.interface = interface_module.interface
core.is_class = introspection.is_class
core.is_trait = introspection.is_trait
core.is_enumeration = introspection.is_enumeration
core.is_interface = introspection.is_interface
core.is_finalised = introspection.is_finalised
core.class_of = introspection.class_of
core.name = introspection.name
core.superclass = introspection.superclass
core.traits = introspection.traits
core.interfaces = introspection.interfaces
core.is_instance_of = introspection.is_instance_of
core.implements = introspection.implements
core.origin = introspection.origin
core.error_class = errors.error_class
core.set_debug_mode = errors.set_debug_mode
core.is_debug_mode = errors.is_debug_mode

for _, name in ipairs({
  "ConfigurationError", "ConformanceError", "ArgumentError", "CancellationError",
  "DeadlineExceededError", "NonYieldableContextError", "ClosedChannelError", "NetworkError", "ProtocolError", "ValidationError", "DatabaseError",
}) do
  ---@diagnostic disable-next-line: assign-type-mismatch  -- error classes are constructors exported as their class
  core[name] = errors[name]
end

return core
