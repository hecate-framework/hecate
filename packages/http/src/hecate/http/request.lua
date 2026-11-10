-- The request message (RFC 9110, section 3.4; RFC 9112, section 3).
global <const> require, type, error, string, ipairs, pairs

local core = require("hecate.core")
local grammar = require("hecate.http.grammar")
local Fields = require("hecate.http.fields")
local Cookie = require("hecate.http.cookie")
local ContentStream = require("hecate.http.content")
local form = require("hecate.http.form")
local multipart = require("hecate.http.multipart")

--- A request. The server builds it from the wire; a client or a test builds it by hand.
---@class hecate.http.Request
---@field method string  a case-sensitive token, for example "GET" (RFC 9110, section 9.1)
---@field target string  the raw request-target, for example "/users/42?expand=orders" (RFC 9112, section 3.2)
---@field path string  the path component of the target, "/users/42": RAW, as received (not percent-decoded, not normalised: dot segments stay)
---@field query string?  the raw query component without `?` (not decoded), or nil when the target has none
---@field version string  protocol version, "HTTP/1.1" by default
---@field fields hecate.http.Fields
---@field content? string|table|function  the content; the server reads it from the stream
---@field parameters table  values declared by the route; the four keys path, query, fields, cookies
---@field scope? table  the scope of the request (one scope per request)
---@overload fun(options: hecate.http.RequestOptions): hecate.http.Request
local Request = core.class("Request")

---@class hecate.http.RequestOptions
---@field method? string  default "GET"
---@field target string
---@field fields? hecate.http.Fields
---@field content? string|table|function
---@field version? string
---@field scope? table
---@field peer_address? table
---@field content_stream? hecate.http.ContentStream  the content as a stream (the server passes one)

--- Initialises a request.
---
--- Raises `hecate.core.ArgumentError` for an invalid method or a target that is empty or holds
--- whitespace or control characters.
---@param options hecate.http.RequestOptions
function Request:init(options)
  if type(options) ~= "table" then error(core.ArgumentError("http.Request: expected an options table, as in http.Request({ method = \"GET\", target = \"/\" })"), 3) end
  local method = options.method or "GET"
  if not grammar.is_token(method) then error(core.ArgumentError("http.Request: the method must be a token"), 3) end
  local target = options.target
  if type(target) ~= "string" or target == "" or string.find(target, "[%c ]") then
    error(core.ArgumentError("http.Request: the target must be a non-empty string without whitespace or control characters"), 3)
  end
  self.method, self.target, self.version = method, target, options.version or "HTTP/1.1"
  self.path, self.query = string.match(target, "^([^?#]*)%??([^#]*)")
  if string.find(target, "?", 1, true) == nil then self.query = nil end
  self.fields = options.fields or Fields()
  self.content, self.scope = options.content, options.scope
  self._peer_address = options.peer_address
  self._content_stream = options.content_stream
  self.parameters = { path = {}, query = {}, fields = {}, cookies = {} }
end

--- Returns the address of the connection's peer, or nil when unknown.
---@return table?
function Request:peer_address()
  return self._peer_address
end

--- Returns a reader of the content, chunk by chunk (`reader:read()` returns nil at the end). A request built by
--- hand reads its string `content`; one without content reads nothing.
---
--- Raises `hecate.http.ContentError` (`context.reason` `consumed`) once `set_validated_content` was called: the
--- content was read and validated by the kernel, `content` holds the result.
---@return hecate.http.ContentStream
function Request:stream_content()
  if self._content_validated then
    error(ContentStream.ContentError({
      message = "http.Request: the content was already validated and consumed",
      context = { status = 500, reason = "consumed" },
    }), 2)
  end
  if self._content_stream == nil then
    self._content_stream = ContentStream.of(type(self.content) == "string" and self.content or "")
  end
  return self._content_stream
end

--- Records the validated content of the request (the kernel calls it after it has read the content and validated it
--- with the schema of the route): `content` becomes `value`, and the raw content is closed, so that `stream_content`,
--- `read_content`, `read_form` and `stream_parts` raise `hecate.http.ContentError` (reason `consumed`) instead of
--- returning nothing (OQ-76 b). A route without a content schema never calls it and keeps its stream untouched.
---@param value any
function Request:set_validated_content(value)
  self.content = value
  self._content_validated = true
end

--- Reads the whole content into a string, bounded by the limit of the server (and by `limit` when it is lower).
---
--- Raises `hecate.http.ContentError` beyond the limit (status 413) or when the content cannot be read.
---@async
---@param limit? integer  bytes
---@return string
function Request:read_content(limit)
  return self:stream_content():read_all(limit)
end

--- Reads an `application/x-www-form-urlencoded` request into a `Form`, bounded by `limits.max_size` (default 1 MiB, and
--- the `max_content` of the server) and `limits.max_pairs` (default 1000).
---
--- Raises `hecate.http.FormError`: `unsupported_media_type` (415) for any other `Content-Type`, `bad_percent_encoding`,
--- `invalid_utf8` and `nul_in_value` (400), `too_many_pairs` and `too_large` (413); `hecate.http.ContentError` (413) beyond
--- the size limit while reading. The server answers all of them with problem details that echo nothing of the input.
---@async
---@param limits? hecate.http.form.UrlencodedLimits
---@return hecate.http.Form
function Request:read_form(limits)
  local media = self:media_type()
  if media == nil or media:essence() ~= "application/x-www-form-urlencoded" then
    error(form.failure("unsupported_media_type", "the content is not application/x-www-form-urlencoded"), 2)
  end
  local max_size = limits and limits.max_size or form.DEFAULTS.max_size
  return form.parse_urlencoded(self:read_content(max_size), limits)
end

--- Reads a `multipart/form-data` request part by part (see `hecate.http.multipart`): the parts are read lazily from the
--- content stream, with `limits` (parts, part header fields size, part size, total size; defaults in `multipart.DEFAULTS`).
---
--- Raises `hecate.http.FormError` (`unsupported_media_type`, 415; `bad_boundary`, 400) at once; the reader raises the
--- others as the parts are read.
---@param limits? hecate.http.multipart.MultipartLimits
---@return hecate.http.multipart.Reader
function Request:stream_parts(limits)
  return multipart.parts(self:stream_content(), self:media_type(), limits)
end

--- Returns the cookies sent by the client: every `Cookie` line parsed (RFC 6265, section 4.2.1).
---@return table<string, string> cookies
function Request:cookies()
  local all = {}
  for _, line in ipairs(self.fields:get_all("Cookie")) do
    for name, value in pairs((Cookie.parse(line))) do
      if all[name] == nil then all[name] = value end
    end
  end
  return all
end

--- Returns the media type of the content from `Content-Type`, or nil when absent or malformed.
---@return hecate.http.MediaType?
function Request:media_type()
  local value = self.fields:get("Content-Type")
  if value == nil then return nil end
  return (require("hecate.http.media_type").parse(value))
end

return core.finalise(Request)
