-- BufferedReader: line, exact-length and delimiter reads over a stream. Invariant
-- (net/CLAUDE.md): a partial read never leaks. A call returns a complete result or raises,
-- and whatever it had already received stays in the reader's buffer, so the next call
-- sees it again and nothing is lost or duplicated.
global <const> type, error, require, math, tostring

local core = require("hecate.core")
local reactor = require("hecate.reactor")
local errors = require("hecate.net.errors")

local CHUNK = 16 * 1024
local DEFAULT_LIMIT = 64 * 1024

---@class hecate.net.BufferedReader
---@overload fun(stream: hecate.net.Stream, options?: { limit?: integer }): hecate.net.BufferedReader
local BufferedReader = core.class("BufferedReader")

--- Creates a reader over `stream`. `limit` bounds the length of a line or a delimited
--- record (default 65536 bytes), so a peer cannot make the reader buffer without bound.
--- The reader does not own the stream: closing the reader never closes the stream.
---@param stream hecate.net.Stream
---@param options? { limit?: integer }
function BufferedReader:init(stream, options)
  if type(stream) ~= "table" or type(stream.read) ~= "function" then
    error(core.ArgumentError("BufferedReader expects a stream with a read method"), 3)
  end
  local limit = options and options.limit or DEFAULT_LIMIT
  if math.type(limit) ~= "integer" or limit < 1 then
    error(core.ArgumentError(("invalid limit %s: expected a positive integer"):format(tostring(limit))), 3)
  end
  self._stream = stream
  self._limit = limit
  self._buffer = ""
  self._eof = false
  self._lock = reactor.Mutex() -- one reader at a time: two consumers would split a record
end

--- Reads one chunk from the stream into the buffer; returns false at end of stream.
---@async
---@return boolean
function BufferedReader:_fill()
  if self._eof then return false end
  while true do
    local chunk = self._stream:read(CHUNK)
    if chunk == nil then
      self._eof = true
      return false
    end
    if #chunk > 0 then
      self._buffer = self._buffer .. chunk
      return true
    end
  end
end

--- Returns the number of bytes received but not yet consumed.
---@return integer
function BufferedReader:buffered() return #self._buffer end

---@param wanted? integer
local function end_of_stream(self, wanted)
  error(errors.EndOfStreamError({
    message = "the stream ended before the read completed",
    context = { wanted = wanted, buffered = #self._buffer },
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
  limit = limit or self._limit
  local lock <close> = self._lock:lock()
  local from = 1
  while true do
    local first, last = self._buffer:find(delimiter, from, true)
    if first then
      if first - 1 > limit then break end
      local record = self._buffer:sub(1, first - 1)
      self._buffer = self._buffer:sub(last + 1)
      return record
    end
    if #self._buffer > limit then break end
    -- The delimiter may straddle two chunks: resume the search where it could start.
    from = math.max(1, #self._buffer - #delimiter + 2)
    if not self:_fill() then
      if #self._buffer == 0 then return nil end
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
--- bytes stay buffered). `count` is chosen by the caller and is not subject to the limit.
---@async
---@param count integer  not negative
---@return string
function BufferedReader:read_exact(count)
  if math.type(count) ~= "integer" or count < 0 then
    error(core.ArgumentError(("invalid count %s: expected an integer >= 0"):format(tostring(count))), 2)
  end
  local lock <close> = self._lock:lock()
  while #self._buffer < count do
    if not self:_fill() then end_of_stream(self, count) end
  end
  local data = self._buffer:sub(1, count)
  self._buffer = self._buffer:sub(count + 1)
  return data
end

--- Returns what is buffered, or if nothing is, the next chunk from the stream; nil at end
--- of stream. The result is a whole number of received bytes, never a part of a record the
--- caller asked for.
---@async
---@param max? integer  at most this many bytes
---@return string?
function BufferedReader:read_some(max)
  local lock <close> = self._lock:lock()
  if #self._buffer == 0 and not self:_fill() then return nil end
  local count = max and math.min(max, #self._buffer) or #self._buffer
  local data = self._buffer:sub(1, count)
  self._buffer = self._buffer:sub(count + 1)
  return data
end

--- Discards the buffered bytes. Does not close the stream. Idempotent.
function BufferedReader:close()
  self._buffer = ""
  self._eof = true
end

--- Closing the reader (`local reader <close> = ...`) calls `close`.
function BufferedReader:__close() self:close() end

return core.finalise(BufferedReader)
