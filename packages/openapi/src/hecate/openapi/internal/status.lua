-- Reason phrases of the status codes, for the mandatory `description` of an OpenAPI response (OpenAPI 3.1 section
-- 4.8.17: `description` is required). RFC 9110 section 15 names them. `hecate.http` is not a dependency of this
-- package, so the table is repeated here for the codes a contract commonly declares.
global <const> math, string

local PHRASES <const> = {
  [100] = "Continue", [101] = "Switching Protocols",
  [200] = "OK", [201] = "Created", [202] = "Accepted", [203] = "Non-Authoritative Information", [204] = "No Content",
  [205] = "Reset Content", [206] = "Partial Content",
  [300] = "Multiple Choices", [301] = "Moved Permanently", [302] = "Found", [303] = "See Other", [304] = "Not Modified",
  [307] = "Temporary Redirect", [308] = "Permanent Redirect",
  [400] = "Bad Request", [401] = "Unauthorized", [403] = "Forbidden", [404] = "Not Found", [405] = "Method Not Allowed",
  [406] = "Not Acceptable", [408] = "Request Timeout", [409] = "Conflict", [410] = "Gone", [412] = "Precondition Failed",
  [413] = "Content Too Large", [415] = "Unsupported Media Type", [422] = "Unprocessable Content",
  [429] = "Too Many Requests",
  [500] = "Internal Server Error", [501] = "Not Implemented", [502] = "Bad Gateway", [503] = "Service Unavailable",
  [504] = "Gateway Timeout",
}

--- Status codes and their descriptions.
---@class hecate.openapi.status
local status = {}

--- The description of a response with that status code: its reason phrase (RFC 9110 section 15), or the class of the
--- code (`Success`, `Client Error`, ...) for a code without a phrase here.
---@param code integer
---@return string
function status.description(code)
  local phrase = PHRASES[code]
  if phrase ~= nil then return phrase end
  local classes = { "Informational", "Success", "Redirection", "Client Error", "Server Error" }
  return classes[math.tointeger(code // 100)] or "Response"
end

return status
