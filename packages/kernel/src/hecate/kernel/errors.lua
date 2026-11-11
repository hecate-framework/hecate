-- The error classes of the kernel. Each carries a stable `context.reason`, and its `code` is the code of the class
-- followed by the reason: `hecate.kernel.RouteDeclarationError.invalid_path` (object-model.md, "Errors"; ADR 0018).
-- An application matches on `code` for one precise failure and on the class for the family.
global <const> require, type

local core = require("hecate.core")

--- Declares a kernel error class: a subclass of `superclass` whose instances take, from `context.reason`, the code
--- `<class code>.<reason>`. An explicit `code` given at construction wins; an error with no reason keeps the class code.
---@param name string
---@param superclass table
---@return table class
local function declare(name, superclass)
  local class = core.class(name, superclass)
  class.code = "hecate.kernel." .. name
  function class:init(fields, extra)
    superclass.init(self, fields, extra)
    local reason = self.context.reason
    -- `code` is a member of the class until an instance sets its own: only the class code is refined.
    if type(reason) == "string" and self.code == class.code then self.code = class.code .. "." .. reason end
  end
  return core.finalise(class)
end

--- A route declaration the kernel refuses, at declaration or at boot, with a precise diagnostic. `context.reason` is
--- the stable identifier (and the end of `code`: `hecate.kernel.RouteDeclarationError.<reason>`):
---
--- - `invalid_argument`: an argument of a declaring function is of the wrong type (`context.field` names it when it
---   is a field);
--- - `invalid_options`: the options of a route module are not a table;
--- - `unknown_field`: a declaration or an option has a field the kernel does not know;
--- - `invalid_method`, `invalid_path` (also a malformed `prefix`), `invalid_name`, `invalid_text`, `invalid_tags`,
---   `invalid_deprecated`, `invalid_parameters`, `invalid_content`, `invalid_responses`, `invalid_security`,
---   `invalid_filters`: a field of a declaration is malformed;
--- - `parameter_mismatch`: the path template and `parameters.path` disagree;
--- - `invalid_action`: the action is not a function (route module) or a method name (controller);
--- - `missing_action`: a controller has no method of that name;
--- - `invalid_controller`: a controller source is not a finalised class deriving from `Controller`;
--- - `invalid_routes`: the class field `routes` of a controller is not a list;
--- - `invalid_source`: a route declaration or a source of routes is not a table (or class);
--- - `incomplete_route`: a verb was called without its table of declarations (`module:get "/x"` alone);
--- - `missing_container`: a controller declares `dependencies` and the application has no container;
--- - `unsupported_content_type`: a route declares `content` for no media type the kernel reads.
---
--- `context.origin` names the route module or controller; `context.field` the offending field when there is one.
---@class hecate.kernel.RouteDeclarationError : hecate.core.ConfigurationError
---@field context { reason: string, origin?: string, field?: string }
local RouteDeclarationError = declare("RouteDeclarationError", core.ConfigurationError)

--- An application composition the kernel refuses at boot. `context.reason` is the stable identifier (and the end of
--- `code`): `invalid_module` (a module is malformed), `duplicate_module`, `missing_dependency` (a module requires one
--- that is not registered), `dependency_cycle` (`context.cycle` lists the module names), `already_booted` and
--- `already_served` (`Application:serve` runs once). `context.module` names the faulty module.
---@class hecate.kernel.ModuleError : hecate.core.ConfigurationError
---@field context { reason: string, module?: string, cycle?: string[] }
local ModuleError = declare("ModuleError", core.ConfigurationError)

--- The supervisor of the workers stopped on a failure (ADR 0023). `context.reason` is the stable identifier (and the
--- end of `code`): `crash_loop` (workers kept exiting: `crash_limit` exits within `crash_window`), `start_failed` (the
--- worker program cannot be started), `already_run`, and for `Supervisor:reload`: `reload_failed` (`context.cause`:
--- `start_failed`, `exited`, `not_ready`, `worker_lost` or `stopping`; `context.worker` the slot),
--- `reload_in_progress`, `stopping` and `not_running`.
---@class hecate.kernel.SupervisorError : hecate.core.Error
---@field context { reason: string, cause?: string, worker?: integer }
local SupervisorError = declare("SupervisorError", core.Error)

return { RouteDeclarationError = RouteDeclarationError, ModuleError = ModuleError, SupervisorError = SupervisorError }
