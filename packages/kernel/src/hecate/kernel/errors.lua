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

--- An application composition the kernel refuses at boot. `context.reason` is the stable identifier: `invalid_module`,
--- `duplicate_module`, `missing_dependency` (a module requires one that is not registered), `dependency_cycle`
--- (`context.cycle` lists the module names) and `already_booted`. `context.module` names the faulty module.
---@class hecate.kernel.ModuleError : hecate.core.ConfigurationError
---@field context { reason: string, module?: string, cycle?: string[] }
local ModuleError = core.error_class("ModuleError", "hecate.kernel.ModuleError", core.ConfigurationError)

--- The supervisor of the workers stopped on a failure (ADR 0023). `context.reason` is the stable identifier:
--- `crash_loop` (workers kept exiting: `crash_limit` exits within `crash_window`), `start_failed` (the worker program
--- cannot be started), `already_run`, and for `Supervisor:reload`: `reload_failed` (`context.cause`: `start_failed`,
--- `exited`, `not_ready`, `worker_lost` or `stopping`; `context.worker` the slot), `reload_in_progress`, `stopping` and
--- `not_running`.
---@class hecate.kernel.SupervisorError : hecate.core.Error
---@field context { reason: string, cause?: string, worker?: integer }
local SupervisorError = core.error_class("SupervisorError", "hecate.kernel.SupervisorError", core.Error)

return { RouteDeclarationError = RouteDeclarationError, ModuleError = ModuleError, SupervisorError = SupervisorError }
