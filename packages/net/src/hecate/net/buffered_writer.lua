-- BufferedWriter: coalesces small writes. Invariant (net/CLAUDE.md): a partial write never
-- leaks. `Stream:write` accepts all of its data or raises; when a flush fails, the number
-- of bytes the peer received is unknown, so the writer is poisoned: every later call raises
-- the same failure rather than sending bytes after a gap.
global <const> type, error, require, math, table, tostring, pcall

local core = require("hecate.core")
local reactor = require("hecate.reactor")

local DEFAULT_CAPACITY = 8 * 1024

---@class hecate.net.BufferedWriter
---@overload fun(stream: hecate.net.Stream, options?: { capacity?: integer }): hecate.net.BufferedWriter
local BufferedWriter = core.class("BufferedWriter")

--- Creates a writer over `stream`; the buffer is flushed when it reaches `capacity` bytes
--- (default 8192). The writer does not own the stream.
---@param stream hecate.net.Stream
---@param options? { capacity?: integer }
function BufferedWriter:init(stream, options)
  if type(stream) ~= "table" or type(stream.write) ~= "function" then
    error(core.ArgumentError("BufferedWriter expects a stream with a write method"), 3)
  end
  local capacity = options and options.capacity or DEFAULT_CAPACITY
  if math.type(capacity) ~= "integer" or capacity < 1 then
    error(core.ArgumentError(("invalid capacity %s: expected a positive integer"):format(tostring(capacity))), 3)
  end
  self._stream = stream
  self._capacity = capacity
  self._parts, self._size = {}, 0
  self._failure = nil
  self._closed = false
  self._lock = reactor.Mutex() -- keeps flushes, hence bytes, in order
end

---@return table?
function BufferedWriter:_check()
  if self._failure then error(self._failure, 0) end
  if self._closed then error(core.Error("the writer is closed"), 0) end
end

--- Returns the number of bytes accepted but not yet flushed.
---@return integer
function BufferedWriter:buffered() return self._size end

--- Sends the buffered bytes; returns when the stream has accepted all of them (back-pressure).
---@async
function BufferedWriter:flush()
  self:_check()
  local lock <close> = self._lock:lock()
  self:_check()
  if self._size == 0 then return end
  local data = table.concat(self._parts)
  self._parts, self._size = {}, 0
  local ok, err = pcall(self._stream.write, self._stream, data)
  if not ok then
    -- Cancelled or failed mid-write: how much was sent is unknown (OQ-28).
    self._failure = err
    error(err, 0)
  end
end

--- Appends `data`, flushing first when the buffer reaches its capacity. May suspend only
--- when it flushes.
---@async
---@param data string
function BufferedWriter:write(data)
  if type(data) ~= "string" then
    error(core.ArgumentError(("write expects a string, got %s"):format(type(data))), 2)
  end
  self:_check()
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

return core.finalise(BufferedWriter)
