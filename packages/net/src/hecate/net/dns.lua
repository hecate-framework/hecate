-- `net.resolve`: name resolution as part of the network surface. Delegates to `reactor.resolve`
-- (OQ-32); `net` never requires luv.
global <const> require, error, pcall

local core = require("hecate.core")
local reactor = require("hecate.reactor")
local errors = require("hecate.net.errors")

---@class hecate.net
local M = {}

--- Resolves `host` to numeric addresses, in the order the system resolver prefers. A numeric
--- address resolves to itself. Suspends; bound it with `reactor.deadline`.
---
--- Raises `hecate.reactor.TransportError` when the name does not resolve (an empty answer
--- included, so the result is never empty): `context.host` is the name that was looked up, and
--- `context.errno` the resolver's code, for example `EAI_NONAME`. A malformed host or option raises
--- `hecate.core.ArgumentError`.
---@async
---@param host string  a host name or a numeric address
---@param options? hecate.reactor.ResolveOptions  `family` restricts the answer to one address family
---@return hecate.reactor.ResolvedAddress[] addresses  the distinct addresses, in resolver order
function M.resolve(host, options)
  return M.resolve_for("net.resolve", host, options)
end

--- `net.resolve` on behalf of another net call (`net.connect`, `net.listen`, `net.bind_udp`): the
--- failures name that call, as the caller wrote it.
---@async
---@param call string  the public net call
---@param host string
---@param options? hecate.reactor.ResolveOptions
---@return hecate.reactor.ResolvedAddress[]
---@private
function M.resolve_for(call, host, options)
  local ok, addresses = pcall(reactor.resolve, host, options)
  if not ok then
    -- The same error object, with the host added; cancellation and misuse pass through untouched.
    if core.is_instance_of(addresses, reactor.TransportError) then
      local failure = addresses --[[@as hecate.core.Error]]
      if failure.context == nil then failure.context = {} end
      failure.context.host = host
    end
    error(errors.rename(addresses, call), 0)
  end
  -- Defensive: `reactor.resolve` already raises for an empty answer.
  if #addresses == 0 then
    error(reactor.TransportError({
      message = ("%s: resolve %s: EAI_NONAME: no address"):format(call, host),
      context = { operation = "resolve " .. host, errno = "EAI_NONAME", host = host },
    }), 0)
  end
  return addresses
end

return M
