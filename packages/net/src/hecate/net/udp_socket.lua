-- UdpSocket: datagrams over a reactor UDP socket. It wraps `reactor.UdpSocket`, so this package
-- never touches libuv (OQ-28). Datagrams are not a byte stream: it is not a `Stream`.
global <const> require, type, error, tostring, math, tonumber, ipairs

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

--- Whether `text` looks like a numeric IPv4 or IPv6 address (the transport checks it exactly).
---@param text string
---@return boolean
local function is_numeric_address(text)
  local a, b, c, d = text:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
  if a then
    for _, part in ipairs({ a, b, c, d }) do
      if #part > 3 or tonumber(part) > 255 then return false end
    end
    return true
  end
  -- IPv6: hexadecimal groups, colons, an optional embedded IPv4 tail and an optional `%zone`.
  local address = text:match("^([^%%]+)%%[%w_.~-]+$") or text
  return address:find(":", 1, true) ~= nil and address:find("^[%x:.]+$") ~= nil
end

--- Sends one datagram to a numeric address. `send_to` does not resolve names, on purpose: a
--- datagram has no connection to retry on another address, so the caller picks one, with
--- `net.resolve`. A host name raises `ArgumentError` (its message points to `net.resolve`), as does a
--- port outside 1..65535 or a payload that is not a string. A transport failure raises
--- `TransportError` (for example `EMSGSIZE`, or `EBADF` on a closed socket). A send cancelled before it
--- completed closes the socket.
---@async
---@param host string  numeric IPv4 or IPv6 address (resolve a name with `net.resolve`)
---@param port integer  UDP port, 1..65535
---@param data string
function UdpSocket:send_to(host, port, data)
  if type(host) ~= "string" or not is_numeric_address(host) then
    error(core.ArgumentError(
      ("send_to expects a numeric IP address, got %s: resolve a name first with net.resolve"):format(tostring(host))), 2)
  end
  if math.type(port) ~= "integer" or port < 1 or port > 65535 then
    error(core.ArgumentError(("send_to expects a port in 1..65535, got %s"):format(tostring(port))), 2)
  end
  if type(data) ~= "string" then
    error(core.ArgumentError(("send_to expects a string, got %s"):format(type(data))), 2)
  end
  self._inner:send_to(host, port, data)
end

--- Suspends until a datagram arrives; returns its payload (possibly empty) and the sender's
--- address. Cancelling (for example by `reactor.deadline`) keeps the socket open and loses nothing.
---@async
---@return string data
---@return hecate.reactor.SocketAddress from
function UdpSocket:receive_from()
  return self._inner:receive_from()
end

--- Closes the socket. Idempotent, never suspends; a coroutine waiting on it fails with
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

return core.finalise(UdpSocket)
