-- Mapping of errors to problem details responses (RFC 9457) around the filter chain.
-- Only the class of an error and the structured violations of a validation decide the response: the message, the
-- context and the cause of an error never reach a client (OQ-111, invariant "internal error messages are not exposed
-- by default"). What the client may be told is a fixed text per status.
global <const> require, error, math, ipairs, pairs, pcall, tostring, type, getmetatable

local core = require("hecate.core")
local json = require("hecate.json")
local http = require("hecate.http")
local problem = require("hecate.kernel.problem")

--- Problem details responses and the mapping of errors to them.
---@class hecate.kernel.problems
---@field MAX_ERRORS integer  the most entries of `errors` a 422 response carries
local problems = {}

problems.MAX_ERRORS = 100

local CONTENT_TYPE <const> = "application/problem+json"

local DETAIL <const> = {
  [400] = "The request target is not valid.",
  [404] = "No resource matches the request target.",
  [405] = "The method is not allowed for this resource.",
  [422] = "The request content does not conform to the contract.",
}

--- Builds a problem details response (RFC 9457, section 3) with optional extension members (section 3.2).
---@param status integer
---@param detail string
---@param extension? table<string, any>
---@return hecate.http.Response
local function build(status, detail, extension)
  local body = {
    type = "about:blank", -- RFC 9457, section 4.2.1: the default when no type is defined
    title = http.Status.reason(status) or "Error",
    status = status,
    detail = detail,
  }
  if extension ~= nil then
    for key, value in pairs(extension) do body[key] = value end
  end
  local response = http.Response(status, { content = json.encode(body, { canonical = true }) })
  response.fields:set("Content-Type", CONTENT_TYPE)
  return response
end

--- Builds a problem details response for a status from 400 to 599, with the fixed text of that status
--- (`detail` overrides it: a text chosen by the caller, never an error message).
---
--- Raises `hecate.core.ArgumentError` for a status outside 400..599.
---@param status integer
---@param detail? string
---@return hecate.http.Response
function problems.response(status, detail)
  if math.type(status) ~= "integer" or status < 400 or status > 599 then
    error(core.ArgumentError("problems.response: the status must be an integer from 400 to 599"), 2)
  end
  if detail == nil and DETAIL[status] ~= nil then return build(status, DETAIL[status]) end
  return http.problem.response(status, detail)
end

--- The problem details response for a failed routing decision of `Router:match`: `404`, `405` (with `Allow`,
--- RFC 9110, section 15.5.6) or `400` for an unreadable path (the reason is not forwarded). A match that is not a
--- failure (200, 204) gives nil.
---@param match hecate.router.Match
---@return hecate.http.Response?
function problems.from_match(match)
  local status = match.status
  if status == 404 then return problems.response(404) end
  if status == 400 then return problems.response(400) end
  if status == 405 then
    local response = problems.response(405)
    if match.allow_field ~= nil then response.fields:set("Allow", match.allow_field) end
    return response
  end
  return nil
end

--- The violations of a `ValidationError`, as the entries of the `errors` extension: a JSON Pointer (RFC 6901) and the
--- stable code, in order. The message of a violation is not forwarded (conservative, see OQ-112).
---@param err any
---@param expose boolean  also forward the message of each violation (`errors.expose_details`, OQ-112 (5))
---@return table[]?
local function entries_of(err, expose)
  local violations = type(err.context) == "table" and err.context.violations
  if type(violations) ~= "table" or violations[1] == nil then return nil end
  local entries = {}
  for i, violation in ipairs(violations) do
    if i > problems.MAX_ERRORS then break end
    entries[i] = { pointer = violation.path, code = violation.code }
    if expose then entries[i].message = violation.message end
  end
  return entries
end

--- Options of `from_error` and `guard`.
---@class hecate.kernel.problems.Options
---@field input? boolean  a `ValidationError` is about the request input (422); otherwise it is a defect of the server (500)
---@field expose_details? boolean  default false; the kernel binds it to the configuration key `errors.expose_details`: a 422 entry carries its `message`, a generic 500 carries `debug`
---@field logger? { log: fun(self: any, severity: string, message: string, fields?: table) }  receives the failure (`guard` only)

--- The problem details response of a problem instance (RFC 9457, section 3): `type`, `title`, `status`, the `detail`
--- when the developer gave one, and the extension members (section 3.2); no `instance` member.
---@param instance hecate.kernel.problem.Problem
---@return hecate.http.Response
function problems.from_problem(instance)
  local body = {}
  for key, value in pairs(instance.extensions) do body[key] = value end
  body.type = instance.type
  body.title = instance.title
  body.status = instance.status
  body.detail = instance.detail
  local response = http.Response(instance.status, { content = json.encode(body, { canonical = true }) })
  response.fields:set("Content-Type", CONTENT_TYPE)
  return response
end

--- The `debug` extension member of a generic 500 (only with `expose_details`): the class name, the text of the error
--- and its traceback when it has one.
---@param err any
---@return table
local function debug_of(err)
  local is_error = type(err) == "table" and core.is_instance_of(err, core.Error)
  local debug = { error = is_error and core.name(err) or type(err), message = tostring(err) }
  if is_error and type(err.traceback) == "string" then debug.traceback = err.traceback end
  return debug
end

--- The problem details response for an error raised while serving a request:
---
--- - a problem (`hecate.kernel.problem`): its own status, title, type, detail and extension members;
--- - a `ValidationError` with violations, when `options.input` is true: `422` with one entry per violation;
--- - an error of `hecate.http` that carries a client status (`ParseError`, `ContentError`, `FormError`): that status;
--- - anything else, a `ValidationError` about a response included (OQ-95), a Lua runtime error or a value that is not
---   an error: a generic `500` that names nothing.
---@param err any
---@param options? hecate.kernel.problems.Options
---@return hecate.http.Response
function problems.from_error(err, options)
  local expose = options ~= nil and options.expose_details == true
  if problem.is_problem(err) then return problems.from_problem(err) end
  if options ~= nil and options.input == true and core.is_instance_of(err, core.ValidationError) then
    local entries = entries_of(err, expose)
    if entries ~= nil then return build(422, DETAIL[422], { errors = entries }) end
  end
  if expose then
    local status, detail = http.problem.of_error(err)
    if status == 500 then return build(500, detail, { debug = debug_of(err) }) end
  end
  return http.problem.from_error(err)
end

--- Wraps an action (or a composed chain) so that no error escapes as a response of the wrong shape: an error becomes
--- a problem details response, and the function returns the response and the caught failure (for the caller to log).
--- With `options.logger` the failure is logged at `error` severity with its text (free text, by design of OQ-111).
--- Cancellation and deadline errors are never caught: they belong to the scope that raised them (ADR 0003).
---@param action fun(request: hecate.http.Request): hecate.http.Response
---@param options? hecate.kernel.problems.Options
---@return fun(request: hecate.http.Request): hecate.http.Response, any?
function problems.guard(action, options)
  local logger = options ~= nil and options.logger or nil
  return function(request)
    local ok, result = pcall(action, request)
    if ok then return result end
    if core.is_instance_of(result, core.CancellationError) or core.is_instance_of(result, core.DeadlineExceededError) then
      error(result, 0)
    end
    if logger ~= nil and not (problem.is_problem(result) and result.status < 500) then logger:log("error", "unhandled error while serving a request", { error = tostring(result) }) end
    return problems.from_error(result, options), result
  end
end

return problems
