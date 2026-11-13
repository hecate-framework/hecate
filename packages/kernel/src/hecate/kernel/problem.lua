-- Problem classes (RFC 9457): the problems an application raises or returns, as classes of the object model.
-- A problem is a subclass of `hecate.core.Error`, so `error(NotFound { ... })` works from any layer and the guard of
-- `problems` maps it. The developer chooses `detail` and the extension members; an error message is never one of them
-- (OQ-111, OQ-112 (6)).
global <const> require, type, pairs, ipairs, math, error, tostring, getmetatable, pcall, string

local core = require("hecate.core")
local http = require("hecate.http")

--- The problem classes: `NotFound`, `Conflict`, ... for the common statuses, and `define` for an application's own.
---@class hecate.kernel.problem
---@field Problem hecate.kernel.problem.ProblemDetails  base class of every problem
---@field BadRequest hecate.kernel.problem.ProblemDetails  400
---@field Unauthorized hecate.kernel.problem.ProblemDetails  401
---@field Forbidden hecate.kernel.problem.ProblemDetails  403
---@field NotFound hecate.kernel.problem.ProblemDetails  404
---@field MethodNotAllowed hecate.kernel.problem.ProblemDetails  405
---@field NotAcceptable hecate.kernel.problem.ProblemDetails  406
---@field RequestTimeout hecate.kernel.problem.ProblemDetails  408
---@field Conflict hecate.kernel.problem.ProblemDetails  409
---@field Gone hecate.kernel.problem.ProblemDetails  410
---@field PreconditionFailed hecate.kernel.problem.ProblemDetails  412
---@field ContentTooLarge hecate.kernel.problem.ProblemDetails  413
---@field UnsupportedMediaType hecate.kernel.problem.ProblemDetails  415
---@field UnprocessableContent hecate.kernel.problem.ProblemDetails  422
---@field TooManyRequests hecate.kernel.problem.ProblemDetails  429
---@field InternalServerError hecate.kernel.problem.ProblemDetails  500
---@field BadGateway hecate.kernel.problem.ProblemDetails  502
---@field ServiceUnavailable hecate.kernel.problem.ProblemDetails  503
---@field GatewayTimeout hecate.kernel.problem.ProblemDetails  504
local problem = {}

--- The fields a problem is built from.
---@class hecate.kernel.problem.Fields
---@field detail? string  explanation specific to this occurrence, chosen by the developer (RFC 9457, section 3.1.4)
---@field extensions? table<string, any>  extension members (section 3.2)
---@field fields? table<string, string|string[]>  header fields of the response, a name to a value or a list of values (one field line each): `WWW-Authenticate` for a 401 (RFC 9110, sections 11.6.1 and 15.5.2), `Allow` for a 405 (section 15.5.6), `Retry-After` for a 429 or a 503 (section 10.2.3). Names and values follow `hecate.http.Fields`; `Content-Type`, `Content-Length`, `Transfer-Encoding` and `Connection` belong to the kernel and are refused. Never part of the JSON content nor of the contract of a route (OQ-126)

--- A problem details occurrence. The class carries `status`, `title` and `type`; the instance copies them.
---@class hecate.kernel.problem.ProblemDetails : hecate.core.Error
---@field status integer
---@field title string
---@field code string  the stable error code, `<namespace>.problem.<Class>`: `hecate.problem.NotFound` for a built-in class, `app.problem.<Name>` by default for a class of `problem.define`
---@field type string  a URI reference, `about:blank` by default (RFC 9457, section 4.2.1)
---@field detail? string
---@field extensions table<string, any>
---@field fields? hecate.http.Fields  the header fields given at construction (a copy), added to the response; nil when none were given
---@overload fun(fields?: hecate.kernel.problem.Fields): hecate.kernel.problem.ProblemDetails
local Problem = core.class("Problem", core.Error)
Problem.code = "hecate.problem.Problem"
Problem.type = "about:blank"

-- RFC 9457, section 3.1: the members the specification defines; an extension member may not reuse their names.
local RESERVED <const> = { type = true, title = true, status = true, detail = true, instance = true }

--- The header fields the kernel sets itself on a problem details response (lowercase): a problem may not carry them.
--- `Content-Type` is `application/problem+json` (RFC 9457, section 3); the framing fields belong to the server
--- (RFC 9112, sections 6 and 9.6).
local OWNED <const> = { ["content-type"] = true, ["content-length"] = true, ["transfer-encoding"] = true, connection = true }

