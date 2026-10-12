-- hecate.core: the single object model of Hecate (ADR 0007), the error hierarchy
-- (ADR 0018), enumerations, value classes and Lua-version shims.
global <const> ipairs, require
local class_module = require("hecate.core.class")
local trait_module = require("hecate.core.trait")
local interface_module = require("hecate.core.interface")
local introspection = require("hecate.core.introspection")
local errors = require("hecate.core.error")
local compat = require("hecate.core.compat")

---@class hecate.core
local core = {
  class = class_module.class,
  finalise = class_module.finalise,
  trait = trait_module.trait,
  interface = interface_module.interface,
  is_class = introspection.is_class,
  is_trait = introspection.is_trait,
  is_interface = introspection.is_interface,
  is_finalised = introspection.is_finalised,
  class_of = introspection.class_of,
  name = introspection.name,
  superclass = introspection.superclass,
  traits = introspection.traits,
  interfaces = introspection.interfaces,
  is_instance_of = introspection.is_instance_of,
  implements = introspection.implements,
  origin = introspection.origin,
  Error = errors.Error,
  error_class = errors.error_class,
  set_debug_mode = errors.set_debug_mode,
  is_debug_mode = errors.is_debug_mode,
  compat = compat,
}

for _, name in ipairs({
  "ConfigurationError", "ConformanceError", "ArgumentError", "CancellationError",
  "DeadlineExceeded", "NetworkError", "ProtocolError", "ValidationError", "DatabaseError",
}) do
  core[name] = errors[name]
end

return core
