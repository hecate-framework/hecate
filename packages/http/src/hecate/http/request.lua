-- The request message (RFC 9110, section 3.4; RFC 9112, section 3).
global <const> require, type, error, string, ipairs, pairs

local core = require("hecate.core")
local grammar = require("hecate.http.grammar")
local Fields = require("hecate.http.fields")
local Cookie = require("hecate.http.cookie")
local ContentReader = require("hecate.http.content")

--- A request. The server builds it from the wire; a client or a test builds it by hand.
---@class hecate.http.Request
---@field method string  an uppercase-sensitive token, for example "GET" (RFC 9110, section 9.1)
---@field target string  the raw request-target, for example "/users/42?expand=orders" (RFC 9112, section 3.2)
---@field path string  the path component of the target, "/users/42"
---@field query string?  the raw query component without `?`, or nil when the target has none
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
---@field content_reader? hecate.http.ContentReader  the content as a stream (the server passes one)

--- Initialises a request.
---
--- Raises `hecate.core.ArgumentError` for an invalid method or a target that is empty or holds
--- whitespace or control characters.
---@param options hecate.http.RequestOptions
function Request:init(options)
  if type(options) ~= "table" then error(core.ArgumentError("http.Request: expected an options table"), 3) end
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
  self._content_reader = options.content_reader
  self.parameters = { path = {}, query = {}, fields = {}, cookies = {} }
end

--- Returns the address of the connection's peer, or nil when unknown.
---@return table?
function Request:peer_address()
  return self._peer_address
end

--- Returns a reader of the content, chunk by chunk (`reader:read()` returns nil at the end). A request built by
--- hand reads its string `content`; one without content reads nothing.
---@return hecate.http.ContentReader
function Request:content_reader()
  if self._content_reader == nil then
    self._content_reader = ContentReader.of(type(self.content) == "string" and self.content or "")
  end
  return self._content_reader
end

--- Reads the whole content into a string, bounded by the limit of the server (and by `limit` when it is lower).
---
--- Raises `hecate.http.ContentError` beyond the limit (status 413) or when the content cannot be read.
---@async
---@param limit? integer  bytes
---@return string
function Request:read_content(limit)
  return self:content_reader():read_all(limit)
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
