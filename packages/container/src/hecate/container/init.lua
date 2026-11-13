---@diagnostic disable: assign-type-mismatch  -- classes are constructors exported as their class (as in hecate.core)
-- hecate.container: inversion-of-control container: bindings, lifetimes (singleton, scoped, transient), constructor
-- injection, cycle detection at boot.
global <const> require

local container = require("hecate.container.container")
local errors = require("hecate.container.errors")

--- The container package: bind services, validate the graph at boot, resolve by constructor injection.
---@class hecate.container
---@field Container hecate.container.Container  bindings, validation and resolution
---@field ServiceScope hecate.container.ServiceScope  the lifetime of scoped services (one per request)
---@field Lifetime hecate.container.Lifetime  `singleton`, `scoped`, `transient`
---@field ContainerError hecate.container.ContainerError  base class; wrong-state use
---@field DuplicateBindingError hecate.container.DuplicateBindingError  a key bound twice
---@field MissingBindingError hecate.container.MissingBindingError  a key without binding
---@field CycleError hecate.container.CycleError  a dependency cycle
---@field LifetimeError hecate.container.LifetimeError  a captive scoped service, or a root resolution that needs a service scope
---@field GraphError hecate.container.GraphError  everything `validate` found
---@field ConstructionError hecate.container.ConstructionError  a constructor or factory raised
local M = {}
M.Container = container.Container
M.ServiceScope = container.ServiceScope
M.Lifetime = require("hecate.container.lifetime")
M.ContainerError = errors.ContainerError
M.DuplicateBindingError = errors.DuplicateBindingError
M.MissingBindingError = errors.MissingBindingError
M.CycleError = errors.CycleError
M.LifetimeError = errors.LifetimeError
M.GraphError = errors.GraphError
M.ConstructionError = errors.ConstructionError

return M
