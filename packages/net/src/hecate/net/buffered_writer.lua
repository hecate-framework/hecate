-- BufferedWriter: coalesces small writes. Invariant (net/CLAUDE.md): a partial write never
-- leaks. `Stream:write` accepts all of its data or raises; when a flush fails, the number
-- of bytes the peer received is unknown, so the writer is poisoned: every later call raises
-- the same failure rather than sending bytes after a gap.
global <const> type, error, require, math, table, tostring, pcall, pairs

local core = require("hecate.core")
local reactor = require("hecate.reactor")

-- Kept at 8 KiB: it is the size at which small writes (a protocol's header lines) are coalesced.
-- A TLS record carries up to 16 KiB of plaintext, so a 16 KiB capacity would fill a record per
-- flush over a `TlsStream`; not measured here, pass `{ capacity = 16384 }` to try it.
local DEFAULT_CAPACITY = 8 * 1024

--- Writes a stream through a buffer; a failed flush poisons the writer so that no partial write goes unnoticed.
---@class hecate.net.BufferedWriter
---@overload fun(stream: hecate.net.Stream, options?: { capacity?: integer }): hecate.net.BufferedWriter
local BufferedWriter = core.class("BufferedWriter")

--- Creates a writer over `stream`; the buffer is flushed when it reaches `capacity` bytes
--- (default 8192). A payload of at least `capacity` bytes written while nothing is buffered goes
--- to the stream directly, without a copy. The writer does not own the stream.
---@param stream hecate.net.Stream
---@param options? { capacity?: integer }
function BufferedWriter:init(stream, options)
  if type(stream) ~= "table" or type(stream.write) ~= "function" then
    error(core.ArgumentError("net.BufferedWriter: expects a stream with a write method"), 3)
  end
  if options ~= nil and type(options) ~= "table" then
    error(core.ArgumentError(("net.BufferedWriter: expects an options table, got %s"):format(type(options))), 3)
  end
  for key in pairs(options or {}) do
    if key ~= "capacity" then
      error(core.ArgumentError(("net.BufferedWriter: unknown option %s (options: capacity)"):format(tostring(key))), 3)
    end
  end
  local capacity = options and options.capacity
  if capacity == nil then capacity = DEFAULT_CAPACITY end
  if math.type(capacity) ~= "integer" or capacity < 1 then
    error(core.ArgumentError(("net.BufferedWriter: invalid capacity %s: expected a positive integer"):format(tostring(capacity))), 3)
  end
  self._stream = stream
  self._capacity = capacity
  self._parts, self._size = {}, 0
  self._failure = nil
  self._closed = false
  self._lock = reactor.Mutex() -- keeps flushes, hence bytes, in order
end

--- Raises the earlier failure (as a fresh error) when the writer is poisoned, and the
--- `TransportError` (`EBADF`, as a closed `TcpStream` does) when it is closed.
---@param operation string  the public method, the stable `context.operation` of the closed error
---@private
function BufferedWriter:_check(operation)
  if self._failure then
    -- A fresh error: the stored failure may be a cancellation this caller is not subject to.
    error(core.NetworkError({ message = "net.BufferedWriter." .. operation .. ": the writer failed earlier and is poisoned", cause = self._failure }), 0)
  end
  if self._closed then
    error(reactor.TransportError({
      message = "net.BufferedWriter." .. operation .. ": EBADF: the writer is closed",
      context = { operation = operation, errno = "EBADF" },
    }), 0)
  end
end

--- Returns the number of bytes accepted but not yet flushed.
---@return integer
function BufferedWriter:buffered() return self._size end

--- Hands `data` to the stream; the caller holds the lock. A failure, a cancellation included,
--- poisons the writer: how much was sent is unknown (OQ-28).
---@async
---@param data string
---@private
function BufferedWriter:_send(data)
  local ok, err = pcall(self._stream.write, self._stream, data)
  if not ok then
    self._failure = err
    error(err, 0)
  end
end

--- Sends the buffered bytes; returns when the stream has accepted all of them (back-pressure).
---@async
function BufferedWriter:flush()
  self:_check("flush")
  local lock <close> = self._lock:lock()
  self:_check("flush")
  if self._size == 0 then return end
  local data = table.concat(self._parts)
  self._parts, self._size = {}, 0
  self:_send(data)
end

--- Appends `data`, flushing first when the buffer reaches its capacity. May suspend only
--- when it flushes. A payload of at least `capacity` bytes, written while nothing is buffered and
--- no flush is running, goes straight to the stream: the same ordering and failure rules, one copy
--- less.
---@async
---@param data string
function BufferedWriter:write(data)
  if type(data) ~= "string" then
    error(core.ArgumentError(("net.BufferedWriter.write: expects a string, got %s"):format(type(data))), 2)
  end
  self:_check("write")
  if self._size == 0 and #data >= self._capacity then
    local lock = self._lock:try_lock()
    if lock then
      -- Indicative (Lua 5.5): handing a 64 MiB payload over took 80 ms through the buffer (the
      -- `table.concat` copy) and no measurable time directly.
      local ok, err = pcall(self._send, self, data)
      lock:release()
      if not ok then error(err, 0) end
      return
    end
  end
  self._parts[#self._parts + 1] = data
  self._size = self._size + #data
  if self._size >= self._capacity then self:flush() end
end

--- Closes the writer. Unflushed bytes are discarded, never sent: flushing may suspend, and a
--- `<close>` handler must not suspend while its scope is cancelled (OQ-23). Call `flush`
--- first. Does not close the stream. Idempotent.
function BufferedWriter:close()
  self._closed = true
  self._parts, self._size = {}, 0
end

--- Closing the writer (`local writer <close> = ...`) calls `close`.
function BufferedWriter:__close() self:close() end

---@return boolean
function BufferedWriter:is_closed() return self._closed end

return core.finalise(BufferedWriter)
