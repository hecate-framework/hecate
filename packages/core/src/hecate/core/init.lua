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
local weak_module = require("hecate.core.weak")

--- The object model of hecate: classes, traits, interfaces, enumerations and value classes,
--- introspection, the error hierarchy and Lua-version shims.
---@class hecate.core
---@field Error hecate.core.Error
---@field ConfigurationError hecate.core.ConfigurationError
---@field ConformanceError hecate.core.ConformanceError
---@field PreconditionError hecate.core.PreconditionError
---@field ArgumentError hecate.core.ArgumentError
---@field StateError hecate.core.StateError
---@field CancellationError hecate.core.CancellationError
---@field DeadlineExceededError hecate.core.DeadlineExceededError
---@field NonYieldableContextError hecate.core.NonYieldableContextError
---@field ClosedChannelError hecate.core.ClosedChannelError
---@field NetworkError hecate.core.NetworkError
---@field IoError hecate.core.IoError
---@field ProtocolError hecate.core.ProtocolError
---@field ValidationError hecate.core.ValidationError
---@field DatabaseError hecate.core.DatabaseError
---@field compat hecate.core.compat  Lua-version shims (ADR 0001)
local core = {
  Error = errors.Error --[[@as hecate.core.Error]],
  compat = compat,
}
core.class = class_module.class
core.finalise = class_module.finalise
core.allocate = class_module.allocate
core.instantiate_value = class_module.instantiate_value
core.weak_table = weak_module.weak_table
core.value_class = value_module.value_class
core.enumeration = enumeration_module.enumeration
core.trait = trait_module.trait
core.interface = interface_module.interface
core.is_class = introspection.is_class
core.is_value_class = introspection.is_value_class
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
  "ConfigurationError", "ConformanceError", "PreconditionError", "ArgumentError", "StateError", "CancellationError",
  "DeadlineExceededError", "NonYieldableContextError", "ClosedChannelError", "NetworkError", "IoError", "ProtocolError", "ValidationError", "DatabaseError",
}) do
  ---@diagnostic disable-next-line: assign-type-mismatch  -- error classes are constructors exported as their class
  core[name] = errors[name]
end

return core
