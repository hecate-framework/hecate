-- The Schema class, its read-only option tables and the checks shared by the constructors of hecate.schema.
-- Internal to `hecate.schema`: not public API. `schema.lua` and the other `internal/` modules require it.
global <const> require, type, pairs, table, tostring, math, error

local core = require("hecate.core")

local math_type = math.type

---@class hecate.schema.internal.model
local M = {}

--- A read-only table of named values (the declared refinements, the properties of a schema): a value class, so that
--- writes raise `ConformanceError`.
---@class hecate.schema.Options
---@overload fun(fields: table): hecate.schema.Options
local Options = core.value_class("Options")

---@param fields table
function Options:init(fields)
  for key, value in pairs(fields) do self[key] = value end
end

core.finalise(Options)

--- A validator: appends the violations of `value`, found at the node whose path has `at` reference tokens (see `path_to`),
--- to `out`.
---@alias hecate.schema.Validator fun(value: any, at: integer, out: hecate.schema.RawViolation[])

--- A coercer: returns `value` converted from its textual form to the type of the schema; appends a `coercion`
--- violation to `out` when a text cannot be converted. Values that are not text pass through unchanged.
---@alias hecate.schema.Coercer fun(value: any, at: integer, out: hecate.schema.RawViolation[]): any

--- A builder: returns the conforming `value` with every class-bound part replaced by an instance of its class.
---@alias hecate.schema.Builder fun(value: any): any

--- A representer: returns the plain JSON-ready form of `value` (found at the node whose path has `at` reference tokens), in fresh tables. It does not
--- validate; it raises `ValidationError` when the nesting guard or the work budget stops it (see `Schema:represent`).
---@alias hecate.schema.Representer fun(value: any, at: integer): any

--- A violation as collected during validation, before it becomes a `Violation`.
---@class hecate.schema.RawViolation
---@field [1] string  path
---@field [2] hecate.schema.ViolationCode  code
---@field [3] string  message
---@field [4] table?  context

--- A type declaration: base type, refinement, product, collection or sum. `kind`, `options`, `properties` and `item`
--- are read-only descriptions that `openapi` and `doc` may read; the compiled closures are internal to this package.
---@class hecate.schema.Schema
---@field kind string  "string", "integer", "number", "boolean", "literal", "enumeration", "object", "array", "map", "optional", "nullable", "union", "default", "tagged_union", "any", "null", "named" or "class"
---@field options hecate.schema.Options  the declared refinements (read-only)
---@field properties? hecate.schema.Options  property name to schema (variant name to derived `object` schema for a `tagged_union`)
---@field item? hecate.schema.Schema  element schema of an `array` or a `map`, wrapped schema of `optional`, `nullable`, `default` and `named`
---@field package validator hecate.schema.Validator  compiled validator closure
---@field package coercer hecate.schema.Coercer  compiled coercion closure (textual input to typed value)
---@field package relaxed_validator hecate.schema.Validator  validator of PATCH content: the required properties of the top-level object may be absent
---@field package builder hecate.schema.Builder  compiled builder of instances (see `Schema:build`)
---@field package representer hecate.schema.Representer  compiled representer of instances (see `Schema:represent`)
---@field package copy_default? fun(): any  a fresh copy of the default of a `default` schema (the stored value is not reachable)
---@field package prefilter? fun(value: any): boolean  cheap necessary condition for a value to conform (false: it cannot); absent when there is none
---@field private _members fun(): any[]  a new list of the members, from a private list
---@overload fun(kind: string, parts: table): hecate.schema.Schema
local Schema = core.value_class("Schema")

---@param kind string
---@param parts table  `options`, `properties`, `item`, `members` and the compiled closures
function Schema:init(kind, parts)
  self.kind = kind
  self.options = Options(parts.options or {})
  self.properties = parts.properties and Options(parts.properties)
  self.item = parts.item
  local list = parts.members or {}
  -- A closure over a private list, so that nothing a caller holds can change the schema.
  self._members = function() return { table.unpack(list) } end
  self.validator = parts.validator
  self.coercer = parts.coercer or function(value) return value end
  self.relaxed_validator = parts.relaxed_validator or parts.validator
  self.builder = parts.builder or function(value) return value end
  self.representer = parts.representer or function(value) return value end
  self.prefilter = parts.prefilter
  self.copy_default = parts.copy_default
end

local function refuse(message, context)
  error(core.ArgumentError("schema: " .. message, { context = context }), 3)
end

--- Checks the option table of a constructor: known names only, each of the expected type.
---@param constructor string
---@param options table?
---@param spec table<string, string>  option name to Lua type ("number", "integer", "string", "boolean")
---@return table options  a private copy
local function read_options(constructor, options, spec)
  options = options or {}
  if type(options) ~= "table" then refuse(constructor .. ": options must be a table, got " .. type(options)) end
  local copy = {}
  for name, value in pairs(options) do
    local expected = spec[name]
    if expected == nil then
      local accepted = {}
      for known in pairs(spec) do accepted[#accepted + 1] = known end
      table.sort(accepted)
      refuse(("%s: unknown option %s; accepted options: %s"):format(constructor, tostring(name), table.concat(accepted, ", ")),
        { option = tostring(name), accepted = accepted })
    end
    local ok
    if expected == "integer" then ok = math_type(value) == "integer"
    elseif expected == "number" then ok = type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
    else ok = type(value) == expected end
    if not ok then
      refuse(("%s: option %s must be %s, got %s"):format(constructor, name,
        expected == "integer" and "an integer" or "a " .. expected, type(value)), { option = name })
    end
    copy[name] = value
  end
  return copy
end

local function check_range(constructor, options, low, high)
  if options[low] ~= nil and options[high] ~= nil and options[low] > options[high] then
    refuse(("%s: %s is greater than %s"):format(constructor, low, high), { option = low })
  end
end

---@param value any
---@return boolean
local function is_schema(value)
  return type(value) == "table" and core.is_instance_of(value, Schema)
end

---@param constructor string
---@param value any
local function require_schema(constructor, value)
  if not is_schema(value) then refuse(constructor .. ": expected a schema, got " .. type(value)) end
end

M.Options = Options
M.Schema = Schema
M.refuse = refuse
M.read_options = read_options
M.check_range = check_range
M.is_schema = is_schema
M.require_schema = require_schema
return M
