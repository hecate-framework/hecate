-- hecate.http: HTTP/1.1 server and client with a message model following RFC 9110 semantics.
global <const> require

--- The HTTP message model (the server and the client follow in later steps).
---@class hecate.http
---@field Fields hecate.http.Fields  case-insensitive, multi-valued, ordered fields
---@field MediaType hecate.http.MediaType  parsed and formatted media types
---@field Status hecate.http.Status  status codes and reason phrases
---@field Cookie hecate.http.Cookie  Cookie parsing; `Cookie.SetCookie` formats Set-Cookie
---@field SetCookie hecate.http.SetCookie  a Set-Cookie field value
---@field Request hecate.http.Request  the request message
---@field Response hecate.http.Response  the response message
---@field Server hecate.http.Server  the HTTP/1.1 server
---@field ContentReader hecate.http.ContentReader  message content as a stream
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
http.ContentReader = require("hecate.http.content")
http.ContentError = http.ContentReader.ContentError
http.problem = require("hecate.http.problem")
http.Server = require("hecate.http.server")

return http
