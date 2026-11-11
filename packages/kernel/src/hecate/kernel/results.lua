-- Serialisation of the result of an action into a `hecate.http.Response`: a pure function, no socket, no Application.
-- `http` is bytes only (OQ-76 a): the kernel represents the value with the schema declared for the status
-- (`schema:represent`, OQ-95), encodes it with the serialiser chosen by content negotiation (RFC 9110, section 12),
-- and only then builds the Response. Nothing of a value or of an error message goes into a response (OQ-111).
global <const> require, type, error, getmetatable, rawequal, math, string, table, ipairs, pairs, tonumber, tostring

local core = require("hecate.core")
local json = require("hecate.json")
local http = require("hecate.http")
local problem = require("hecate.kernel.problem")
local problems = require("hecate.kernel.problems")

--- Result of an action and its serialisation.
---@class hecate.kernel.results
---@field serialisers table<string, fun(plain: any): string>  media type -> serialiser, extensible: add an entry to plug a representation in
local results = {}

--- Private tag of a result built by `respond`.
local RESULT <const> = {}

local JSON <const> = "application/json"

--- The built-in serialisers. JSON is the only built-in representation until the `template` package exists.
--- A serialiser receives the plain value (already represented) and returns a string; it must raise on failure.
results.serialisers = {
  [JSON] = function(plain) return json.encode(plain) end,
}

---@class hecate.kernel.results.Result  an answer with a status, built by `respond`
---@field status integer
---@field value any
---@field schema? table

--- Builds a result that makes the serialiser answer with `status` and a representation of `value`, with the schema
--- declared for that status by the route, or with `schema` when given. Not a Response.
---
--- Raises `hecate.core.ArgumentError` for a status outside 100..599.
---@param status integer
---@param value? any
---@param schema? table
---@return hecate.kernel.results.Result
function results.respond(status, value, schema)
  if math.type(status) ~= "integer" or status < 100 or status > 599 then
    error(core.ArgumentError("hecate.kernel.results.respond: the status must be an integer from 100 to 599, got " .. tostring(status)), 2)
  end
  return { [RESULT] = true, status = status, value = value, schema = schema }
end

--- Tells whether a value was built by `respond`.
---@param value any
---@return boolean
function results.is_result(value)
  return type(value) == "table" and value[RESULT] == true
end

