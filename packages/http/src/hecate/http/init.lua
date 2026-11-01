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
---@field Client hecate.http.Client  the HTTP/1.1 client
---@field form hecate.http.form  application/x-www-form-urlencoded
---@field multipart hecate.http.multipart  multipart/form-data
---@field Form hecate.http.Form  an ordered multi-map of form pairs
---@field FormError hecate.http.FormError  form content refused (400, 413, 415)
---@field url hecate.http.url  URL parsing and resolution
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
http.Server = require("hecate.http.server")
http.Client = require("hecate.http.client")
http.url = require("hecate.http.url")
http.form = require("hecate.http.form")
http.multipart = require("hecate.http.multipart")
http.Form = http.form.Form
http.FormError = http.form.FormError

return http
