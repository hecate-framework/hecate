-- The shipped CORS filter (OQ-136): Cross-Origin Resource Sharing of the WHATWG Fetch standard, driven by the `cors.*`
-- configuration keys or by the `cors` option of `Application`. Disabled by default, and no origin is allowed.
global <const> require, type, error, pairs, ipairs, table, math, tostring

local core = require("hecate.core")
local http = require("hecate.http")

---@class hecate.kernel.CorsOptions
---@field enabled? boolean  default false: without it the filter is not installed
---@field allowed_origins? string[]  serialised origins (`https://app.example.com`, no path), or the single entry `"*"`; required, non-empty, when enabled
---@field allowed_methods? string[]  the methods a preflight request may ask for (default `GET`, `HEAD`, `POST`)
---@field allowed_headers? string[]  the header fields a preflight request may ask for (default none), compared without regard to case
---@field exposed_headers? string[]  the response header fields a page may read (default none)
---@field allow_credentials? boolean  default false; refused together with `"*"` (the Fetch standard rejects that pair)
---@field max_age? integer  seconds a browser may cache a preflight answer (default 600)

--- The filter of the CORS policy. A global filter, installed outermost by `Application`: the preflight request is an
--- `OPTIONS` request that matches no route, and only global filters see it.
---@class hecate.kernel.CorsFilter : hecate.kernel.Filter
local CorsFilter = core.class("CorsFilter")

local KEYS = {
  enabled = true, allowed_origins = true, allowed_methods = true, allowed_headers = true,
  exposed_headers = true, allow_credentials = true, max_age = true,
}
local ORIGIN_PATTERN <const> = "^https?://[^/%s?#@]+$"
local TOKEN_PATTERN <const> = "^[%w!#$%%&'*+%-.^_`|~]+$" -- a token of RFC 9110, 5.6.2

---@param key string
---@param message string
local function refuse(key, message)
  error(core.ArgumentError { message = "hecate.kernel.cors: cors." .. key .. ": " .. message, context = { key = "cors." .. key } }, 4)
end

--- A list of strings that are tokens; an absent value gives an empty list.
---@param key string
---@param value any
---@return string[]
local function token_list(key, value)
  if value == nil then return {} end
  if type(value) ~= "table" then refuse(key, "must be a list of strings, got " .. type(value)) end
  local list = {}
  for index, item in ipairs(value) do
    if type(item) ~= "string" or not item:match(TOKEN_PATTERN) then
      refuse(key, ("item %d is not a valid token (letters, digits and !#$%%&'*+-.^_`|~)"):format(index))
    end
    list[index] = item
  end
  return list
end

--- Checks the options and returns them completed with their defaults; nil when the filter is disabled.
---
--- Raises `hecate.core.ArgumentError` with `context.key` naming the offending key.
---@param options table
---@return table? resolved
local function resolve(options)
  if type(options) ~= "table" then error(core.ArgumentError("hecate.kernel.cors: the cors option must be a table, got " .. type(options)), 3) end
  for key in pairs(options) do
    if not KEYS[key] then refuse(tostring(key), "unknown key") end
  end
  if options.enabled ~= nil and type(options.enabled) ~= "boolean" then refuse("enabled", "must be a boolean") end
  if not options.enabled then return nil end
  local origins = options.allowed_origins
  if type(origins) ~= "table" or #origins == 0 then
    refuse("allowed_origins", "an enabled filter needs at least one origin (no origin is allowed by default)")
  end
  local wildcard = false
  for index, origin in ipairs(origins) do
    if origin == "*" then
      wildcard = true
    elseif type(origin) ~= "string" or not origin:match(ORIGIN_PATTERN) then
      refuse("allowed_origins", ("item %d is not an origin: write scheme://host[:port] without a path or a trailing slash, or \"*\""):format(index))
    end
  end
  if wildcard and #origins > 1 then refuse("allowed_origins", '"*" cannot be combined with other origins') end
  local credentials = options.allow_credentials
  if credentials ~= nil and type(credentials) ~= "boolean" then refuse("allow_credentials", "must be a boolean") end
  if credentials and wildcard then
    refuse("allow_credentials", 'cannot be true with allowed_origins "*": browsers reject that pair; list the origins')
  end
  local max_age = options.max_age == nil and 600 or options.max_age
  if math.type(max_age) ~= "integer" or max_age < 0 then refuse("max_age", "must be a non-negative integer of seconds") end
  local methods = options.allowed_methods == nil and { "GET", "HEAD", "POST" } or token_list("allowed_methods", options.allowed_methods)
  local resolved = {
    wildcard = wildcard, credentials = credentials or false, max_age = max_age, methods = methods,
    headers = token_list("allowed_headers", options.allowed_headers),
    exposed = token_list("exposed_headers", options.exposed_headers),
    origins = {}, method_set = {}, header_set = {},
  }
  for _, origin in ipairs(origins) do resolved.origins[origin] = true end
  for _, method in ipairs(resolved.methods) do resolved.method_set[method] = true end
  for _, header in ipairs(resolved.headers) do resolved.header_set[header:lower()] = true end
  return resolved
