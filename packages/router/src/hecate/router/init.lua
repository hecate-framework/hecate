-- hecate.router: radix-tree router over URI templates (RFC 6570 level-1 subset) with 404/405 handling and reverse routing.
global <const> require

--- The router: compile a route table once at boot, match requests, build URLs from route names.
---@class hecate.router
---@field Router hecate.router.Router  a compiled route table
---@field RouteTableError hecate.router.RouteTableError  a route table refused at boot (a `ConfigurationError`)
---@field path hecate.router.paths  decoding, dot segments and encoding of request paths
---@field template hecate.router.templates  parsing and expansion of path templates
local router = {}

router.Router = require("hecate.router.router")
router.RouteTableError = require("hecate.router.errors").RouteTableError
router.path = require("hecate.router.path")
router.template = require("hecate.router.template")

return router