--- Tells whether a header field belongs to the kernel on a problem details response (`Content-Type`,
--- `Content-Length`, `Transfer-Encoding`, `Connection`, in any case): a problem may not carry it.
---@param name string
---@return boolean
function problem.is_owned_field(name)
  return type(name) == "string" and OWNED[string.lower(name)] == true
end

--- Checks the `fields` of a problem and copies them into `hecate.http.Fields`.
---@param given any
---@return hecate.http.Fields
local function fields_of(given)
  if type(given) ~= "table" then
    error(core.ArgumentError("hecate.kernel.problem.init: fields must be a table of header field names to values, got " .. type(given)), 4)
  end
  for name, value in pairs(given) do
    if type(name) ~= "string" then
      error(core.ArgumentError("hecate.kernel.problem.init: header field names must be strings, got " .. type(name)), 4)
    end
    if problem.is_owned_field(name) then
      error(core.ArgumentError(("hecate.kernel.problem.init: header field %q is owned by the kernel (Content-Type, Content-Length, Transfer-Encoding and Connection are refused)"):format(name)), 4)
    end
    local values = type(value) == "table" and value or { value }
    for _, item in ipairs(values) do
      if type(item) ~= "string" then
        error(core.ArgumentError(("hecate.kernel.problem.init: the value of header field %q must be a string or a list of strings, got a %s"):format(name, type(item))), 4)
      end
    end
  end
  local built, copy = pcall(function() return http.Fields(given) end)
  if not built then
    -- The text of `http.Fields` names the rule broken, never the value (which could be anything the caller passed).
    local reason = core.is_instance_of(copy, core.Error) and (copy --[[@as hecate.core.Error]]).message or tostring(copy)
    error(core.ArgumentError("hecate.kernel.problem.init: invalid header fields: " .. reason), 4)
  end
  return copy
end

--- Builds a problem from `fields`.
---
--- Raises `hecate.core.ArgumentError` for an unknown field, a `detail` that is not a string, `extensions` that
--- is not a table with string keys outside the reserved names (`type`, `title`, `status`, `detail`, `instance`), or
--- that holds, at its first level, a function, a thread, a userdata or a number that is not finite (NaN, infinity),
--- or `fields` that is not a table of header field names to strings or lists of strings, that holds a name or a value
--- `hecate.http.Fields` refuses (not a token; a control character other than HTAB), or a field the kernel owns
--- (`problem.is_owned_field`).
---@param fields? hecate.kernel.problem.Fields
function Problem:init(fields)
  if fields == nil then fields = {} end
  if type(fields) ~= "table" then
    error(core.ArgumentError("hecate.kernel.problem.init: a problem is built from a table of fields, got " .. type(fields)), 3)
  end
  for key in pairs(fields) do
    if key ~= "detail" and key ~= "extensions" and key ~= "fields" then
      error(core.ArgumentError("hecate.kernel.problem.init: unknown field '" .. tostring(key) .. "' (valid: detail, extensions, fields)"), 3)
    end
  end
  if fields.detail ~= nil and type(fields.detail) ~= "string" then
    error(core.ArgumentError("hecate.kernel.problem.init: detail must be a string, got " .. type(fields.detail)), 3)
  end
  local extensions = fields.extensions
  if extensions ~= nil then
    if type(extensions) ~= "table" then error(core.ArgumentError("hecate.kernel.problem.init: extensions must be a table, got " .. type(extensions)), 3) end
    for key, value in pairs(extensions) do
      -- Cheap checks of what JSON cannot carry (the encoder would refuse it at the first answer): the nested values are
      -- left to `problems.from_problem`, which never lets an encoding failure escape.
      local kind = type(value)
      if kind == "function" or kind == "thread" or kind == "userdata" then
        error(core.ArgumentError(("hecate.kernel.problem.init: extension %q is a %s, which has no JSON representation"):format(tostring(key), kind)), 3)
      end
      if kind == "number" and (value ~= value or value == math.huge or value == -math.huge) then
        error(core.ArgumentError(("hecate.kernel.problem.init: extension %q is not a finite number"):format(tostring(key))), 3)
      end
      if type(key) ~= "string" then
        error(core.ArgumentError("hecate.kernel.problem.init: extension names must be strings, got " .. type(key)), 3)
      end
      if RESERVED[key] then
        error(core.ArgumentError("hecate.kernel.problem.init: extension name '" .. key .. "' is reserved (RFC 9457, section 3.1)"), 3)
      end
    end
  end
  local header_fields = fields.fields ~= nil and fields_of(fields.fields) or nil
  local class = getmetatable(self)
  core.Error.init(self, { message = fields.detail or class.title or "Problem" })
  self.status = class.status
  self.title = class.title
  self.type = class.type
  self.detail = fields.detail
  self.extensions = extensions or {}
  self.fields = header_fields
