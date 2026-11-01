-- hecate.http: HTTP/1.1 server and client with a message model following RFC 9110 semantics.
global <const> require, type, pcall, error, string

--- HTTP/1.1: the message model, content streams, forms, problem details, and, when the native module is built, the parser,
--- the server and the client. The message model, forms, cookies and `Fields` need no native module: without it `Parser`,
--- `Server` and `Client` are nil and `http.available()` says why (`lua tools/run.lua build-native http`).
---@class hecate.http
---@field Fields hecate.http.Fields  case-insensitive, multi-valued, ordered fields
---@field MediaType hecate.http.MediaType  parsed and formatted media types
---@field Status hecate.http.Status  status codes and reason phrases
---@field Cookie hecate.http.Cookie  Cookie parsing; `Cookie.SetCookie` formats Set-Cookie
---@field SetCookie hecate.http.SetCookie  a Set-Cookie field value
---@field Request hecate.http.Request  the request message
---@field Response hecate.http.Response  the response message
---@field Server? hecate.http.Server  the HTTP/1.1 server (needs the native module)
---@field Client? hecate.http.Client  the HTTP/1.1 client (needs the native module)
---@field Parser? hecate.http.Parser  the llhttp parser (needs the native module)
---@field ParseError hecate.http.ParseError  a message llhttp refused or a parser limit exceeded (a `ProtocolError`)
---@field form hecate.http.forms  application/x-www-form-urlencoded
---@field multipart hecate.http.multipart  multipart/form-data
---@field Form hecate.http.Form  an ordered multi-map of form pairs
---@field FormError hecate.http.FormError  form content refused (400, 413, 415)
---@field url hecate.http.urls  URL parsing and resolution
---@field ContentStream hecate.http.ContentStream  message content as a stream
---@field ContentError hecate.http.ContentError  content over its limit, truncated, malformed or stalled
---@field problem hecate.http.problem  RFC 9457 problem details responses
local http = {}

http.Fields = require("hecate.http.fields")
http.MediaType = require("hecate.http.media_type")
http.Status = require("hecate.http.status")
http.Cookie = require("hecate.http.cookie")
http.SetCookie = http.Cookie.SetCookie
http.Request = require("hecate.http.request")
http.Response = require("hecate.http.response")
http.ContentStream = require("hecate.http.content")
http.ContentError = http.ContentStream.ContentError
http.problem = require("hecate.http.problem")
http.ParseError = require("hecate.http.errors").ParseError
http.url = require("hecate.http.url")
http.form = require("hecate.http.form")
http.multipart = require("hecate.http.multipart")
http.Form = http.form.Form
http.FormError = http.form.FormError

local native_failure

--- Loads a module that needs the native parser; nil when that module is not built (any other failure is raised).
---@param name string
---@return any?
local function optional(name)
  local ok, result = pcall(require, name)
  if ok then return result end
  if type(result) == "string" and string.find(result, "hecate.http.native", 1, true) then
    native_failure = native_failure or result
    return nil
  end
  error(result, 0)
end

http.Parser = optional("hecate.http.parser")
http.Server = optional("hecate.http.server")
http.Client = optional("hecate.http.client")

--- Reports whether the native module is built, so that `Parser`, `Server` and `Client` exist. Returns `true`, or `false`
--- and the reason.
---@return boolean available
---@return string? reason
function http.available()
  if http.Parser ~= nil then return true end
  local first = string.match(native_failure or "", "^[^\n]*")
  return false, first .. " (run `lua tools/run.lua build-native http`)"
end

return http
