-- Status codes and reason phrases (RFC 9110, section 15).
global <const> type, math

--- Registered status codes (RFC 9110, section 15; IANA registry) with their reason phrases.
---@class hecate.http.Status
local Status = {}

local REASONS <const> = {
  [100] = "Continue", [101] = "Switching Protocols", [102] = "Processing", [103] = "Early Hints",
  [200] = "OK", [201] = "Created", [202] = "Accepted", [203] = "Non-Authoritative Information",
  [204] = "No Content", [205] = "Reset Content", [206] = "Partial Content", [207] = "Multi-Status",
  [208] = "Already Reported", [226] = "IM Used",
  [300] = "Multiple Choices", [301] = "Moved Permanently", [302] = "Found", [303] = "See Other",
  [304] = "Not Modified", [305] = "Use Proxy", [307] = "Temporary Redirect", [308] = "Permanent Redirect",
  [400] = "Bad Request", [401] = "Unauthorized", [402] = "Payment Required", [403] = "Forbidden",
  [404] = "Not Found", [405] = "Method Not Allowed", [406] = "Not Acceptable",
  [407] = "Proxy Authentication Required", [408] = "Request Timeout", [409] = "Conflict",
  [410] = "Gone", [411] = "Length Required", [412] = "Precondition Failed", [413] = "Content Too Large",
  [414] = "URI Too Long", [415] = "Unsupported Media Type", [416] = "Range Not Satisfiable",
  [417] = "Expectation Failed", [418] = "I'm a teapot", [421] = "Misdirected Request",
  [422] = "Unprocessable Content", [423] = "Locked", [424] = "Failed Dependency", [425] = "Too Early",
  [426] = "Upgrade Required", [428] = "Precondition Required", [429] = "Too Many Requests",
  [431] = "Request Header Fields Too Large", [451] = "Unavailable For Legal Reasons",
  [500] = "Internal Server Error", [501] = "Not Implemented", [502] = "Bad Gateway",
  [503] = "Service Unavailable", [504] = "Gateway Timeout", [505] = "HTTP Version Not Supported",
  [506] = "Variant Also Negotiates", [507] = "Insufficient Storage", [508] = "Loop Detected",
  [510] = "Not Extended", [511] = "Network Authentication Required",
}

--- Reports whether `code` is an integer in 100..599 (RFC 9110, section 15: three digits, first 1 to 5).
---@param code any
---@return boolean
function Status.is_valid(code)
  return type(code) == "number" and math.type(code) == "integer" and code >= 100 and code <= 599
end

--- Returns the reason phrase of a registered code, or nil.
---@param code integer
---@return string?
function Status.reason(code)
  return REASONS[code]
end

--- Returns the class of a valid code: "informational", "successful", "redirection",
--- "client_error" or "server_error" (RFC 9110, section 15); nil for an invalid code.
---@param code integer
---@return string?
function Status.class(code)
  if not Status.is_valid(code) then return nil end
  return ({ "informational", "successful", "redirection", "client_error", "server_error" })[code // 100]
end

--- Reports whether a response with this status never has content: 1xx, 204, 205 and 304
--- (RFC 9110, sections 15.2, 15.3.5, 15.3.6, 15.4.5).
---@param code integer
---@return boolean
function Status.forbids_content(code)
  return code < 200 or code == 204 or code == 205 or code == 304
end

return Status