end

problem.Problem = core.finalise(Problem)

--- Declares a problem class for a status and a title.
---@param name string
---@param code string
---@param status integer
---@param title string
---@param uri string
---@return hecate.kernel.problem.ProblemDetails
local function declare(name, code, status, title, uri)
  local class = core.class(name, Problem)
  class.code = code
  class.status = status
  class.title = title
  class.type = uri
  return core.finalise(class)
end

local COMMON <const> = {
  { "BadRequest", 400 }, { "Unauthorized", 401 }, { "Forbidden", 403 }, { "NotFound", 404 },
  { "MethodNotAllowed", 405 }, { "NotAcceptable", 406 }, { "RequestTimeout", 408 }, { "Conflict", 409 },
  { "Gone", 410 }, { "PreconditionFailed", 412 }, { "ContentTooLarge", 413 }, { "UnsupportedMediaType", 415 },
  { "UnprocessableContent", 422 }, { "TooManyRequests", 429 }, { "InternalServerError", 500 },
  { "BadGateway", 502 }, { "ServiceUnavailable", 503 }, { "GatewayTimeout", 504 },
}

for _, entry in ipairs(COMMON) do
  local name, status = entry[1], entry[2]
  problem[name] = declare(name, "hecate.problem." .. name, status, http.Status.reason(status) or "Error", "about:blank")
end

--- Declares an application's own problem class. Its `code` has the shape of the built-in ones, `<namespace>.problem.<Name>`
--- (`hecate.problem.NotFound`), in the namespace of the application: `app.problem.<Name>` unless `spec.code` gives
--- another. The `hecate.` namespace belongs to the framework and is refused.
---
--- Raises `hecate.core.ArgumentError` when `name` is not a non-empty string, `status` is not an integer from 400 to
--- 599, `title` is not a non-empty string, `type` is given and is not a string, or `code` is given and is not a
--- non-empty string outside the `hecate.` namespace.
---@param name string
---@param spec { status: integer, title: string, type?: string, code?: string }
---@return hecate.kernel.problem.ProblemDetails
function problem.define(name, spec)
  local where = "hecate.kernel.problem.define: "
  if type(name) ~= "string" or name == "" then
    error(core.ArgumentError(where .. "the name must be a non-empty string, got " .. type(name)), 2)
  end
  if type(spec) ~= "table" then error(core.ArgumentError(where .. "the declaration must be a table, got " .. type(spec)), 2) end
  if math.type(spec.status) ~= "integer" or spec.status < 400 or spec.status > 599 then
    error(core.ArgumentError(where .. "the status must be an integer from 400 to 599, got " .. tostring(spec.status)), 2)
  end
  if type(spec.title) ~= "string" or spec.title == "" then
    error(core.ArgumentError(where .. "the title must be a non-empty string, got " .. type(spec.title)), 2)
  end
  if spec.type ~= nil and type(spec.type) ~= "string" then
    error(core.ArgumentError(where .. "the type must be a string (a URI reference), got " .. type(spec.type)), 2)
  end
  local code = spec.code
  if code == nil then
    code = "app.problem." .. name
  elseif type(code) ~= "string" or code == "" then
    error(core.ArgumentError(where .. "the code must be a non-empty string, got " .. type(code)), 2)
  elseif code == "hecate" or code:sub(1, 7) == "hecate." then
    error(core.ArgumentError(where .. "the code must not be in the 'hecate.' namespace, which belongs to the framework, got '"
      .. code .. "'"), 2)
  end
  return declare(name, code, spec.status, spec.title, spec.type or "about:blank")
end

--- Tells whether a value is an instance of a problem class.
---@param value any
---@return boolean
function problem.is_problem(value)
  return type(value) == "table" and core.is_instance_of(value, Problem)
end

--- Tells whether a value is a problem class (`Problem` or a subclass), as referenced by `responses = { [404] = NotFound }`.
---@param value any
---@return boolean
function problem.is_class(value)
  if not core.is_class(value) then return false end
  local current = value
  while current ~= nil do
    if current == Problem then return true end
    current = core.superclass(current)
  end
  return false
end

return problem
