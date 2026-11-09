-- The response message (RFC 9110, section 3.4; RFC 9112, section 4).
global <const> require, error, type, pcall

local core = require("hecate.core")
local Fields = require("hecate.http.fields")
local Status = require("hecate.http.status")
local ContentStream = require("hecate.http.content")
local MediaType = require("hecate.http.media_type")
local json = require("hecate.json")

--- A response. `content` is a string or a function that streams (`content(write, flush)`). `http` never
--- serialises (OQ-76 a): a table as content is for a layer above, the kernel, that serialises it by content negotiation; a table
--- that reaches the server is an error (a generic 500 problem details response and a log entry, see `hecate.http.dispatch`). A response of the client has no `content`: it
--- is read with `read_content`, `read_json` or `stream_content`.
---@class hecate.http.Response
---@field status integer  100..599
---@field reason string  the reason phrase; defaults to the registered one, or "" (RFC 9112, section 4)
---@field fields hecate.http.Fields
---@field content? string|table|function
---@field url? string  the URL that answered, for a response of the client
---@overload fun(status?: integer, options?: hecate.http.ResponseOptions): hecate.http.Response
local Response = core.class("Response")

---@class hecate.http.ResponseOptions
---@field fields? hecate.http.Fields
---@field content? string|table|function
---@field reason? string
---@field content_stream? hecate.http.ContentStream  INTERNAL, do not use: the content read lazily (the client passes one)
---@field discard? fun()  INTERNAL, do not use: called by `close` when the content was not read to its end (the client drops the connection)
---@field max_content? integer  INTERNAL, do not use: default limit of `read_content` for a stream

--- Initialises a response.
---
--- Raises `hecate.core.ArgumentError` for a status outside 100..599, or for content on a status
--- that never has content (1xx, 204, 304; RFC 9110, section 6.4.1).
---@param status? integer  default 200
---@param options? hecate.http.ResponseOptions
function Response:init(status, options)
  status = status or 200
  options = options or {}
  if not Status.is_valid(status) then
    error(core.ArgumentError("http.Response: the status must be an integer from 100 to 599"), 3)
  end
  if options.content ~= nil and Status.forbids_content(status) then
    error(core.ArgumentError("http.Response: status " .. status .. " never has content (RFC 9110, section 6.4.1); return a Response without content"), 3)
  end
  self.status = status
  self.reason = options.reason or Status.reason(status) or ""
  self.fields = options.fields or Fields()
  self.content = options.content
  self._content_stream = options.content_stream
  self._discard = options.discard
  self._max_content = options.max_content
end

--- Returns the content as a stream, chunk by chunk (`read()` returns nil at the end). A response of the client holds its
--- connection until the stream is read to its end or the response is closed. A response built by hand streams its string
--- `content`.
---@return hecate.http.ContentStream
function Response:stream_content()
  if self._content_stream == nil then
    self._content_stream = ContentStream.of(type(self.content) == "string" and self.content or "")
  end
  return self._content_stream
end

--- Reads the whole content into a string, bounded by `limit` (default: the `max_content` of the client for a client
--- response). Raises `hecate.http.ContentError` (status 413, `too_large`) beyond the limit, and the failure of the
--- connection when the content cannot be read.
---@async
---@param limit? integer  bytes
---@return string
function Response:read_content(limit)
  if type(self.content) == "string" then return self.content --[[@as string]] end
  local stream = self:stream_content()
  local ok, content = pcall(stream.read_all, stream, limit or self._max_content)
  if not ok then
    self:close() -- the content could not be read to its end: the connection cannot be reused
    error(content, 0)
  end
  return content
end

--- Returns the media type of the content from `Content-Type`, or nil when absent or malformed.
---@return hecate.http.MediaType?
function Response:media_type()
  local value = self.fields:get("Content-Type")
  if value == nil then return nil end
  return (MediaType.parse(value))
end

--- Reads the whole content (bounded like `read_content`) and decodes it as JSON.
---
--- Raises `hecate.core.ProtocolError` with the reason `invalid_json` when the content is not valid JSON (the message holds
--- none of it), and what `read_content` raises.
---@async
---@param limit? integer  bytes
---@return any value
function Response:read_json(limit)
  local text = self:read_content(limit)
  local ok, value = pcall(json.decode, text)
  if not ok then
    error(core.ProtocolError({ message = "http.Response:read_json: the content is not valid JSON", context = { reason = "invalid_json" } }), 2)
  end
  return value
end

--- Gives the connection back: a response whose content was not read to its end drops the connection (it cannot be
--- reused). Idempotent, never suspends; also the `<close>` protocol.
function Response:close()
  local discard = self._discard
  self._discard = nil
  if discard ~= nil and not (self._content_stream and self._content_stream:is_finished()) then discard() end
end

--- Closes at the end of a `<close>` scope.
function Response:__close() self:close() end

--- Adds a `Set-Cookie` line (RFC 6265, section 4.1); one line per cookie, never combined.
---@param cookie hecate.http.SetCookie
---@return hecate.http.Response self
function Response:set_cookie(cookie)
  self.fields:add("Set-Cookie", cookie:format())
  return self
end

--- Reports whether the status is in the 2xx class.
---@return boolean
function Response:is_successful()
  return self.status >= 200 and self.status < 300
end

return core.finalise(Response)
