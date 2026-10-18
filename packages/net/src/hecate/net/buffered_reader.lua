-- BufferedReader: line, exact-length and delimiter reads over a stream. Invariant
-- (net/CLAUDE.md): a partial read never leaks. A call returns a complete result or raises,
-- and whatever it had already received stays in the reader's buffer, so the next call
-- sees it again and nothing is lost or duplicated.
global <const> type, error, require, math, tostring, table

local core = require("hecate.core")
local reactor = require("hecate.reactor")
local errors = require("hecate.net.errors")

local CHUNK = 16 * 1024
local DEFAULT_LIMIT = 64 * 1024

--- Reads a stream with a buffer; a call returns a complete result or raises, never a part of it.
---@class hecate.net.BufferedReader
---@overload fun(stream: hecate.net.Stream, options?: { limit?: integer }): hecate.net.BufferedReader
local BufferedReader = core.class("BufferedReader")

--- Validates a length bound.
---@return integer
local function check_limit(limit, level)
  if math.type(limit) ~= "integer" or limit < 1 then
    error(core.ArgumentError(("invalid limit %s: expected a positive integer"):format(tostring(limit))), level)
  end
  return limit
end

--- Creates a reader over `stream`. `limit` bounds the length of a line or a delimited
--- record (default 65536 bytes), so a peer cannot make the reader buffer without bound; the
--- buffer may hold up to one chunk (16 KiB) more than the limit before the check fires.
--- The reader does not own the stream: closing the reader never closes the stream.
---@param stream hecate.net.Stream
---@param options? { limit?: integer }
function BufferedReader:init(stream, options)
  if type(stream) ~= "table" or type(stream.read) ~= "function" then
    error(core.ArgumentError("BufferedReader expects a stream with a read method"), 3)
  end
  self._stream = stream
  self._limit = check_limit(options and options.limit or DEFAULT_LIMIT, 3)
  -- Received bytes are `_buffer` from `_pos` on, then `_parts` (chunks not yet joined, `_extra`
  -- bytes in all): joining once per search or read, and consuming by offset, keeps reads linear.
  self._buffer = ""
  self._pos = 1
  self._parts = {}
  self._extra = 0
  self._eof = false
  self._closed = false
  self._lock = reactor.Mutex() -- one reader at a time: two consumers would split a record
end

--- Raises when the reader was closed.
---@private
function BufferedReader:_check()
  if self._closed then error(core.Error("the reader is closed"), 0) end
end

--- Number of bytes received and not yet consumed.
---@return integer
---@private
function BufferedReader:_size()
  return #self._buffer - self._pos + 1 + self._extra
end

--- Joins the pending chunks so that `_buffer` from `_pos` holds every unconsumed byte.
---@private
function BufferedReader:_join()
  if self._extra > 0 then
    self._buffer = self._buffer:sub(self._pos) .. table.concat(self._parts)
    self._pos = 1
    self._parts = {}
    self._extra = 0
  end
end

--- Removes and returns the first `count` unconsumed bytes (`count <= _size()`).
---@param count integer
---@return string
---@private
function BufferedReader:_take(count)
  self:_join()
  local data = self._buffer:sub(self._pos, self._pos + count - 1)
  self._pos = self._pos + count
  if self._pos > #self._buffer then self._buffer, self._pos = "", 1 end
  return data
end

