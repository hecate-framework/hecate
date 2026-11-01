-- The response message (RFC 9110, section 3.4; RFC 9112, section 4).
global <const> require, error

local core = require("hecate.core")
local Fields = require("hecate.http.fields")
local Status = require("hecate.http.status")

--- A response. `content` is a string, a table (serialised by the kernel) or a writer function.
---@class hecate.http.Response
---@field status integer  100..599
---@field reason string  the reason phrase; defaults to the registered one, or "" (RFC 9112, section 4)
---@field fields hecate.http.Fields
---@field content? string|table|function
---@overload fun(status?: integer, options?: hecate.http.ResponseOptions): hecate.http.Response
local Response = core.class("Response")

---@class hecate.http.ResponseOptions
---@field fields? hecate.http.Fields
---@field content? string|table|function
---@field reason? string

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
    error(core.ArgumentError("http.Response: status " .. status .. " never has content (RFC 9110, section 6.4.1)"), 3)
  end
  self.status = status
  self.reason = options.reason or Status.reason(status) or ""
  self.fields = options.fields or Fields()
  self.content = options.content
end

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
