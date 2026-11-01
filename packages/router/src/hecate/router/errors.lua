-- The error classes of the router.
global <const> require

local core = require("hecate.core")

--- A route table the router refuses at boot, with a precise diagnostic. `context.reason` is the stable identifier:
--- `invalid_route`, `invalid_method`, `invalid_template` (then `context.template_reason` says why, as
--- `template.parse` does), `duplicate_name` or `ambiguous_route`. `context.index` is the position of the offending
--- route in the table (from 1); `context.other_index` the route it conflicts with, and `context.method` the method
--- they share, for `duplicate_name` and `ambiguous_route`.
---@class hecate.router.RouteTableError : hecate.core.ConfigurationError
---@field context { reason: string, index: integer, other_index?: integer, method?: string, template_reason?: string }
local RouteTableError = core.error_class("RouteTableError", "hecate.router.RouteTableError", core.ConfigurationError)

return { RouteTableError = RouteTableError }
