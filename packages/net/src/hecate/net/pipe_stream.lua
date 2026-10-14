-- PipeStream: a `Stream` over a reactor pipe (Unix-domain socket, named pipe on Windows).
global <const> require

local core = require("hecate.core")
local Stream = require("hecate.net.stream")
local BufferedReader = require("hecate.net.buffered_reader")
local BufferedWriter = require("hecate.net.buffered_writer")

--- A connected pipe stream with buffered readers and writers. Semantics as `hecate.net.TcpStream`.
---@class hecate.net.PipeStream: hecate.net.Stream
---@overload fun(inner: hecate.reactor.PipeStream): hecate.net.PipeStream
local PipeStream = core.class("PipeStream", nil, { implements = { Stream } })

--- Wraps an established reactor pipe stream, which this stream owns. Prefer `net.connect_pipe`.
---@param inner hecate.reactor.PipeStream
---@private
function PipeStream:init(inner) self._inner = inner end

--- Reads at most `max` bytes; nil at end of stream; never an empty string. Cancelling keeps the
--- stream open and loses no data.
---@async
---@param max? integer
---@return string?
function PipeStream:read(max) return self._inner:read(max) end

--- Writes all of `data` or raises; a write cancelled before it completed closes the stream.
---@async
---@param data string
function PipeStream:write(data) return self._inner:write(data) end

--- Half-close: tells the peer that no more data will come; the stream stays readable.
---@async
function PipeStream:shutdown() return self._inner:shutdown() end

--- Closes the stream. Idempotent, never suspends.
function PipeStream:close() self._inner:close() end

--- Closes at the end of a `<close>` scope, including on cancellation.
function PipeStream:__close() self._inner:close() end

---@return boolean
function PipeStream:is_closed() return self._inner:is_closed() end

--- A `BufferedReader` over this stream (which it does not own).
---@param options? { limit?: integer }
---@return hecate.net.BufferedReader
function PipeStream:reader(options) return BufferedReader(self, options) end

--- A `BufferedWriter` over this stream (which it does not own); flush it before `shutdown`.
---@param options? { capacity?: integer }
---@return hecate.net.BufferedWriter
function PipeStream:writer(options) return BufferedWriter(self, options) end

core.finalise(PipeStream)

return PipeStream
