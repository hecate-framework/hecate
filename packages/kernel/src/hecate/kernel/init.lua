-- hecate.kernel: the application. So far: the chain of responsibility, results, problems and route declarations.
global <const> require

--- The application kernel.
---@class hecate.kernel
---@field chain hecate.kernel.chain  composes filters around an action
---@field results hecate.kernel.results  serialises the result of an action into a Response
---@field problem hecate.kernel.problem  problem classes (`NotFound`, ...) and `define`
---@field problems hecate.kernel.problems  maps errors and routing failures to problem details responses
---@field routes fun(name: string): hecate.kernel.RouteModule  creates a route module (`hecate.routes "health"`)
---@field dispatcher hecate.kernel.dispatcher  builds the function that serves a request from a route table
---@field RouteModule hecate.kernel.RouteModule  the class of route modules
---@field Controller hecate.kernel.Controller  the superclass of controllers
---@field route hecate.kernel.route  the route entry: normalisation and checks
---@field routing hecate.kernel.routing  gathers route modules and controllers into one route table
---@field RouteDeclarationError hecate.kernel.RouteDeclarationError  an invalid route declaration
local kernel = {}

kernel.chain = require("hecate.kernel.chain")
kernel.results = require("hecate.kernel.results")
kernel.problem = require("hecate.kernel.problem")
kernel.problems = require("hecate.kernel.problems")
kernel.route = require("hecate.kernel.route")
kernel.routing = require("hecate.kernel.routing")
kernel.dispatcher = require("hecate.kernel.dispatcher")
---@diagnostic disable-next-line: assign-type-mismatch  -- class constructor exported as its class
kernel.RouteModule = require("hecate.kernel.routes")
---@diagnostic disable-next-line: assign-type-mismatch  -- class constructor exported as its class
kernel.Controller = require("hecate.kernel.controller")
kernel.RouteDeclarationError = require("hecate.kernel.errors").RouteDeclarationError

--- Creates a route module: the lightweight declaration style (`local health = kernel.routes "health"`).
---@param name string
---@return hecate.kernel.RouteModule
function kernel.routes(name) return kernel.RouteModule(name) end

return kernel
