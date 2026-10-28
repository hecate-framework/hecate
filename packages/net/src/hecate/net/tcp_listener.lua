-- TcpListener: accepts `TcpStream`s over a reactor TCP listener (OQ-28).
global <const> require

local core = require("hecate.core")
local TcpStream = require("hecate.net.tcp_stream")

--- A listening TCP socket that accepts `TcpStream`s.
---@class hecate.net.TcpListener
---@overload fun(inner: hecate.reactor.TcpListener): hecate.net.TcpListener
local TcpListener = core.class("TcpListener")

--- Wraps a reactor listener, which this listener owns from now on. Prefer `net.listen`.
---@param inner hecate.reactor.TcpListener
---@private
function TcpListener:init(inner)
  ---@diagnostic disable-next-line: inject-field  -- the reactor listener names this class in its messages
  inner._label = "net.TcpListener"
  self._inner = inner
end

--- Suspends until a connection arrives. Cancelling keeps the listener open and the queued
--- connections; connections are taken one per call, so a slow acceptor leaves the rest in the
--- kernel backlog (back-pressure).
---@async
---@return hecate.net.TcpStream
function TcpListener:accept()
  return TcpStream(self._inner:accept())
end

--- Stops listening. Idempotent, never suspends; a coroutine waiting in `accept` fails with
--- `TransportError` (`ECANCELED`). Accepted streams are unaffected.
function TcpListener:close() self._inner:close() end

--- Closes at the end of a `<close>` scope.
function TcpListener:__close() self._inner:close() end

--- Returns whether the listener is closed.
---@return boolean
function TcpListener:is_closed() return self._inner:is_closed() end

--- Address the listener is bound to (use it to learn the port chosen for port 0).
---@return hecate.reactor.SocketAddress
function TcpListener:local_address() return self._inner:local_address() end

return core.finalise(TcpListener)
