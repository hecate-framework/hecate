-- A stream that counts the bytes read from it and refuses more than a budget, until it is released. The server wraps an
-- accepted connection in it for the TLS handshake, so that a client cannot make the handshake read without bound
-- (Phase 1 security review, finding 2). Everything else passes through to the wrapped stream.
global <const> require, type, error, math

local core = require("hecate.core")

--- A budgeted view of a stream, for the duration of a handshake.
---@class hecate.http.HandshakeStream
---@overload fun(inner: hecate.net.TcpStream, budget: integer): hecate.http.HandshakeStream
local HandshakeStream = core.class("HandshakeStream")

--- Wraps `inner`, which stays owned by the caller until the wrapper is handed on (closing the wrapper closes it).
---
--- Raises `hecate.core.ArgumentError` for a budget that is not a positive integer.
---@param inner hecate.net.TcpStream
---@param budget integer  bytes that may be read before `release`
function HandshakeStream:init(inner, budget)
  if math.type(budget) ~= "integer" or budget < 1 then
    error(core.ArgumentError("http.HandshakeStream: the budget must be a positive integer"), 3)
  end
  self._inner = inner
  self._budget = budget
  self._received = 0
  self._limited = true
end

--- Reads from the stream; once more than the budget was received before `release`, closes the stream and raises a
--- `ProtocolError` (its text names nothing of the peer).
---@async
---@param max? integer
---@return string?
function HandshakeStream:read(max)
  local chunk = self._inner:read(max)
  if chunk ~= nil and self._limited then
    self._received = self._received + #chunk
    if self._received > self._budget then
      self._inner:close()
      error(core.ProtocolError({
        message = "http.HandshakeStream: the handshake exceeded its byte budget",
        context = { reason = "handshake_too_large", limit = self._budget },
      }), 0)
    end
  end
  return chunk
end

--- Lifts the budget: the handshake is over.
function HandshakeStream:release() self._limited = false end

--- Returns the number of bytes received so far.
---@return integer
function HandshakeStream:received() return self._received end

---@async
---@param data string
function HandshakeStream:write(data) self._inner:write(data) end

---@async
function HandshakeStream:shutdown() self._inner:shutdown() end

--- Closes the wrapped stream.
function HandshakeStream:close() self._inner:close() end

--- Closes the wrapped stream at the end of a `<close>` scope.
function HandshakeStream:__close() self._inner:close() end

---@return boolean
function HandshakeStream:is_closed() return self._inner:is_closed() end

---@return hecate.reactor.SocketAddress
function HandshakeStream:peer_address() return self._inner:peer_address() end

---@return hecate.reactor.SocketAddress
function HandshakeStream:local_address() return self._inner:local_address() end

---@param enabled boolean
function HandshakeStream:set_nodelay(enabled) self._inner:set_nodelay(enabled) end

return core.finalise(HandshakeStream)
