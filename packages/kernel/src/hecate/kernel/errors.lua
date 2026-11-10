-- The error classes of the kernel.
global <const> require

local core = require("hecate.core")

--- A route declaration the kernel refuses, at declaration or at boot, with a precise diagnostic. `context.reason` is
--- the stable identifier: `unknown_field`, `invalid_method`, `invalid_path`, `invalid_name`, `invalid_text`,
--- `invalid_tags`, `invalid_deprecated`, `invalid_parameters`, `parameter_mismatch` (the path template and
--- `parameters.path` disagree), `invalid_content`, `invalid_responses`, `invalid_security`, `invalid_filters`,
--- `invalid_action`, `missing_action` (a controller has no such method), `invalid_controller` and `invalid_source`.
--- `context.origin` names the route module or controller; `context.field` the offending field when there is one.
---@class hecate.kernel.RouteDeclarationError : hecate.core.ConfigurationError
---@field context { reason: string, origin?: string, field?: string }
local RouteDeclarationError = core.error_class("RouteDeclarationError", "hecate.kernel.RouteDeclarationError",
  core.ConfigurationError)

return { RouteDeclarationError = RouteDeclarationError }
