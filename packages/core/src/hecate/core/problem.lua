-- The `Problem` marker interface: it says that a class is serialisable as an RFC 9457 problem. A consumer such as
-- `hecate.openapi` recognises a problem class by `core.implements(class, core.Problem)` instead of by duck typing
-- (OQ-129 (7), (12)). An interface declares methods only (ADR 0007), so this one declares none.
global <const> require

local interface_module = require("hecate.core.interface")

--- The marker interface of a problem class (RFC 9457): a class that declares it with `implements = { core.Problem }`
--- (and every subclass, which inherits the declaration) is serialisable as a problem. It declares no method and no
--- field, so `core.finalise` checks nothing about it. Documented contract, read as class attributes and validated by
--- the consumer, not by `core`: `status`, an integer from 400 to 599 (RFC 9110, sections 15.5 and 15.6;
--- `core.status.is_error` checks it), and `title`, a string, possibly empty (RFC 9457, section 3.1.4).
---@type table
local Problem = interface_module.interface("Problem", {})

return Problem
