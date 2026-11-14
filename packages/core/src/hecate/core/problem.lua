-- The `Problem` interface: what a problem class (RFC 9457) declares at class level. A consumer such as
-- `hecate.openapi` or `hecate.kernel` recognises a problem class by `core.implements(class, core.Problem)`
-- instead of by duck typing (OQ-129 (7)).
global <const> type, require

local interface_module = require("hecate.core.interface")
local status = require("hecate.core.status")

--- The interface of a problem class (RFC 9457): a class that declares it with `implements = { core.Problem }`
--- has a class-level `status` (an integer from 100 to 599, RFC 9110 section 15) and a class-level `title` (a string,
--- RFC 9457 section 3.1.4), and `core.finalise` raises `ConformanceError` naming the class and the member otherwise.
--- A class inherits both from a finalised superclass. The interface checks the class, not an instance.
---@type table
local Problem = interface_module.interface("Problem", {}, {
  fields = {
    { name = "status", expected = "an integer from 100 to 599", check = status.is_valid },
    { name = "title", expected = "a string", check = function(value) return type(value) == "string" end },
  },
})

return Problem
