-- The content of a message as a stream (RFC 9110, section 6.4; RFC 9112, section 6).
global <const> require, type, error, math, table, pcall

local core = require("hecate.core")

--- The content of a message could not be read: it exceeds the limit, ended early, was malformed or stalled.
--- `context.reason` is a stable identifier (`too_large`, `timeout`, `truncated`, `malformed`) and `context.limit` is
--- set for `too_large`. On the server, `context.status` is the status code to answer with (413, 408 or 400); the
--- client raises it for a response (`too_large` beyond `max_content`, `timeout` when the content stalls longer than
--- `content_timeout`) without a status, which is the server's to give (OQ-82).
---@class hecate.http.ContentError : hecate.core.ProtocolError
---@field context { status?: integer, reason: string, limit?: integer }
local ContentError = core.error_class("ContentError", "hecate.http.ContentError", core.ProtocolError)

--- A stream of message content: an ordered sequence of bytes read in order, chunk by chunk. A server creates one per request; a request built by hand
--- gets one over its string content.
---@class hecate.http.ContentStream
---@overload fun(pull: fun(): (string?), options?: { limit?: integer, client?: boolean }): hecate.http.ContentStream
local ContentStream = core.class("ContentStream")
ContentStream.ContentError = ContentError

--- Creates a reader. `pull` returns the next chunk (never empty) or nil at the end of the content; it may
--- suspend. `options.limit` bounds the total number of bytes the reader delivers (no default: the server passes its own).
--- `options.client` is true for the content of a response read by a client: its `ContentError` then carries no
--- `context.status` (default false: a `too_large` error carries 413).
---@param pull fun(): string?
---@param options? { limit?: integer, client?: boolean }
function ContentStream:init(pull, options)
  if type(pull) ~= "function" then error(core.ArgumentError("http.ContentStream: expected a pull function"), 3) end
  local limit = options and options.limit
  if limit ~= nil and (math.type(limit) ~= "integer" or limit < 0) then
    error(core.ArgumentError("http.ContentStream: limit must be a non-negative integer"), 3)
  end
  local client = options and options.client
  if client ~= nil and type(client) ~= "boolean" then
    error(core.ArgumentError("http.ContentStream: client must be a boolean"), 3)
  end
  self._pull = pull
  self._limit = limit
  self._too_large_status = not client and 413 or nil
  self._total = 0
  self._finished = false
  self._started = false
  self._failure = nil
end

--- A reader over a string held in memory.
---@param text string
---@return hecate.http.ContentStream
function ContentStream.of(text)
  local sent = text == ""
  return ContentStream(function()
    if sent then return nil end
    sent = true
    return text
  end)
end

--- Returns the next chunk, or nil at the end of the content. A failure is sticky.
---
--- Raises `hecate.http.ContentError` when the limit is exceeded or the content cannot be read; the error of the
--- transport or the parser that stopped the content is raised as it came.
---@async
---@return string? chunk
function ContentStream:read()
  if self._failure ~= nil then error(self._failure, 0) end
  if self._finished then return nil end
  self._started = true
  local ok, chunk = pcall(self._pull)
  if not ok then
    self._failure = chunk
    error(chunk, 0)
  end
  if chunk == nil then
    self._finished = true
    return nil
  end
  self._total = self._total + #chunk
  if self._limit ~= nil and self._total > self._limit then
    self._failure = ContentError({
      message = "http.ContentStream: the content exceeds its limit",
      context = { status = self._too_large_status, reason = "too_large", limit = self._limit },
    })
    error(self._failure, 0)
  end
  return chunk
end

--- Reads the rest of the content into one string. `limit` (bytes) lowers the limit of the reader for this call.
---
--- Raises `hecate.http.ContentError` (`too_large`) beyond the smaller of the two limits.
---@async
---@param limit? integer
---@return string content
function ContentStream:read_all(limit)
  if limit ~= nil and (math.type(limit) ~= "integer" or limit < 0) then
    error(core.ArgumentError("http.ContentStream:read_all: limit must be a non-negative integer"), 2)
  end
  local parts, size = {}, 0
  while true do
    local chunk = self:read()
    if chunk == nil then break end
    size = size + #chunk
    if limit ~= nil and size > limit then
      error(ContentError({
        message = "http.ContentStream: the content exceeds its limit",
        context = { status = self._too_large_status, reason = "too_large", limit = limit },
      }), 2)
    end
    parts[#parts + 1] = chunk
  end
  return table.concat(parts)
end

--- Reports whether the end of the content was reached.
---@return boolean
function ContentStream:is_finished() return self._finished end

--- Reports whether a read was attempted.
---@return boolean
function ContentStream:is_started() return self._started end

--- Returns the number of bytes delivered so far.
---@return integer
function ContentStream:consumed() return self._total end

return core.finalise(ContentStream)
