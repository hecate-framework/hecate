-- Problem classes (RFC 9457): the problems an application raises or returns, as classes of the object model.
-- A problem is a subclass of `hecate.core.Error`, so `error(NotFound { ... })` works from any layer and the guard of
-- `problems` maps it. The developer chooses `detail` and the extension members; an error message is never one of them
-- (OQ-111, OQ-112 (6)).
global <const> require, type, pairs, ipairs, math, error, tostring, getmetatable

local core = require("hecate.core")
local http = require("hecate.http")

--- The problem classes: `NotFound`, `Conflict`, ... for the common statuses, and `define` for an application's own.
---@class hecate.kernel.problem
---@field Problem hecate.kernel.problem.Problem  base class of every problem
---@field BadRequest hecate.kernel.problem.Problem  400
---@field Unauthorized hecate.kernel.problem.Problem  401
---@field Forbidden hecate.kernel.problem.Problem  403
---@field NotFound hecate.kernel.problem.Problem  404
---@field MethodNotAllowed hecate.kernel.problem.Problem  405
---@field Conflict hecate.kernel.problem.Problem  409
---@field Gone hecate.kernel.problem.Problem  410
---@field UnprocessableContent hecate.kernel.problem.Problem  422
---@field TooManyRequests hecate.kernel.problem.Problem  429
---@field InternalServerError hecate.kernel.problem.Problem  500
---@field ServiceUnavailable hecate.kernel.problem.Problem  503
local problem = {}

--- The fields a problem is built from.
---@class hecate.kernel.problem.Fields
---@field detail? string  explanation specific to this occurrence, chosen by the developer (RFC 9457, section 3.1.4)
---@field extensions? table<string, any>  extension members (section 3.2)

--- A problem details occurrence. The class carries `status`, `title` and `type`; the instance copies them.
---@class hecate.kernel.problem.Problem : hecate.core.Error
---@field status integer
---@field title string
---@field code string  the stable error code, `hecate.problem.<Class>`
---@field type string  a URI reference, `about:blank` by default (RFC 9457, section 4.2.1)
---@field detail? string
---@field extensions table<string, any>
---@overload fun(fields?: hecate.kernel.problem.Fields): hecate.kernel.problem.Problem
local Problem = core.class("Problem", core.Error)
Problem.code = "hecate.problem.Problem"
Problem.type = "about:blank"

-- RFC 9457, section 3.1: the members the specification defines; an extension member may not reuse their names.
local RESERVED <const> = { type = true, title = true, status = true, detail = true, instance = true }

--- Builds a problem from `fields`.
---
--- Raises `hecate.core.ArgumentError` for an unknown field, a `detail` that is not a string, or `extensions` that
--- is not a table with string keys outside the reserved names (`type`, `title`, `status`, `detail`, `instance`), or
--- that holds, at its first level, a function, a thread, a userdata or a number that is not finite (NaN, infinity).
---@param fields? hecate.kernel.problem.Fields
function Problem:init(fields)
  if fields == nil then fields = {} end
  if type(fields) ~= "table" then
    error(core.ArgumentError("a problem is built from a table of fields"), 3)
  end
  for key in pairs(fields) do
    if key ~= "detail" and key ~= "extensions" then
      error(core.ArgumentError("a problem has no field " .. tostring(key) .. "; fields are detail and extensions"), 3)
    end
  end
  if fields.detail ~= nil and type(fields.detail) ~= "string" then
    error(core.ArgumentError("problem detail must be a string"), 3)
  end
  local extensions = fields.extensions
  if extensions ~= nil then
    if type(extensions) ~= "table" then error(core.ArgumentError("problem extensions must be a table"), 3) end
    for key, value in pairs(extensions) do
      -- Cheap checks of what JSON cannot carry (the encoder would refuse it at the first answer): the nested values are
      -- left to `problems.from_problem`, which never lets an encoding failure escape.
      local kind = type(value)
      if kind == "function" or kind == "thread" or kind == "userdata" then
        error(core.ArgumentError(("problem extension %q is a %s, which has no JSON representation"):format(tostring(key), kind)), 3)
      end
      if kind == "number" and (value ~= value or value == math.huge or value == -math.huge) then
        error(core.ArgumentError(("problem extension %q is not a finite number"):format(tostring(key))), 3)
      end
      if type(key) ~= "string" then
        error(core.ArgumentError("problem extension names must be strings"), 3)
      end
      if RESERVED[key] then
        error(core.ArgumentError("problem extension name '" .. key .. "' is reserved (RFC 9457, section 3.1)"), 3)
      end
    end
  end
  local class = getmetatable(self)
  core.Error.init(self, { message = fields.detail or class.title or "Problem" })
  self.status = class.status
  self.title = class.title
  self.type = class.type
  self.detail = fields.detail
  self.extensions = extensions or {}
end

problem.Problem = core.finalise(Problem)

--- Declares a problem class for a status and a title.
---@param name string
---@param code string
---@param status integer
---@param title string
---@param uri string
---@return hecate.kernel.problem.Problem
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
  { "MethodNotAllowed", 405 }, { "Conflict", 409 }, { "Gone", 410 }, { "UnprocessableContent", 422 },
  { "TooManyRequests", 429 }, { "InternalServerError", 500 }, { "ServiceUnavailable", 503 },
}

for _, entry in ipairs(COMMON) do
  local name, status = entry[1], entry[2]
  problem[name] = declare(name, "hecate.problem." .. name, status, http.Status.reason(status) or "Error", "about:blank")
end

--- Declares an application's own problem class.
---
--- Raises `hecate.core.ArgumentError` when `name` is not a non-empty string, `status` is not an integer from 400 to
--- 599, `title` is not a non-empty string, or `type` is given and is not a string.
---@param name string
---@param spec { status: integer, title: string, type?: string }
---@return hecate.kernel.problem.Problem
function problem.define(name, spec)
  if type(name) ~= "string" or name == "" then
    error(core.ArgumentError("problem.define: the name must be a non-empty string"), 2)
  end
  if type(spec) ~= "table" then error(core.ArgumentError("problem.define: the declaration must be a table"), 2) end
  if math.type(spec.status) ~= "integer" or spec.status < 400 or spec.status > 599 then
    error(core.ArgumentError("problem.define: the status must be an integer from 400 to 599"), 2)
  end
  if type(spec.title) ~= "string" or spec.title == "" then
    error(core.ArgumentError("problem.define: the title must be a non-empty string"), 2)
  end
  if spec.type ~= nil and type(spec.type) ~= "string" then
    error(core.ArgumentError("problem.define: the type must be a string (a URI reference)"), 2)
  end
  return declare(name, name, spec.status, spec.title, spec.type or "about:blank")
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