--- Parses `Accept` (RFC 9110, section 12.5.1) into the media types it ranges over, best first. Minimal: parameters
--- other than `q` are ignored, and the specificity of a range does not break ties between equal weights.
---@param header string
---@return string[] ranges  lower-case ranges with a weight above zero, by decreasing weight
local function ranges_of(header)
  local entries = {}
  for part in string.gmatch(header, "[^,]+") do
    local range, params = string.match(part, "^%s*([^;%s]+)%s*(.*)$")
    if range ~= nil then
      local weight = tonumber(string.match(params, ";%s*[qQ]%s*=%s*([%d.]+)")) or 1
      if weight > 0 then entries[#entries + 1] = { string.lower(range), weight, #entries } end
    end
  end
  table.sort(entries, function(a, b)
    if a[2] ~= b[2] then return a[2] > b[2] end
    return a[3] < b[3]
  end)
  local ranges = {}
  for i, entry in ipairs(entries) do ranges[i] = entry[1] end
  return ranges
end

--- Picks the media type of the representation: the first range of `Accept` (best weight first) that a serialiser
--- satisfies; with no `Accept`, `application/json` when there is a serialiser for it, else the first by name.
---@param request hecate.http.Request
---@param serialisers table<string, function>
---@return string? media_type  nil when nothing is acceptable
local function negotiate(request, serialisers)
  local header = request.fields:combined("Accept")
  if header == nil then
    if serialisers[JSON] ~= nil then return JSON end
    local names = {}
    for name in pairs(serialisers) do names[#names + 1] = name end
    table.sort(names)
    return names[1]
  end
  for _, range in ipairs(ranges_of(header)) do
    if range == "*/*" then
      if serialisers[JSON] ~= nil then return JSON end
      local names = {}
      for name in pairs(serialisers) do names[#names + 1] = name end
      table.sort(names)
      if names[1] ~= nil then return names[1] end
    elseif string.sub(range, -2) == "/*" then
      local prefix = string.sub(range, 1, -2)
      if serialisers[JSON] ~= nil and string.sub(JSON, 1, #prefix) == prefix then return JSON end
      local names = {}
      for name in pairs(serialisers) do
        if string.sub(name, 1, #prefix) == prefix then names[#names + 1] = name end
      end
      table.sort(names)
      if names[1] ~= nil then return names[1] end
    elseif serialisers[range] ~= nil then
      return range
    end
  end
  return nil
end

--- Refuses an instance of a class used without a schema: its attributes are not representable by default.
---@param value any
local function refuse_unrepresentable(value)
  if type(value) == "table" then
    local meta = getmetatable(value)
    if meta ~= nil and not json.is_array(value) and not json.is_object(value) and type(meta.__pairs) ~= "function" then
      error(core.ArgumentError("hecate.kernel.results.serialise: a value of a class has no schema declared for this status; declare one with schema.of(Class)"), 3)
    end
  end
end

--- Whether the status is the one a plain value answers with (see `serialise`).
---@param request hecate.http.Request
---@param route_responses table
---@param options? table
---@return integer
local function default_status(request, route_responses, options)
  if options ~= nil and options.created == true then return 201 end
  if request.method == "POST" and route_responses[201] ~= nil and route_responses[200] == nil then return 201 end
  return 200
end

--- Builds a Response from a status and a value.
---@param status integer
---@param value any
---@param schema any
---@param request hecate.http.Request
---@param serialisers table<string, function>
---@param validate boolean  check the representation against `schema` (development and test)
---@return hecate.http.Response
local function build(status, value, schema, request, serialisers, validate)
  if value == nil or http.Status.forbids_content(status) then
    return http.Response(status)
  end
  local media_type = negotiate(request, serialisers)
  if media_type == nil then
    -- RFC 9110, section 15.5.7: no representation is acceptable. The value is neither described nor logged (OQ-111).
    return http.problem.response(406, "No representation acceptable to the client is available.")
  end
  local plain
  if type(schema) == "table" and type(schema.represent) == "function" then
    plain = schema:represent(value) -- ValidationError for a wrong shape (OQ-95): propagates, the caller makes a 500
    if validate and type(schema.validate) == "function" then
      local ok, violations = schema:validate(plain)
      if not ok then
        -- A defect of the server, not of the request: the caller makes a 500. The message names the status (which
        -- identifies the declared schema) and the code of the first violation, never a value (OQ-111) and never the
        -- pointer into the data either: a key of a map can carry data of a user. `violation.path` stays in
        -- `context.violations` for a caller that wants it; `hecate.schema` has no schema path to log (reported).
        local first = violations[1]
        error(core.ValidationError(
          ("results.serialise: the response for status %d does not conform to the schema declared for that status: %d violation(s), first violation code '%s'")
            :format(status, #violations, first.code),
          { context = { status = status, violations = violations } }), 3)
      end
    end
  else
    refuse_unrepresentable(value)
    plain = value
  end
  local response = http.Response(status, { content = serialisers[media_type](plain) })
  response.fields:set("Content-Type", media_type)
  return response
end

--- Serialises the result of an action into a Response.
---
--- - a `hecate.http.Response` (a problem of `http.problem.response` included, RFC 9457) is returned as is;
--- - a problem (`hecate.kernel.problem`) is answered as `problems.from_problem` does;
--- - a result of `respond` answers with its status, represented with its own schema or the one declared for it;
--- - nil answers `204` without content when the route declares a `204`, else `200` without content;
--- - any other value answers `200`, or `201` when `options.created` is true or when the request is a `POST` and the
---   route declares a `201` but no `200`; it is represented with the schema declared for that status
---   (`route_responses[status]`, for example `schema.of(User)`), or encoded as is when none is declared (plain
---   tables and strings only: an instance of a class without schema raises `hecate.core.ArgumentError`).
---
--- The representation is chosen by `Accept` among `options.serialisers` (default `results.serialisers`): absent,
--- `*/*` or a matching range select it, a request nothing satisfies gets a 406 problem details Response.
--- A failure of `represent` (a `hecate.core.ValidationError`) or of a serialiser propagates as an error: the caller
--- maps it to a 500 without internal details.
---
--- With `options.validate_responses` (development and test, http-and-routing.md "Results and serialisation"), the
--- representation of a value that has a schema declared for its status (or given to `respond`) is validated against
--- it; a mismatch raises `hecate.core.ValidationError` with `context.status` and `context.violations` (a defect of the
--- server: the caller maps it to a 500). A Response, a problem and a value without schema are not checked.
---@param result any
---@param request hecate.http.Request
---@param route_responses table<integer, any>  status -> schema (or `true` for a declared status without content)
---@param options? { created?: boolean, serialisers?: table<string, fun(plain: any): string>, validate_responses?: boolean, logger?: { log: fun(self: any, severity: string, message: string, fields?: table) } }  `logger` receives a problem whose extension members cannot be encoded (default `log.default()`)
---@return hecate.http.Response
function results.serialise(result, request, route_responses, options)
  if type(result) == "table" and rawequal(getmetatable(result), nil) == false and core.is_instance_of(result, http.Response) then
    return result
  end
  -- A returned problem is a result like a Response: always `application/problem+json` (RFC 9457, section 3).
  if problem.is_problem(result) then return problems.from_problem(result, options ~= nil and options.logger or nil) end
  local serialisers = options ~= nil and options.serialisers or results.serialisers
  local validate = options ~= nil and options.validate_responses == true
  if results.is_result(result) then
    local status = result.status
    return build(status, result.value, result.schema or route_responses[status], request, serialisers, validate)
  end
  if result == nil then
    if route_responses[204] ~= nil then return http.Response(204) end
    return http.Response(200)
  end
  local status = default_status(request, route_responses, options)
  return build(status, result, route_responses[status], request, serialisers, validate)
end

return results
