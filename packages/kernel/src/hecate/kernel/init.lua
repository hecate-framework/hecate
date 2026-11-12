-- hecate.kernel: the application: filters, results, problems, route declarations, dispatcher and Application.
global <const> require, type, error, pairs

--- The application kernel.
---@class hecate.kernel
---@field chain hecate.kernel.chain  composes filters around an action
---@field results hecate.kernel.results  serialises the result of an action into a Response
---@field problem hecate.kernel.problem  problem classes (`NotFound`, ...) and `define`
---@field problems hecate.kernel.problems  maps errors and routing failures to problem details responses
---@field respond fun(status: integer, value?: any, schema?: table): hecate.kernel.results.Result  answers with a status and a value (`kernel.respond(201, user)`), alias of `results.respond`
---@field routes fun(name: string, options?: hecate.kernel.RouteModuleOptions): hecate.kernel.RouteModule  creates a route module (`hecate.routes "health"`)
---@field dispatcher hecate.kernel.dispatcher  builds the function that serves a request from a route table
---@field RouteModule hecate.kernel.RouteModule  the class of route modules
---@field Controller hecate.kernel.Controller  the superclass of controllers
---@field route hecate.kernel.route  the route entry: normalisation and checks
---@field routing hecate.kernel.routing  gathers route modules and controllers into one route table
---@field modules hecate.kernel.modules  validation and ordering of feature modules
---@field Application hecate.kernel.Application  the composition root
---@field listening hecate.kernel.listening  the listening strategies of multi-process serving (ADR 0023)
---@field load_configuration fun(options: hecate.config.LoadOptions): hecate.config.Configuration  `config.load` with `wrap_secret = hecate.log.Secret`
---@field ModuleError hecate.kernel.ModuleError  an invalid application composition
---@field SupervisorError hecate.kernel.SupervisorError  the supervisor of the workers stopped on a failure
---@field supervisor hecate.kernel.supervisors  multi-process serving: `Supervisor` in the primary, `worker_role()` in a worker
---@field RouteDeclarationError hecate.kernel.RouteDeclarationError  an invalid route declaration
local kernel = {}

local core = require("hecate.core")
local config = require("hecate.config")
local log = require("hecate.log")

-- `config.load` checks that `wrap_secret` is a function; `log.Secret` is a callable class.
local function wrap_secret(value) return log.Secret(value) end

kernel.chain = require("hecate.kernel.chain")
kernel.results = require("hecate.kernel.results")
kernel.problem = require("hecate.kernel.problem")
kernel.respond = kernel.results.respond
kernel.problems = require("hecate.kernel.problems")
kernel.route = require("hecate.kernel.route")
kernel.routing = require("hecate.kernel.routing")
kernel.dispatcher = require("hecate.kernel.dispatcher")
---@diagnostic disable-next-line: assign-type-mismatch  -- class constructor exported as its class
kernel.RouteModule = require("hecate.kernel.routes")
---@diagnostic disable-next-line: assign-type-mismatch  -- class constructor exported as its class
kernel.Controller = require("hecate.kernel.controller")
kernel.modules = require("hecate.kernel.modules")
kernel.listening = require("hecate.kernel.listening")
---@diagnostic disable-next-line: assign-type-mismatch  -- class constructor exported as its class
kernel.Application = require("hecate.kernel.application")
kernel.RouteDeclarationError = require("hecate.kernel.errors").RouteDeclarationError
kernel.ModuleError = require("hecate.kernel.errors").ModuleError
kernel.SupervisorError = require("hecate.kernel.errors").SupervisorError
kernel.supervisor = require("hecate.kernel.supervisor")

--- Creates a route module: the lightweight declaration style (`local health = kernel.routes "health"`).
--- `options` is `{ prefix?, filters? }`: see `hecate.kernel.RouteModuleOptions`.
---@param name string
---@param options? hecate.kernel.RouteModuleOptions
---@return hecate.kernel.RouteModule
function kernel.routes(name, options) return kernel.RouteModule(name, options) end

--- Loads the configuration with `hecate.config.load`, passing `hecate.log.Secret` as `wrap_secret` unless the options
--- give one (configuration.md, "Secrets"): the secret values are then rendered `[redacted]` by every logging sink.
--- Pass the result as the `configuration` option of `Application`.
---
--- Raises `hecate.core.ArgumentError` for invalid options and the errors of `hecate.config.load`.
---@param options hecate.config.LoadOptions
---@return hecate.config.Configuration
function kernel.load_configuration(options)
  if type(options) ~= "table" then
    error(core.ArgumentError("hecate.kernel.init.load_configuration: options must be a table, got " .. type(options)), 2)
  end
  local copy = {}
  for key, value in pairs(options) do copy[key] = value end
  if copy.wrap_secret == nil then copy.wrap_secret = wrap_secret end
  return config.load(copy)
end

return kernel
