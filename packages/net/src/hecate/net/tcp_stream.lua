-- TcpStream: a `Stream` over a reactor TCP connection. It wraps `reactor.TcpStream`, so this
-- package never touches libuv (OQ-28). Failures surface as `reactor.TransportError` (OQ-32).
global <const> require, error, math, tostring

local core = require("hecate.core")
local Stream = require("hecate.net.stream")
local BufferedReader = require("hecate.net.buffered_reader")
local BufferedWriter = require("hecate.net.buffered_writer")

--- A connected TCP stream with buffered readers and writers.
---@class hecate.net.TcpStream: hecate.net.Stream
---@overload fun(inner: hecate.reactor.TcpStream): hecate.net.TcpStream
local TcpStream = core.class("TcpStream", nil, { implements = { Stream } })

--- Wraps an established reactor stream, which this stream owns from now on. Prefer
--- `net.connect` and `TcpListener:accept`.
---@param inner hecate.reactor.TcpStream
---@private
function TcpStream:init(inner)
  self._inner = inner
end

--- Reads at most `max` bytes; nil at end of stream (the peer shut down its side); never an
--- empty string. Cancelling (for example by `reactor.deadline`) keeps the stream open and
--- loses no data.
---@async
---@param max? integer
---@return string?
function TcpStream:read(max)
  if max ~= nil and (math.type(max) ~= "integer" or max < 1) then
    error(core.ArgumentError(("net.TcpStream.read: expects a positive integer, got %s"):format(tostring(max))), 2)
  end
  return self._inner:read(max)
end

--- Writes all of `data` or raises; suspends while the peer is slow (back-pressure). A write
--- cancelled before it completed closes the stream, because the bytes sent are unknown.
---@async
---@param data string
function TcpStream:write(data)
  self._inner:write(data)
end

--- Half-close: tells the peer that no more data will come, once pending writes are flushed;
--- the stream stays readable. Flush any `BufferedWriter` first.
---@async
function TcpStream:shutdown()
  self._inner:shutdown()
end

--- Closes the stream. Idempotent, never suspends; coroutines waiting on it fail with `TransportError`
--- (`ECANCELED`). Unflushed or pending bytes are abandoned.
function TcpStream:close()
  self._inner:close()
end

--- Closes at the end of a `<close>` scope, including on cancellation.
function TcpStream:__close()
  self._inner:close()
end

---@return boolean
function TcpStream:is_closed() return self._inner:is_closed() end

--- Address of the remote end.
---@return hecate.reactor.SocketAddress
function TcpStream:peer_address() return self._inner:peer_address() end

--- Address of the local end.
---@return hecate.reactor.SocketAddress
function TcpStream:local_address() return self._inner:local_address() end

--- Enables or disables Nagle's algorithm (`true` disables it).
---@param enabled boolean
function TcpStream:set_nodelay(enabled) self._inner:set_nodelay(enabled) end

--- Enables or disables keep-alive probes; `delay` is the idle time in seconds before the first.
---@param enabled boolean
---@param delay? number
function TcpStream:set_keepalive(enabled, delay) self._inner:set_keepalive(enabled, delay) end

--- A `BufferedReader` over this stream (which it does not own).
---@param options? { limit?: integer }
---@return hecate.net.BufferedReader
function TcpStream:reader(options) return BufferedReader(self, options) end

--- A `BufferedWriter` over this stream (which it does not own); flush it before `shutdown`.
---@param options? { capacity?: integer }
---@return hecate.net.BufferedWriter
function TcpStream:writer(options) return BufferedWriter(self, options) end

return core.finalise(TcpStream)
