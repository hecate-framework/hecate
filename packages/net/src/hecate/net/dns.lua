-- `net.resolve`: name resolution as part of the network surface. Delegates to `reactor.resolve`
-- (OQ-32); `net` never requires luv.
global <const> require

local reactor = require("hecate.reactor")

---@class hecate.net
local M = {}

--- Resolves `host` to numeric addresses, in the order the system resolver prefers. A numeric
--- address resolves to itself. Suspends; bound it with `reactor.deadline`.
---
--- Raises `hecate.reactor.TransportError` when the name does not resolve and
--- `hecate.core.ArgumentError` for a malformed host or option.
---@async
---@param host string  a host name or a numeric address
---@param options? hecate.reactor.ResolveOptions  `family` restricts the answer to one address family
---@return hecate.reactor.ResolvedAddress[] addresses  the distinct addresses, in resolver order
function M.resolve(host, options)
  return reactor.resolve(host, options)
end

return M
