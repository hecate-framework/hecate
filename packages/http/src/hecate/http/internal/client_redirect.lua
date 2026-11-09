-- The redirect loop of the client: follows 301, 302, 303, 307 and 308 (RFC 9110, section 15.4) up to `max_redirects`,
-- strips credentials when the origin changes and refuses loops and downgrades.
-- Internal to `hecate.http`: not public API. Only `client.lua` requires it.
global <const> require, type, error, ipairs, string, tostring

local url = require("hecate.http.url")
local connections = require("hecate.http.internal.client_connection")

local protocol_error = connections.protocol_error

---@class hecate.http.internal.client_redirect
local M = {}

local ENTITY_FIELDS <const> = { "Content-Type", "Content-Length", "Content-Encoding", "Content-Language", "Content-Location", "Transfer-Encoding", "Expect" }

--- Sends the request and follows its redirects; returns the final response. `options` are the (validated) options of
--- `Client:request`; `state` holds the per-request deadline and limits.
---@async
---@param self hecate.http.Client
---@param parts table  the parsed URL
---@param method string
---@param fields hecate.http.Fields
---@param content any
---@param state table
---@param options table
---@return hecate.http.Response
function M.follow(self, parts, method, fields, content, state, options)
  local visited = {}
  for hop = 0, state.max_redirects do
    local response = self:_exchange(parts, method, fields, content, state, parts.origin .. parts.target)
    local status = response.status
    local location = response.fields:get("Location")
    local follows = options.redirects ~= false and location ~= nil
      and (status == 301 or status == 302 or status == 303 or status == 307 or status == 308)
    if not follows then return response end
    -- 307 and 308 repeat the request: only when the content can be sent again.
    if (status == 307 or status == 308) and type(content) == "function" then return response end
    if hop == state.max_redirects then
      response:close()
      error(protocol_error("more than " .. state.max_redirects .. " redirects", "too_many_redirects"), 0)
    end
    local absolute, why = url.resolve(parts, location)
    local nxt = absolute and url.parse(absolute)
    if nxt == nil then
      response:close()
      error(protocol_error("the Location of a redirect is not usable: " .. tostring(why or "invalid URL"), "bad_location"), 0)
    end
    if parts.scheme == "https" and nxt.scheme == "http" and not self._allow_downgrade then
      response:close()
      error(protocol_error("a redirect from https to http is refused", "downgrade"), 0)
    end
    -- A 307 or 308 repeats the request, content included: to another origin only when the caller said so (the content
    -- may be a secret that the first server chose to hand over, not the second).
    if (status == 307 or status == 308) and content ~= nil and nxt.origin ~= parts.origin
      and not (options.cross_origin_redirects or self._cross_origin_redirects) then
      return response
    end
    local new_method = method
    if status == 303 and method ~= "GET" and method ~= "HEAD" then
      new_method = "GET"
    elseif (status == 301 or status == 302) and method == "POST" then
      new_method = "GET" -- RFC 9110 section 15.4.2 and 15.4.3: what user agents do
    end
    if new_method ~= method then
      content = nil
      for _, name in ipairs(ENTITY_FIELDS) do fields:remove(name) end
    end
    if nxt.origin ~= parts.origin then
      for _, name in ipairs(self._strip_on_redirect) do fields:remove(name) end
    end
    local key = new_method .. " " .. nxt.origin .. nxt.target
    if visited[key] then
      response:close()
      error(protocol_error("redirect loop at " .. nxt.origin .. nxt.target, "redirect_loop"), 0)
    end
    visited[parts.origin .. parts.target] = true
    visited[key] = true
    response:close()
    method, parts = new_method, nxt
  end
  error(protocol_error("redirects exhausted", "too_many_redirects"), 0) -- not reached
end

return M