end

--- Builds the filter, or returns nil when the options disable it.
---
--- Raises `hecate.core.ArgumentError` for an invalid option or a refused combination (`context.key` names the key).
---@param options hecate.kernel.CorsOptions
---@return hecate.kernel.CorsFilter?
function CorsFilter.from_options(options)
  local resolved = resolve(options)
  if resolved == nil then return nil end
  return CorsFilter(resolved)
end

---@param resolved table
function CorsFilter:init(resolved)
  self._policy = resolved
  self._methods = table.concat(resolved.methods, ", ")
  self._headers = table.concat(resolved.headers, ", ")
  self._exposed = table.concat(resolved.exposed, ", ")
end

--- Tells whether every field named by `Access-Control-Request-Headers` is allowed.
---@param policy table
---@param requested string?
---@return boolean
local function headers_allowed(policy, requested)
  if requested == nil then return true end
  for name in requested:gmatch("[^,%s]+") do
    if not policy.header_set[name:lower()] then return false end
  end
  return true
end

--- Adds a field name to `Vary` unless the response already lists it (or `*`).
---@param response hecate.http.Response
---@param name string
local function add_vary(response, name)
  for _, line in ipairs(response.fields:get_all("Vary")) do
    for token in line:gmatch("[^,%s]+") do
      if token == "*" or token:lower() == name:lower() then return end
    end
  end
  response.fields:add("Vary", name)
end

---@param request hecate.kernel.Request
---@param next fun(request: hecate.kernel.Request): hecate.http.Response
---@return hecate.http.Response
function CorsFilter:handle(request, next)
  local policy = self._policy
  local origin = request.fields:get("Origin")
  local allowed = origin ~= nil and (policy.wildcard or policy.origins[origin] == true)
  local response
  local preflight = allowed and request.method == "OPTIONS" and request.fields:get("Access-Control-Request-Method") ~= nil
  if preflight then
    response = http.Response(204)
    local asked = request.fields:get("Access-Control-Request-Method")
    -- A preflight that asks for more than the policy grants gets no permission at all: the browser then blocks the call.
    if policy.method_set[asked]
      and headers_allowed(policy, request.fields:get("Access-Control-Request-Headers")) then
      response.fields:set("Access-Control-Allow-Methods", self._methods)
      if self._headers ~= "" then response.fields:set("Access-Control-Allow-Headers", self._headers) end
      response.fields:set("Access-Control-Max-Age", tostring(policy.max_age))
    else
      allowed = false
    end
  else
    response = next(request)
  end
  if allowed then
    response.fields:set("Access-Control-Allow-Origin", policy.wildcard and "*" or origin)
    if policy.credentials then response.fields:set("Access-Control-Allow-Credentials", "true") end
    if not preflight and self._exposed ~= "" then response.fields:set("Access-Control-Expose-Headers", self._exposed) end
  end
  -- The answer depends on the Origin header unless every origin gets the same one (RFC 9110, 12.5.5).
  -- A preflight answer also depends on what it asks for, so a shared cache must not reuse it for another request.
  if not policy.wildcard then add_vary(response, "Origin") end
  if preflight then
    add_vary(response, "Access-Control-Request-Method")
    add_vary(response, "Access-Control-Request-Headers")
  end
  return response
end

core.finalise(CorsFilter)

return CorsFilter
