-- The `Problem` interface: what a problem class (RFC 9457) declares at class level. A consumer such as
-- `hecate.openapi` or `hecate.kernel` recognises a problem class by `core.implements(class, core.Problem)`
-- instead of by duck typing (OQ-129 (7)). Methods only, like every interface (ADR 0007), in the manner of
-- `schema.Representable` and its class-level `schema()`.
global <const> require

local interface_module = require("hecate.core.interface")

--- The interface of a problem class (RFC 9457): a class that declares it with `implements = { core.Problem }`
--- provides two class-level functions, `status()` returning an integer from 400 to 599 (RFC 9110, sections 15.5 and
--- 15.6; `core.status.is_error` checks it) and `title()` returning a string, possibly empty (RFC 9457, section 3.1.4).
--- `core.finalise` raises `ConformanceError` naming the class and the member when one is missing, and inherits both
--- from a finalised superclass. Only the presence is checked at finalisation, as for `Representable`: the returned
--- values are the contract of the implementer, checked by the consumer that calls them.
---@type table
local Problem = interface_module.interface("Problem", { "status", "title" })

return Problem
