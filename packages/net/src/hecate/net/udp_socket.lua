-- UdpSocket: datagrams over a reactor UDP socket. It wraps `reactor.UdpSocket`, so this package
-- never touches libuv (OQ-28). Datagrams are not a byte stream: it is not a `Stream`.
global <const> require

local core = require("hecate.core")

--- A bound UDP socket. Each call moves exactly one datagram.
---@class hecate.net.UdpSocket
---@overload fun(inner: hecate.reactor.UdpSocket): hecate.net.UdpSocket
local UdpSocket = core.class("UdpSocket")

--- Wraps a bound reactor socket, which this socket owns from now on. Prefer `net.bind_udp`.
---@param inner hecate.reactor.UdpSocket
---@private
function UdpSocket:init(inner)
  self._inner = inner
end

--- Sends one datagram to a numeric address. Raises `TransportError` when it cannot be sent
--- (for example `EMSGSIZE`). A send cancelled before it completed closes the socket.
---@async
---@param data string
---@param host string  numeric IPv4 or IPv6 address
---@param port integer  UDP port, 1..65535
function UdpSocket:send_to(data, host, port)
  return self._inner:send_to(data, host, port)
end

--- Suspends until a datagram arrives; returns its payload and the sender's address. Cancelling
--- (for example by `reactor.deadline`) keeps the socket open and loses nothing.
---@async
---@return string data
---@return hecate.reactor.SocketAddress from
function UdpSocket:receive_from()
  return self._inner:receive_from()
end

--- Closes the socket. Idempotent, never suspends; a task waiting on it fails with
--- `TransportError` (`ECANCELED`).
function UdpSocket:close() self._inner:close() end

--- Closing at the end of a `<close>` scope.
function UdpSocket:__close() self._inner:close() end

--- Returns whether the socket is closed.
---@return boolean
function UdpSocket:is_closed() return self._inner:is_closed() end

--- Address the socket is bound to (use it to learn the port chosen for port 0).
---@return hecate.reactor.SocketAddress
function UdpSocket:local_address() return self._inner:local_address() end

core.finalise(UdpSocket)

return UdpSocket
