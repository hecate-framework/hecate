-- `net.bind_udp`: a host name is resolved with `reactor.resolve`, then the numeric address goes
-- to the reactor transport (OQ-28, OQ-32).
global <const> require, type, error, tostring

local core = require("hecate.core")
local reactor = require("hecate.reactor")
local UdpSocket = require("hecate.net.udp_socket")

-- Documented on `hecate.net` (module class completed here so that the LuaLS export lists the
-- functions; coding-standards.md, "Annotations for the reference").

---@class hecate.net
local M = {}

--- Binds a UDP socket on `host:port` (port 0 picks a free port, see `UdpSocket:local_address`).
--- A host name is resolved and its first address is used. Suspends only for the resolution.
---
--- Raises `hecate.reactor.TransportError` when the name does not resolve or binding fails, and
--- `hecate.core.ArgumentError` for a malformed host or port.
---@async
---@param host string  host name or numeric address
---@param port integer  UDP port; 0 picks a free port
---@return hecate.net.UdpSocket socket  the bound socket
function M.bind_udp(host, port)
  if type(host) ~= "string" or host == "" then
    error(core.ArgumentError(("bind_udp expects a host name or address, got %s"):format(tostring(host))), 2)
  end
  local addresses = reactor.resolve(host)
  return UdpSocket(reactor.udp_bind(addresses[1].ip, port))
end

return M
