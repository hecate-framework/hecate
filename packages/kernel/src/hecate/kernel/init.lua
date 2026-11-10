-- hecate.kernel: the application: filters, results, problems, route declarations, dispatcher and Application.
global <const> require

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
---@field ModuleError hecate.kernel.ModuleError  an invalid application composition
---@field RouteDeclarationError hecate.kernel.RouteDeclarationError  an invalid route declaration
local kernel = {}

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
---@diagnostic disable-next-line: assign-type-mismatch  -- class constructor exported as its class
kernel.Application = require("hecate.kernel.application")
kernel.RouteDeclarationError = require("hecate.kernel.errors").RouteDeclarationError
kernel.ModuleError = require("hecate.kernel.errors").ModuleError

--- Creates a route module: the lightweight declaration style (`local health = kernel.routes "health"`).
--- `options` is `{ prefix?, filters? }`: see `hecate.kernel.RouteModuleOptions`.
---@param name string
---@param options? hecate.kernel.RouteModuleOptions
---@return hecate.kernel.RouteModule
function kernel.routes(name, options) return kernel.RouteModule(name, options) end

return kernel
