-- The error classes of the container. All extend `core.ConfigurationError`: each means that the composition is wrong
-- (ADR 0018, container.md "Errors").
global <const> require

local core = require("hecate.core")

--- Base class of the container errors; also raised for a use in the wrong state (before `validate`, `bind` after it,
--- any use after `close`).
---@class hecate.container.ContainerError : hecate.core.ConfigurationError
---@overload fun(fields: hecate.core.ErrorFields|string, extra?: hecate.core.ErrorFields): hecate.container.ContainerError
local ContainerError = core.error_class("ContainerError", "hecate.container.ContainerError", core.ConfigurationError)

--- `bind` on a key that is already bound. `context.key` is the key.
---@class hecate.container.DuplicateBindingError : hecate.container.ContainerError
---@field context { key: string }
---@overload fun(fields: hecate.core.ErrorFields|string, extra?: hecate.core.ErrorFields): hecate.container.DuplicateBindingError
local DuplicateBindingError = core.error_class("DuplicateBindingError", "hecate.container.DuplicateBindingError",
  ContainerError)

--- A required or requested key has no binding, or `override` of an unbound key. `context.key` is the missing key and
--- `context.path` the chain of keys that led to it.
---@class hecate.container.MissingBindingError : hecate.container.ContainerError
---@field context { key: string, path: string[] }
---@overload fun(fields: hecate.core.ErrorFields|string, extra?: hecate.core.ErrorFields): hecate.container.MissingBindingError
local MissingBindingError = core.error_class("MissingBindingError", "hecate.container.MissingBindingError",
  ContainerError)

--- The dependency graph has a cycle. `context.path` lists the keys in order, the first one repeated at the end.
---@class hecate.container.CycleError : hecate.container.ContainerError
---@field context { path: string[] }
---@overload fun(fields: hecate.core.ErrorFields|string, extra?: hecate.core.ErrorFields): hecate.container.CycleError
local CycleError = core.error_class("CycleError", "hecate.container.CycleError", ContainerError)

--- A singleton depends on a scoped service; a service that needs a scoped one is requested from the container itself;
--- or a resolution from the container itself would create a closable transient that no singleton owns.
--- `context.key` is the singleton (or the requested key), `context.dependency` the scoped service (or the closable
--- transient), `context.path` the chain between them; `context.suppressed` holds the close errors of the products
--- closed again before a refusal of a closable transient, if any.
---@class hecate.container.LifetimeError : hecate.container.ContainerError
---@field context { key: string, dependency: string, path: string[], suppressed?: any[] }
---@overload fun(fields: hecate.core.ErrorFields|string, extra?: hecate.core.ErrorFields): hecate.container.LifetimeError
local LifetimeError = core.error_class("LifetimeError", "hecate.container.LifetimeError", ContainerError)

--- `validate` found one or more problems. `context.problems` holds the individual errors, in the order of binding.
---@class hecate.container.GraphError : hecate.container.ContainerError
---@field context { problems: hecate.core.Error[] }
---@overload fun(fields: hecate.core.ErrorFields|string, extra?: hecate.core.ErrorFields): hecate.container.GraphError
local GraphError = core.error_class("GraphError", "hecate.container.GraphError", ContainerError)

--- A constructor or factory raised. `cause` is the original error; `context.key` and `context.path` locate it.
---@class hecate.container.ConstructionError : hecate.container.ContainerError
---@field context { key: string, path: string[] }
---@overload fun(fields: hecate.core.ErrorFields|string, extra?: hecate.core.ErrorFields): hecate.container.ConstructionError
local ConstructionError = core.error_class("ConstructionError", "hecate.container.ConstructionError", ContainerError)

return {
  ContainerError = ContainerError,
  DuplicateBindingError = DuplicateBindingError,
  MissingBindingError = MissingBindingError,
  CycleError = CycleError,
  LifetimeError = LifetimeError,
  GraphError = GraphError,
  ConstructionError = ConstructionError,
}