--- Reads one chunk from the stream into the buffer; returns false at end of stream.
---@async
---@return boolean
---@private
function BufferedReader:_fill()
  if self._eof then return false end
  while true do
    local chunk = self._stream:read(CHUNK)
    if chunk == nil then
      self._eof = true
      return false
    end
    if #chunk > 0 then
      self._parts[#self._parts + 1] = chunk
      self._extra = self._extra + #chunk
      return true
    end
  end
end

--- Returns the number of bytes received but not yet consumed.
---@return integer
function BufferedReader:buffered() return self:_size() end

---@param wanted? integer
local function end_of_stream(self, wanted)
  error(errors.EndOfStreamError({
    message = "the stream ended before the read completed",
    context = { wanted = wanted, buffered = self:_size() },
  }), 0)
end

--- Reads up to and excluding `delimiter`, and consumes the delimiter. Returns nil if the
--- stream ended with nothing buffered; raises `EndOfStreamError` if it ended inside a
--- record (the bytes stay buffered), and `ProtocolError` if the record exceeds the limit.
---@async
---@param delimiter string  not empty
---@param limit? integer  overrides the reader's limit for this call
---@return string?
function BufferedReader:read_until(delimiter, limit)
  if type(delimiter) ~= "string" or delimiter == "" then
    error(core.ArgumentError("read_until expects a non-empty delimiter string"), 2)
  end
  limit = limit == nil and self._limit or check_limit(limit, 2)
  self:_check()
  local lock <close> = self._lock:lock()
  self:_check()
  local from = 0 -- offset, from the first unconsumed byte, where a delimiter could start
  while true do
    self:_join()
    local first, last = self._buffer:find(delimiter, self._pos + from, true)
    if first then
      local length = first - self._pos
      if length > limit then break end
      local record = self:_take(length)
      self._pos = self._pos + #delimiter
      if self._pos > #self._buffer then self._buffer, self._pos = "", 1 end
      return record
    end
    local size = self:_size()
    if size > limit then break end
    -- The delimiter may straddle two chunks: resume the search where it could start.
    from = math.max(0, size - #delimiter + 1)
    if not self:_fill() then
      if size == 0 then return nil end
      end_of_stream(self)
    end
  end
  error(core.ProtocolError({
    message = ("no delimiter within %d bytes"):format(limit),
    context = { limit = limit },
  }), 0)
end

--- Reads one line: up to a line feed, which is consumed together with a carriage return
--- before it (OQ-28). Same results and errors as `read_until`.
---@async
---@param limit? integer
---@return string?
function BufferedReader:read_line(limit)
  local line = self:read_until("\n", limit)
  if line ~= nil and line:sub(-1) == "\r" then line = line:sub(1, -2) end
  return line
end

--- Reads exactly `count` bytes. Raises `EndOfStreamError` if the stream ends first (the
--- bytes stay buffered). `count` is chosen by the caller and, unless `limit` is given, is not
--- subject to the reader's limit; pass `limit` when `count` comes from a peer (a frame length):
--- a larger `count` raises `ProtocolError` before anything is read.
---@async
---@param count integer  not negative
---@param limit? integer  largest `count` accepted
---@return string
function BufferedReader:read_exact(count, limit)
  if math.type(count) ~= "integer" or count < 0 then
    error(core.ArgumentError(("invalid count %s: expected an integer >= 0"):format(tostring(count))), 2)
  end
  if limit ~= nil then
    check_limit(limit, 2)
    if count > limit then
      error(core.ProtocolError({
        message = ("%d bytes requested, more than the limit of %d"):format(count, limit),
        context = { limit = limit, wanted = count },
      }), 0)
    end
  end
  self:_check()
  local lock <close> = self._lock:lock()
  self:_check()
  while self:_size() < count do
    if not self:_fill() then end_of_stream(self, count) end
  end
  return self:_take(count)
end

--- Returns what is buffered, or if nothing is, the next chunk from the stream; nil at end
--- of stream. The result is a whole number of received bytes, never a part of a record the
--- caller asked for.
---@async
---@param max? integer  at most this many bytes
---@return string?
function BufferedReader:read_some(max)
  self:_check()
  local lock <close> = self._lock:lock()
  self:_check()
  if self:_size() == 0 and not self:_fill() then return nil end
  local size = self:_size()
  return self:_take(max and math.min(max, size) or size)
end

--- Discards the buffered bytes; later reads raise. Does not close the stream. Idempotent.
function BufferedReader:close()
  self._buffer, self._pos, self._parts, self._extra = "", 1, {}, 0
  self._eof = true
  self._closed = true
end

--- Closing the reader (`local reader <close> = ...`) calls `close`.
function BufferedReader:__close() self:close() end

---@return boolean
function BufferedReader:is_closed() return self._closed end

return core.finalise(BufferedReader)
