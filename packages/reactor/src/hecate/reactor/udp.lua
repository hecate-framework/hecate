-- UDP transport as suspending calls over libuv datagram handles (concurrency.md, "Model";
-- ADR 0002: luv is wrapped once, here). Same cancellation rules as `tcp.lua`: `receive_from`
-- leaves the socket intact (a datagram that arrives later stays in the kernel queue for the next
-- call); a `send_to` cancelled before it completed closes the socket; `close` is idempotent,
-- never suspends and wakes the coroutine waiting on the socket.
global <const> type, error, require, pcall, tostring, math

local core = require("hecate.core")
local uv = require("luv")
local uv_call = require("hecate.reactor.internal.uv_call")
local context = require("hecate.reactor.internal.context")

---@param name string
---@param host any
---@param port any
local function check_endpoint(name, host, port)
  if type(host) ~= "string" then
    error(core.ArgumentError(("%s: expects a numeric address string, got %s"):format(name, type(host))), 3)
  end
  if math.type(port) ~= "integer" or port < 0 or port > 65535 then
    error(core.ArgumentError(("%s: expects a port in 0..65535, got %s"):format(name, tostring(port))), 3)
  end
end

--- luv raises a Lua error for a malformed address; report it as libuv's EINVAL instead.
---@param fn function
---@param ... any
---@return any ok
---@return string? err
local function protected(fn, ...)
  local ok, result, err = pcall(fn, ...)
  if not ok then return nil, "EINVAL: invalid address (" .. tostring(result) .. ")" end
  return result, err
end

--- The call named in the messages of `operation`: the method of the class in `_label`.
---@param self table
---@param operation string
---@return string
local function qualified(self, operation)
  return self._label .. "." .. operation
end

---@param self table
---@param operation string
local function require_open(self, operation)
  if self._closed then uv_call.fail_transport(qualified(self, operation), operation, "EBADF: socket is closed") end
end

--- A bound UDP socket; its operations suspend until the datagram moves.
---@class hecate.reactor.UdpSocket
---@overload fun(handle: table): hecate.reactor.UdpSocket
local UdpSocket = core.class("UdpSocket")

---@param handle table  a bound libuv UDP handle, owned by the socket from now on
---@private
function UdpSocket:init(handle)
  self._handle = handle
  self._label = "reactor.UdpSocket" -- the class named in messages; a wrapper may relabel it
  self._closed = false
  self._wake = nil
  self._receiving = false
end

--- Sends one datagram to a numeric address; returns once libuv handed it to the operating
--- system. A datagram larger than the path allows raises `TransportError` (`EMSGSIZE`). A send
--- cancelled before it completed closes the socket.
---@async
---@param host string  numeric IPv4 or IPv6 address
---@param port integer  UDP port, 0..65535 (`net` refuses 0)
---@param data string
function UdpSocket:send_to(host, port, data)
  if type(data) ~= "string" then
    error(core.ArgumentError(("%s: expects a string, got %s"):format(qualified(self, "send_to"), type(data))), 2)
  end
  check_endpoint(qualified(self, "send_to"), host, port)
  uv_call.begin(qualified(self, "send_to"))
  require_open(self, "send_to")
  local state = {}
  local ok, failure = pcall(context.suspend, function(wake)
    local started, err = protected(self._handle.send, self._handle, data, host, port, function(e)
      state.done, state.err = true, e
      wake()
    end)
    if not started then
      state.done, state.err = true, tostring(err)
      wake()
    end
  end)
  if not ok then
    if not state.done then self:close() end
    error(failure, 0)
  end
  if state.err then uv_call.fail_transport(qualified(self, "send_to"), "send_to", state.err) end
end

--- Suspends until a datagram arrives; returns its payload and the sender's address. An empty
--- datagram is returned as an empty string. Cancelling keeps the socket open and loses nothing.
--- One coroutine receives at a time.
---@async
---@return string data
---@return hecate.reactor.SocketAddress from
function UdpSocket:receive_from()
  uv_call.begin(qualified(self, "receive_from"))
  require_open(self, "receive_from")
  if self._receiving then error(core.Error(qualified(self, "receive_from") .. ": another coroutine is already receiving"), 2) end
  local state = {}
  self._receiving = true
  local ok, failure = pcall(context.suspend, function(wake)
    self._wake = wake
    local started, err = self._handle:recv_start(function(e, data, address)
      if not e and data == nil then return end -- libuv: nothing to read right now
      self._handle:recv_stop()
      state.err, state.data, state.address = e, data, address
      local wake_receiver = self._wake
      self._wake = nil
      if wake_receiver then wake_receiver() end
    end)
    if not started then
      state.err = tostring(err)
      self._wake = nil
      wake()
    end
    return function()
      self._wake = nil
      if not self._closed then self._handle:recv_stop() end
    end
  end)
  self._receiving = false
  if not ok then error(failure, 0) end
  if self._closed then uv_call.fail_transport(qualified(self, "receive_from"), "receive_from", "ECANCELED: socket closed while receiving") end
  if state.err then uv_call.fail_transport(qualified(self, "receive_from"), "receive_from", state.err) end
  local address = state.address
  return state.data, { ip = address.ip, port = address.port, family = address.family }
end

--- Closes the socket. Idempotent, never suspends; a coroutine waiting on it is woken with a
--- `TransportError` (`ECANCELED`).
function UdpSocket:close()
  if self._closed then return end
  self._closed = true
  local wake = self._wake
  self._wake = nil
  if not self._handle:is_closing() then self._handle:close() end
  if wake then wake() end
end

--- Closing at the end of a `<close>` scope, including on cancellation.
function UdpSocket:__close() self:close() end

--- Returns whether the socket is closed.
---@return boolean
function UdpSocket:is_closed() return self._closed end

--- Address the socket is bound to (use it to learn the port chosen for port 0).
---@return hecate.reactor.SocketAddress
function UdpSocket:local_address()
  require_open(self, "local_address")
  local address, err = self._handle:getsockname()
  if not address then uv_call.fail_transport(qualified(self, "local_address"), "local_address", tostring(err)) end
  return { ip = address.ip, port = address.port, family = address.family }
end

core.finalise(UdpSocket)

local M = { UdpSocket = UdpSocket }

-- Documented on `hecate.reactor` (module class completed here so that the LuaLS export lists the
-- function; coding-standards.md, "Annotations for the reference").

---@class hecate.reactor
local api = {}

--- Binds a UDP socket to a numeric address (port 0 picks a free port; see `local_address`).
--- Does not suspend. The socket can send to and receive from any peer.
---
--- Raises `hecate.reactor.TransportError` when binding fails, and `hecate.core.ArgumentError`
--- for a malformed host or port.
---@param host string  numeric IPv4 or IPv6 address
---@param port integer  UDP port; 0 picks a free port
---@return hecate.reactor.UdpSocket socket  the bound socket
function api.bind_udp(host, port)
  check_endpoint("reactor.bind_udp", host, port)
  uv_call.begin("reactor.bind_udp")
  local handle = uv.new_udp()
  local bound, err = protected(handle.bind, handle, host, port)
  if not bound then
    handle:close()
    uv_call.fail_transport("reactor.bind_udp", "bind " .. host .. ":" .. port, tostring(err))
  end
  return UdpSocket(handle)
end

M.bind_udp = api.bind_udp

return M
