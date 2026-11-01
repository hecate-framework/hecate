-- BufferedWriter: coalesces small writes. Invariant (net/CLAUDE.md): a partial write never
-- leaks. `Stream:write` accepts all of its data or raises; when a flush fails, the number
-- of bytes the peer received is unknown, so the writer is poisoned: every later call raises
-- the same failure rather than sending bytes after a gap.
global <const> type, error, require, math, table, tostring, pcall, pairs

local core = require("hecate.core")
local reactor = require("hecate.reactor")

-- 16 KiB, one TLS record of plaintext (RFC 8446 section 5.1): a flush over a `TlsStream` fills a record. The owner
-- chose it on 2026-11-01 from the `net/buffered-writer` sweep (4 KiB, Go's `bufio` default, was clearly slower than
-- 8 KiB, and throughput rose up to 16 to 32 KiB); the cost is up to 16 KiB held per writer with a full buffer.
local DEFAULT_CAPACITY = 16 * 1024
-- Seconds `close` may spend flushing under `reactor.shield` (OQ-29 (5)). Not decided by the owner:
-- the conservative value recorded in docs/open-questions.md, to be confirmed.
local DEFAULT_CLOSE_TIMEOUT = 5

--- Options of a `BufferedWriter`.
---@class hecate.net.BufferedWriterOptions
---@field capacity? integer  bytes buffered before a flush, default 16384
---@field close_timeout? number  seconds `close` may take to flush the buffered bytes, default 5

--- Writes a stream through a buffer; a failed flush poisons the writer so that no partial write goes unnoticed.
---@class hecate.net.BufferedWriter
---@overload fun(stream: hecate.net.Stream, options?: hecate.net.BufferedWriterOptions): hecate.net.BufferedWriter
local BufferedWriter = core.class("BufferedWriter")

--- Creates a writer over `stream`; the buffer is flushed when it reaches `capacity` bytes
--- (default 16384). `close_timeout` (positive finite seconds, default 5) bounds the flush `close` performs. A payload of at least `capacity` bytes written while nothing is buffered goes
--- to the stream directly, without a copy. The writer does not own the stream.
---@param stream hecate.net.Stream
---@param options? hecate.net.BufferedWriterOptions
function BufferedWriter:init(stream, options)
  if type(stream) ~= "table" or type(stream.write) ~= "function" then
    error(core.ArgumentError("net.BufferedWriter: expects a stream with a write method"), 3)
  end
  if options ~= nil and type(options) ~= "table" then
    error(core.ArgumentError(("net.BufferedWriter: expects an options table, got %s"):format(type(options))), 3)
  end
  for key in pairs(options or {}) do
    if key ~= "capacity" and key ~= "close_timeout" then
      error(core.ArgumentError(("net.BufferedWriter: unknown option %s (options: capacity, close_timeout)"):format(tostring(key))), 3)
    end
  end
  local capacity = options and options.capacity
  if capacity == nil then capacity = DEFAULT_CAPACITY end
  if math.type(capacity) ~= "integer" or capacity < 1 then
    error(core.ArgumentError(("net.BufferedWriter: invalid capacity %s: expected a positive integer"):format(tostring(capacity))), 3)
  end
  local close_timeout = options and options.close_timeout
  if close_timeout == nil then close_timeout = DEFAULT_CLOSE_TIMEOUT end
  if type(close_timeout) ~= "number" or close_timeout ~= close_timeout or close_timeout <= 0 or close_timeout == math.huge then
    error(core.ArgumentError(("net.BufferedWriter: invalid close_timeout %s: expected a positive finite number of seconds"):format(tostring(close_timeout))), 3)
  end
  self._stream = stream
  self._close_timeout = close_timeout
  self._capacity = capacity
  self._parts, self._size = {}, 0
  self._failure = nil
  self._closed = false
  self._closing = false -- `close` is flushing: other tasks are refused, the flush itself is not
  self._lock = reactor.Mutex() -- keeps flushes, hence bytes, in order
end

--- Raises the earlier failure (as a fresh error) when the writer is poisoned, and the
--- `TransportError` (`EBADF`, as a closed `TcpStream` does) when it is closed.
---@param operation string  the public method, the stable `context.operation` of the closed error
---@private
function BufferedWriter:_check(operation)
  -- Closed first: a poisoned writer that was then closed is closed, as the package invariant states.
  if self._closed or self._closing then
    error(reactor.TransportError({
      message = "net.BufferedWriter." .. operation .. ": EBADF: the writer is closed",
      context = { operation = operation, errno = "EBADF" },
    }), 0)
  end
  if self._failure then
    -- A fresh error: the stored failure may be a cancellation this caller is not subject to.
    error(core.NetworkError({ message = "net.BufferedWriter." .. operation .. ": the writer failed earlier and is poisoned", cause = self._failure }), 0)
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
  self:_drain("flush")
end

--- Takes the lock and sends the buffered bytes. `operation` is the public method to check against
--- again once the lock is held (a `close` may have started meanwhile); `nil` skips the check, for the
--- flush `close` performs itself.
---@async
---@param operation? string
---@private
function BufferedWriter:_drain(operation)
  local lock <close> = self._lock:lock()
  if operation then
    self:_check(operation)
  elseif self._failure then
    return -- poisoned while `close` waited for the lock: reported already
  end
  if self._size == 0 then return end
  local data = table.concat(self._parts)
  self._parts, self._size = {}, 0
  self:_send(data)
end

--- Appends `data`, flushing first when the buffer reaches its capacity. May suspend only
--- when it flushes. Raises `TransportError` (`EBADF`) once `close` has started. A payload of at least `capacity` bytes, written while nothing is buffered and
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

--- Closes the writer after flushing the buffered bytes under `reactor.shield`, so the flush
--- completes even when the enclosing scope is cancelled, and `close_timeout` bounds it: a stuck
--- peer cannot block shutdown (OQ-23, OQ-29 (5)). The writer is closed whatever happens. A failed
--- flush, or an expired `close_timeout` (`hecate.core.DeadlineExceededError`), is raised once and
--- the unsent bytes are dropped; a poisoned writer is closed without raising (its failure was
--- reported already). Nothing buffered: no suspension, so this may be called outside a reactor.
--- Does not close the stream. Idempotent.
---@async
function BufferedWriter:close()
  if self._closed or self._closing then return end
  if self._failure or self._size == 0 then
    self._closed = true
    self._parts, self._size = {}, 0
    return
  end
  -- From here a `write` or `flush` by another task raises EBADF instead of being silently dropped.
  self._closing = true
  local ok, err = pcall(reactor.shield, self._close_timeout, self._drain, self)
  self._closed = true
  self._parts, self._size = {}, 0
  if not ok then error(err, 0) end
end

--- Closing the writer (`local writer <close> = ...`) calls `close`. When the scope is left by an error or a
--- cancellation (`err` is the error being propagated), the flush still happens under the shield but its failure
--- is swallowed: it must not replace the `CancellationError` or `DeadlineExceededError` in flight, nor
--- cancel siblings. On a normal exit the failure is raised, as `close` does.
---@async
---@param err? any  the error propagating out of the scope
function BufferedWriter:__close(err)
  if err == nil then return self:close() end
  pcall(self.close, self)
end

--- Returns whether the writer is closed.
---@return boolean
function BufferedWriter:is_closed() return self._closed end

return core.finalise(BufferedWriter)
