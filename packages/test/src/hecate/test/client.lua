-- In-process HTTP client: serves a request to an action without a socket, through the same seam as the server
-- (`hecate.http.serve_request`, OQ-78), so a test exercises the code path of production.
global <const> require, type, error

local core = require("hecate.core")
local http = require("hecate.http")

--- Sends requests to an action in the calling computation (a test runs in a reactor), without a network.
--- The action is what `hecate.kernel.Application:boot()` returns, or any `fun(request): Response`.
---@class hecate.test.Client
---@overload fun(action: fun(request: hecate.http.Request): hecate.http.Response): hecate.test.Client
local Client = core.class("Client")

--- Options of one request.
---@class hecate.test.ClientRequestOptions
---@field fields? table<string, string|string[]>|hecate.http.Fields  request fields
---@field content? string  the content, as is
---@field json? any  a value encoded as JSON content (with `Content-Type: application/json` unless the fields set one); excludes `content`

--- Creates a client.
---@param action fun(request: hecate.http.Request): hecate.http.Response
function Client:init(action)
  if type(action) ~= "function" then
    error(core.ArgumentError("test.Client: expects an action (a function of a request), as returned by Application:boot()"), 3)
  end
  self._action = action
end

--- Serves a request and returns the response, and the failure the server would have logged (the action raised, or
--- returned something that cannot be sent: the response is then the generic 500 problem details response), or nil.
---
--- Raises `hecate.core.ArgumentError` for options that do not fit (`content` with `json`, a method or target that
--- `http.Request` refuses).
---@async
---@param method string  for example `"GET"`
---@param target string  the request-target, for example `"/users/42?expand=orders"`
---@param options? hecate.test.ClientRequestOptions
---@return hecate.http.Response response
---@return any? failure
function Client:request(method, target, options)
  options = options or {}
  if options.content ~= nil and options.json ~= nil then
    error(core.ArgumentError("test.Client: give content or json, not both"), 2)
  end
  local fields = options.fields
  if fields ~= nil and not core.is_instance_of(fields, http.Fields) then fields = http.Fields(fields) end
  local content = options.content
  if options.json ~= nil then
    content = require("hecate.json").encode(options.json)
    fields = fields or http.Fields()
    if not fields:has("content-type") then fields:set("Content-Type", "application/json") end
  end
  local request = http.Request({ method = method, target = target, fields = fields, content = content })
  return http.serve_request(self._action, request)
end

--- Shorthand of `request` with the method GET.
---@async
---@param target string
---@param options? hecate.test.ClientRequestOptions
---@return hecate.http.Response response
---@return any? failure
function Client:get(target, options) return self:request("GET", target, options) end

--- Shorthand of `request` with the method HEAD.
---@async
---@param target string
---@param options? hecate.test.ClientRequestOptions
---@return hecate.http.Response response
---@return any? failure
function Client:head(target, options) return self:request("HEAD", target, options) end

--- Shorthand of `request` with the method POST.
---@async
---@param target string
---@param options? hecate.test.ClientRequestOptions
---@return hecate.http.Response response
---@return any? failure
function Client:post(target, options) return self:request("POST", target, options) end

--- Shorthand of `request` with the method PUT.
---@async
---@param target string
---@param options? hecate.test.ClientRequestOptions
---@return hecate.http.Response response
---@return any? failure
function Client:put(target, options) return self:request("PUT", target, options) end

--- Shorthand of `request` with the method PATCH.
---@async
---@param target string
---@param options? hecate.test.ClientRequestOptions
---@return hecate.http.Response response
---@return any? failure
function Client:patch(target, options) return self:request("PATCH", target, options) end

--- Shorthand of `request` with the method DELETE.
---@async
---@param target string
---@param options? hecate.test.ClientRequestOptions
---@return hecate.http.Response response
---@return any? failure
function Client:delete(target, options) return self:request("DELETE", target, options) end

--- Shorthand of `request` with the method OPTIONS.
---@async
---@param target string
---@param options? hecate.test.ClientRequestOptions
---@return hecate.http.Response response
---@return any? failure
function Client:options(target, options) return self:request("OPTIONS", target, options) end

return core.finalise(Client)
