-- Two filters written with the kernel of today: authentication, which
-- refuses a request before the action runs, and CORS, which answers the
-- preflight request and marks every response of an allowed origin.
local http = require("hecate.http")
local hecate = require("hecate")

-- Authentication: a filter of the routes that need it. It short-circuits
-- with a 401 (RFC 9110 asks for WWW-Authenticate) or passes the principal.
---@class app.Request : hecate.kernel.Request
---@field principal string?  set by the authentication filter

local TOKENS = { ["s3cret"] = "ada" }
local authenticate = {
  handle = function(_, request, next)
    local token = (request.fields:get("Authorization") or "")
      :match("^Bearer (%S+)$")
    local user = token and TOKENS[token]
    if user == nil then
      local refused = http.problem.response(401, "A bearer token is needed.")
      refused.fields:set("WWW-Authenticate", 'Bearer realm="accounts"')
      return refused
    end
    request.principal = user
    return next(request)
  end,
}

-- CORS: a global filter, because the preflight OPTIONS request matches no
-- declared route and only the global filters see it.
local ALLOWED = "https://app.example.com"
local cors = {
  handle = function(_, request, next)
    local origin = request.fields:get("Origin")
    if origin ~= ALLOWED then return next(request) end
    local response
    if request.method == "OPTIONS"
      and request.fields:get("Access-Control-Request-Method") then
      response = http.Response(204)
      response.fields:set("Access-Control-Allow-Methods", "GET, POST")
      response.fields:set("Access-Control-Allow-Headers", "Authorization")
      response.fields:set("Access-Control-Max-Age", "600")
    else
      -- Global filters receive a Response: the result is serialised.
      response = next(request)
    end
    response.fields:set("Access-Control-Allow-Origin", origin)
    response.fields:add("Vary", "Origin")
    return response
  end,
}

-- The filters of a route module are the default filters of its routes.
local accounts = hecate.routes("accounts", { filters = { authenticate } })
accounts:get("/me", {
  ---@param request app.Request
  action = function(request) return { user = request.principal } end,
})

local serve = hecate.Application({ routes = { accounts }, filters = { cors } })
  :boot()
local function ask(method, fields)
  return serve(http.Request({
    method = method, target = "/me", fields = http.Fields(fields),
  }))
end

local response = ask("GET", { Authorization = "Bearer s3cret" })
print(response.status, response.content)
-- Prints: 200	{"user":"ada"}
response = ask("GET", {})
print(response.status, response.fields:get("WWW-Authenticate"))
-- Prints: 401	Bearer realm="accounts"
response = ask("OPTIONS", {
  Origin = ALLOWED, ["Access-Control-Request-Method"] = "GET",
})
print(response.status, response.fields:get("Access-Control-Allow-Methods"))
-- Prints: 204	GET, POST
response = ask("GET", { Origin = ALLOWED })
print(response.status, response.fields:get("Access-Control-Allow-Origin"))
-- Prints: 401	https://app.example.com
