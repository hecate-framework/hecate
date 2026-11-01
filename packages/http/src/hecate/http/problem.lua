-- Problem details responses (RFC 9457) and the mapping from errors to what a client may be told.
-- Nothing of an error's message or context is ever forwarded: the text names addresses, errno values, paths and
-- parameters that belong to the server (security review of Phase 1, finding 1).
global <const> require, error, math

local core = require("hecate.core")
local json = require("hecate.json")
local reactor = require("hecate.reactor")
local Response = require("hecate.http.response")
local Status = require("hecate.http.status")
local ContentError = require("hecate.http.content").ContentError
local FormError = require("hecate.http.form").FormError
local ParseError = require("hecate.http.errors").ParseError

--- Builds problem details responses and maps errors to them.
---@class hecate.http.problem
local problem = {}

--- Fixed texts: the `detail` of a response is one of these, chosen by status or by the class of the failure.
local DETAIL_BY_STATUS <const> = {
  [400] = "The request is malformed.",
  [408] = "The request was not received in time.",
  [413] = "The request content exceeds the limit of the server.",
  [414] = "The request target is too long.",
  [415] = "The media type of the request content is not supported.",
  [417] = "The expectation of the request cannot be met.",
  [431] = "The request fields are too large.",
  [500] = "The server could not process the request.",
  [501] = "The server does not support this feature of the request.",
  [503] = "The server is not able to handle the request now.",
}

local NETWORK_DETAIL <const> = "A network operation of the server failed."

--- Builds a problem details response (RFC 9457, section 3): `application/problem+json` with `type` `about:blank`,
--- `title` the reason phrase, `status` and `detail`.
---
--- Raises `hecate.core.ArgumentError` for a status outside 400..599.
---@param status integer
---@param detail? string  a fixed text; defaults to the generic text of the status
---@return hecate.http.Response
function problem.response(status, detail)
  if math.type(status) ~= "integer" or status < 400 or status > 599 then
    error(core.ArgumentError("http.problem.response: the status must be an integer from 400 to 599"), 2)
  end
  local content = json.encode({
    type = "about:blank",
    title = Status.reason(status) or "Error",
    status = status,
    detail = detail or DETAIL_BY_STATUS[status] or DETAIL_BY_STATUS[500],
  }, { canonical = true })
  local response = Response(status, { content = content })
  response.fields:set("Content-Type", "application/problem+json")
  return response
end

--- Maps an error raised while serving a request to a status and a generic detail. Only the class decides:
--- the message and the context of the error never reach the result. A `ParseError` or a `ContentError` carries its
--- own status; a transport or network failure is a 500 with a text of its own; anything else is a 500.
---@param err any
---@return integer status
---@return string detail
function problem.of_error(err)
  if core.is_instance_of(err, ParseError) or core.is_instance_of(err, ContentError) or core.is_instance_of(err, FormError) then
    local status = err.context and err.context.status
    if DETAIL_BY_STATUS[status] ~= nil and status ~= 500 then return status, DETAIL_BY_STATUS[status] end
    return 400, DETAIL_BY_STATUS[400]
  end
  if core.is_instance_of(err, reactor.TransportError) or core.is_instance_of(err, core.NetworkError) then
    return 500, NETWORK_DETAIL
  end
  return 500, DETAIL_BY_STATUS[500]
end

--- The problem details response for an error: `problem.response(problem.of_error(err))`.
---@param err any
---@return hecate.http.Response
function problem.from_error(err)
  return problem.response(problem.of_error(err))
end

return problem
