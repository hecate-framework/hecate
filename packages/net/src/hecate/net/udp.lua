-- `net.bind_udp`: a host name is resolved with `reactor.resolve`, then the numeric address goes
-- to the reactor transport (OQ-28, OQ-32).
global <const> require, type, error, tostring, math, pairs

local core = require("hecate.core")
local reactor = require("hecate.reactor")
local UdpSocket = require("hecate.net.udp_socket")
local dns = require("hecate.net.dns")

-- Documented on `hecate.net` (module class completed here so that the LuaLS export lists the
-- functions; coding-standards.md, "Annotations for the reference").

---@class hecate.net
local M = {}

--- Binds a UDP socket on `host:port` (port 0 picks a free port, see `UdpSocket:local_address`).
--- A host name is resolved and its first address is used. Suspends only for the resolution. The
--- only option is `family` (`"inet"` or `"inet6"`), which restricts the resolution as for
--- `net.connect`.
---
--- Raises `hecate.reactor.TransportError` when the name does not resolve or binding fails, and
--- `hecate.core.ArgumentError` for a malformed host, port or option.
---@async
---@param host string  host name or numeric address
---@param port integer  UDP port; 0 picks a free port
---@param options? { family?: "inet"|"inet6" }
---@return hecate.net.UdpSocket socket  the bound socket
function M.bind_udp(host, port, options)
  if type(host) ~= "string" or host == "" then
    error(core.ArgumentError(("net.bind_udp: expects a host name or address, got %s"):format(tostring(host))), 2)
  end
  if math.type(port) ~= "integer" or port < 0 or port > 65535 then
    error(core.ArgumentError(("net.bind_udp: expects a port in 0..65535, got %s"):format(tostring(port))), 2)
  end
  if options ~= nil and type(options) ~= "table" then
    error(core.ArgumentError(("net.bind_udp: expects an options table, got %s"):format(type(options))), 2)
  end
  for key in pairs(options or {}) do
    if key ~= "family" then
      error(core.ArgumentError(("net.bind_udp: unknown option %s"):format(tostring(key))), 2)
    end
  end
  local addresses = dns.resolve(host, { family = options and options.family })
  return UdpSocket(reactor.bind_udp(addresses[1].ip, port))
end

return M
