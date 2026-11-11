-- hecate: the meta-module. It re-exports the framework surface and has no code of its own.
global <const> require
local kernel = require("hecate.kernel")

--- The framework surface for typical applications (`local hecate = require "hecate"`).
--- It does not re-export the object-model entry points: classes are declared with `core.class` from `hecate.core`
--- (OQ-57), and schemas are built with `hecate.schema`.
---@class hecate
---@field Application hecate.kernel.Application  the composition root
---@field Controller hecate.kernel.Controller  the superclass of controllers
---@field routes fun(name: string, options?: hecate.kernel.RouteModuleOptions): hecate.kernel.RouteModule  creates a route module (`hecate.routes "health"`)
---@field respond fun(status: integer, value?: any, schema?: table): hecate.kernel.results.Result  answers with a status and a value
---@field problem hecate.kernel.problem  problem classes (`hecate.problem.NotFound`) and `hecate.problem.define`
---@field load_configuration fun(options: hecate.config.LoadOptions): hecate.config.Configuration  loads the configuration, wrapping secrets with `hecate.log.Secret`
---@field RouteDeclarationError hecate.kernel.RouteDeclarationError  an invalid route declaration
---@field ModuleError hecate.kernel.ModuleError  an invalid application composition
---@field SupervisorError hecate.kernel.SupervisorError  the supervisor of the workers stopped on a failure
local hecate = {
  Application = kernel.Application,
  Controller = kernel.Controller,
  routes = kernel.routes,
  respond = kernel.respond,
  problem = kernel.problem,
  load_configuration = kernel.load_configuration,
  RouteDeclarationError = kernel.RouteDeclarationError,
  ModuleError = kernel.ModuleError,
  SupervisorError = kernel.SupervisorError,
}

return hecate
