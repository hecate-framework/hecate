-- The type model and the validation core of hecate.schema (schemas-and-contracts.md, "Types" and "Validation").
--
-- A schema is an immutable value (a core value class). Its constructor compiles a validator closure once, at
-- declaration time; validating never walks the schema description (package invariants).
global <const> require, rawget, type, pairs, ipairs, next, table, string, math, utf8, pcall, tostring, tonumber, error

local core = require("hecate.core")
local json = require("hecate.json")
local violation_module = require("hecate.schema.violation")
local pattern_to_ecma = require("hecate.schema.pattern").to_ecma

local copy_value, remark
local Violation = violation_module.Violation
local escape_token = violation_module.escape_token
local math_type = math.type
local null = json.null

--- A read-only record of named values: a value class, so that writes raise `ConformanceError`.
---@class hecate.schema.Record
---@overload fun(fields: table): hecate.schema.Record
local Record = core.value_class("Record")

---@param fields table
function Record:init(fields)
  for key, value in pairs(fields) do self[key] = value end
end

core.finalise(Record)

--- A validator: appends the violations of `value` (at JSON Pointer `path`) to `out`.
---@alias hecate.schema.Validator fun(value: any, path: string, out: hecate.schema.RawViolation[])

--- A coercer: returns `value` converted from its textual form to the type of the schema; appends a `coercion`
--- violation to `out` when a text cannot be converted. Values that are not text pass through unchanged.
---@alias hecate.schema.Coercer fun(value: any, path: string, out: hecate.schema.RawViolation[]): any

--- A builder: returns the conforming `value` with every class-bound part replaced by an instance of its class.
---@alias hecate.schema.Builder fun(value: any): any

--- A violation as collected during validation, before it becomes a `Violation`.
---@class hecate.schema.RawViolation
---@field [1] string  path
---@field [2] string  code
---@field [3] string  message
---@field [4] table?  context

--- A type declaration: base type, refinement, product, collection or sum.
---@class hecate.schema.Schema
---@field kind string  "string", "integer", "number", "boolean", "literal", "enumeration", "object", "array", "map", "optional", "nullable", "union", "default", "tagged_union", "any", "null", "named" or "class"
---@field options hecate.schema.Record  the declared refinements (read-only)
---@field properties? hecate.schema.Record  property name to schema (variant name to derived `object` schema for a `tagged_union`)
---@field members fun(self: hecate.schema.Schema): any[]  the alternatives of a `union` or the constants of an `enumeration`, as a new list (empty for other kinds)
---@field item? hecate.schema.Schema  element schema of an `array`, wrapped schema of `optional` and `nullable`
---@field validator hecate.schema.Validator  compiled validator closure
---@field coercer hecate.schema.Coercer  compiled coercion closure (textual input to typed value)
---@field relaxed_validator hecate.schema.Validator  validator of PATCH content: the required properties of the top-level object may be absent
---@field builder hecate.schema.Builder  compiled builder of instances (see `Schema:build`)
---@field coerce fun(self: hecate.schema.Schema, value: any): boolean, any  see `Schema:coerce`
---@field to_json_schema fun(self: hecate.schema.Schema): table  the JSON Schema 2020-12 document of the schema
---@overload fun(kind: string, parts: table): hecate.schema.Schema
local Schema = core.value_class("Schema")

---@param kind string
---@param parts table  `options`, `properties`, `item`, `members` and the compiled `validator`
function Schema:init(kind, parts)
  self.kind = kind
  self.options = Record(parts.options or {})
  self.properties = parts.properties and Record(parts.properties)
  self.item = parts.item
  local list = parts.members or {}
  -- A closure over a private list, so that nothing a caller holds can change the schema.
  self.members = function() return { table.unpack(list) } end
  self.validator = parts.validator
  self.coercer = parts.coercer or function(value) return value end
  self.relaxed_validator = parts.relaxed_validator or parts.validator
  self.builder = parts.builder or function(value) return value end
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
      refuse(("%s: unknown option %s"):format(constructor, tostring(name)), { option = tostring(name) })
    end
    local ok
    if expected == "integer" then ok = math_type(value) == "integer"
    elseif expected == "number" then ok = type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
    else ok = type(value) == expected end
    if not ok then
      refuse(("%s: option %s must be %s"):format(constructor, name, expected == "integer" and "an integer" or "a " .. expected),
        { option = name })
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

--- Gives `result` the JSON array or object marker of `value`, so that an empty one still encodes as it was sent.
function remark(value, result)
  if json.is_array(value) then return json.array(result) end
  if json.is_object(value) then return json.object(result) end
  return result
end

local function type_violation(path, expected, out)
  out[#out + 1] = { path, "type", "expected " .. expected, { expected = expected } }
end

---@class hecate.schema
local M = {}

--- Key of the presence set inside an instance built by `Schema:build` (OQ-90). A private table, never a string, so that
--- the set cannot clash with an attribute and does not appear among the string keys of the instance. (A weak-keyed table
--- would need a raw `setmetatable`, reserved to `hecate.core` by `check-boundaries`.)
local PRESENCE = {}

--- Checks of the `format` option of `string` (JSON Schema 2020-12 section 7.3). Conservative subsets: `uuid` (RFC 9562 text
--- form), `date` and `date-time` (RFC 3339), `email` (one `@`, non-empty local part and dotted domain, no whitespace), `ipv4` (dotted quad, RFC 2673 section 3.2, no leading zeros).
local function days_in_month(year, month)
  if month == 2 then return (year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)) and 29 or 28 end
  return (month == 4 or month == 6 or month == 9 or month == 11) and 30 or 31
end

local function is_date(text)
  local y, m, d = text:match("^(%d%d%d%d)-(%d%d)-(%d%d)$")
  if not y then return false end
  y, m, d = tonumber(y), tonumber(m), tonumber(d)
  return m >= 1 and m <= 12 and d >= 1 and d <= days_in_month(y, m)
end

local FORMATS = {
  uuid = function(text)
    return text:find("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil
  end,
  date = is_date,
  ["date-time"] = function(text)
    local date, time = text:match("^(%d%d%d%d%-%d%d%-%d%d)[Tt](.+)$")
    if not date or not is_date(date) then return false end
    local h, mi, s, rest = time:match("^(%d%d):(%d%d):(%d%d)(.*)$")
    if not h or tonumber(h) > 23 or tonumber(mi) > 59 or tonumber(s) > 60 then return false end
    rest = rest:gsub("^%.%d+", "")
    if rest == "Z" or rest == "z" then return true end
    local oh, om = rest:match("^[+-](%d%d):(%d%d)$")
    return oh ~= nil and tonumber(oh) <= 23 and tonumber(om) <= 59
  end,
  ipv4 = function(text)
    local a, b, c, d = text:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    if not a then return false end
    for _, part in ipairs({ a, b, c, d }) do
      if #part > 3 or (#part > 1 and part:sub(1, 1) == "0") or tonumber(part) > 255 then return false end
    end
    return true
  end,
  email = function(text)
    if text:find("[%s]") then return false end
    local local_part, domain = text:match("^([^@]+)@([^@]+)$")
    return local_part ~= nil and domain:find("^[^.]+%.[^.]+") ~= nil and not domain:find("%.%.")
      and not domain:find("^%.") and not domain:find("%.$")
  end,
}

--- Declares a string type.
--- `pattern` is a Lua pattern for now (OQ-85); lengths count Unicode code points (JSON Schema 2020-12 section 6.3.1).
--- A `pattern` that `to_json_schema` cannot translate (`%b`, `%f`, ...) is reported at declaration with
--- `logger:warning(message, fields)` when a `logger` (any object with that method, for example a `hecate.log` logger) is given
--- (OQ-85, point 1); the schema stays valid for Lua validation and emission refuses it.
---@param options? { min_length?: integer, max_length?: integer, pattern?: string, format?: string, logger?: { warning: fun(self: table, message: string, fields?: table) } }
---@return hecate.schema.Schema
function M.string(options)
  local o = read_options("string", options,
    { min_length = "integer", max_length = "integer", pattern = "string", format = "string", logger = "table" })
  local logger = o.logger
  o.logger = nil
  check_range("string", o, "min_length", "max_length")
  local min_length, max_length, pattern = o.min_length, o.max_length, o.pattern
  local check_format = nil
  if o.format ~= nil then
    check_format = FORMATS[o.format]
    if check_format == nil then
      refuse("string: unknown format " .. o.format, { option = "format" })
    end
  end
  if pattern ~= nil and not pcall(string.find, "", pattern) then
    refuse("string: option pattern is not a valid pattern", { option = "pattern" })
  end
  if pattern ~= nil and logger ~= nil then
    local translated, err = pcall(pattern_to_ecma, pattern)
    if not translated then
      logger:warning("schema: the pattern cannot be emitted as a JSON Schema pattern",
        { pattern = pattern, reason = tostring(err) })
    end
  end
  local checks_length = min_length ~= nil or max_length ~= nil
  local validator = function(value, path, out)
    if type(value) ~= "string" then return type_violation(path, "string", out) end
    if checks_length then
      local length = utf8.len(value)
      if length == nil then
        out[#out + 1] = { path, "invalid_utf8", "the string is not well-formed UTF-8" }
      else
        if min_length and length < min_length then
          out[#out + 1] = { path, "min_length", "the string is shorter than " .. min_length, { min_length = min_length } }
        end
        if max_length and length > max_length then
          out[#out + 1] = { path, "max_length", "the string is longer than " .. max_length, { max_length = max_length } }
        end
      end
    end
    if pattern and not value:find(pattern) then
      out[#out + 1] = { path, "pattern", "the string does not match the pattern", { pattern = pattern } }
    end
    if check_format and not check_format(value) then
      out[#out + 1] = { path, "format", "the string is not a valid " .. o.format, { format = o.format } }
    end
  end
  return Schema("string", { options = o, validator = validator })
end

local function coercion_violation(path, expected, out)
  out[#out + 1] = { path, "coercion", "the text is not " .. expected, { expected = expected } }
end

--- Converts a decimal text to an integer; nil when it is not one or does not fit.
local function text_to_integer(text)
  if not text:find("^-?%d+$") then return nil end
  local number = tonumber(text)
  if math_type(number) == "integer" then return number end
  return nil
end

--- Converts a text in the JSON number grammar to a Lua number (integer when written without fraction or exponent).
local function text_to_number(text)
  local integer = text_to_integer(text)
  if integer then return integer end
  if text:find("^-?%d+$") then return nil end -- an integer too large for Lua: no silent loss of precision
  if text:find("^-?%d+%.%d+$") or text:find("^-?%d+%.?%d*[eE][+-]?%d+$") then
    local number = tonumber(text)
    if number and number == number and number ~= math.huge and number ~= -math.huge then return number end
  end
  return nil
end

local function text_to_boolean(text)
  if text == "true" then return true elseif text == "false" then return false end
  return nil
end

local function scalar_coercer(convert, expected)
  return function(value, path, out)
    if type(value) ~= "string" then return value end
    local converted = convert(value)
    if converted == nil then
      coercion_violation(path, expected, out)
      return value
    end
    return converted
  end
end

local function numeric(kind, accepts, expected, options)
  local o = read_options(kind, options, { minimum = "number", maximum = "number",
    exclusive_minimum = "number", exclusive_maximum = "number", multiple_of = "number" })
  if o.multiple_of ~= nil and o.multiple_of <= 0 then
    refuse(kind .. ": option multiple_of must be greater than zero", { option = "multiple_of" })
  end
  check_range(kind, o, "minimum", "maximum")
  check_range(kind, o, "exclusive_minimum", "exclusive_maximum")
  local minimum, maximum = o.minimum, o.maximum
  local exclusive_minimum, exclusive_maximum = o.exclusive_minimum, o.exclusive_maximum
  local multiple_of = o.multiple_of
  local validator = function(value, path, out)
    if not accepts(value) then return type_violation(path, expected, out) end
    if minimum and value < minimum then
      out[#out + 1] = { path, "minimum", "the value is less than " .. minimum, { minimum = minimum } }
    end
    if maximum and value > maximum then
      out[#out + 1] = { path, "maximum", "the value is greater than " .. maximum, { maximum = maximum } }
    end
    if exclusive_minimum and value <= exclusive_minimum then
      out[#out + 1] = { path, "exclusive_minimum", "the value is not greater than " .. exclusive_minimum,
        { exclusive_minimum = exclusive_minimum } }
    end
    if exclusive_maximum and value >= exclusive_maximum then
      out[#out + 1] = { path, "exclusive_maximum", "the value is not less than " .. exclusive_maximum,
        { exclusive_maximum = exclusive_maximum } }
    end
    -- Exact remainder (math.fmod is exact for floats): 0.3 is not a multiple of 0.1, as in IEEE 754 arithmetic.
    if multiple_of and math.fmod(value, multiple_of) ~= 0 then
      out[#out + 1] = { path, "multiple_of", "the value is not a multiple of " .. multiple_of, { multiple_of = multiple_of } }
    end
  end
  local coercer = scalar_coercer(kind == "integer" and text_to_integer or text_to_number, "a" .. (kind == "integer" and "n integer" or " number"))
  return Schema(kind, { options = o, validator = validator, coercer = coercer })
end

--- Declares an integer type: only Lua integers conform, `1.0` does not (OQ-85).
---@param options? { minimum?: number, maximum?: number }
---@return hecate.schema.Schema
function M.integer(options)
  return numeric("integer", function(v) return math_type(v) == "integer" end, "integer", options)
end

--- Declares a number type: Lua integers and finite floats conform, NaN and infinities do not (JSON has none).
---@param options? { minimum?: number, maximum?: number }
---@return hecate.schema.Schema
function M.number(options)
  return numeric("number", function(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end,
    "number", options)
end

--- Declares a boolean type.
---@return hecate.schema.Schema
function M.boolean()
  return Schema("boolean", { validator = function(value, path, out)
    if type(value) ~= "boolean" then return type_violation(path, "boolean", out) end
  end, coercer = scalar_coercer(text_to_boolean, "a boolean (true or false)") })
end

--- Same type and, for numbers, same Lua subtype: `1` and `1.0` are different constants.
local function same_constant(a, b)
  return a == b and math_type(a) == math_type(b)
end

---@param constructor string
---@param value any
local function require_constant(constructor, value)
  local t = type(value)
  if not (t == "string" or t == "boolean" or t == "number" or value == null) then
    refuse(constructor .. ": a constant is a string, number, boolean or null, got " .. t)
  end
end

--- Builds the coercer of a list of constants: a text converts to the constant whose textual form it is.
local function constants_coercer(constants)
  local count = #constants
  return function(value, path, out)
    if type(value) ~= "string" then return value end
    for i = 1, count do
      local constant = constants[i]
      local t = type(constant)
      local converted
      if t == "string" then converted = value == constant and value or nil
      elseif t == "boolean" then converted = text_to_boolean(value)
      elseif t == "number" then converted = text_to_number(value)
      elseif value == "null" then converted = null end
      if converted ~= nil and same_constant(converted, constant) then return converted end
    end
    return value -- the validator reports the constant that was expected
  end
end

--- Declares a type with exactly one value (JSON Schema `const`).
---@param value string|number|boolean|hecate.json.Null
---@return hecate.schema.Schema
function M.literal(value)
  require_constant("literal", value)
  return Schema("literal", { options = { value = value }, coercer = constants_coercer({ value }),
    validator = function(v, path, out)
      if not same_constant(v, value) then
        out[#out + 1] = { path, "literal", "the value is not the expected constant", { value = value } }
      end
    end })
end

--- Declares a type whose values are the members of a list of constants (JSON Schema `enum`).
---@param values (string|number|boolean|hecate.json.Null)[]
---@return hecate.schema.Schema
function M.enumeration(values)
  if type(values) ~= "table" or #values == 0 then refuse("enumeration: expects a non-empty list of constants") end
  local copy = {}
  for i, value in ipairs(values) do
    require_constant("enumeration", value)
    copy[i] = value
  end
  local count = #copy
  return Schema("enumeration", { members = copy, coercer = constants_coercer(copy), validator = function(v, path, out)
    for i = 1, count do
      if same_constant(v, copy[i]) then return end
    end
    out[#out + 1] = { path, "enum", "the value is not one of the allowed values", { values = { table.unpack(copy) } } }
  end })
end

--- Marks a property of an `object` as allowed to be absent. Only meaningful as a property schema.
--- Absent is not null: use `nullable` to accept JSON null.
---@param inner hecate.schema.Schema
---@return hecate.schema.Schema
function M.optional(inner)
  require_schema("optional", inner)
  if inner.kind == "optional" then refuse("optional: already optional") end
  if inner.kind == "default" then refuse("optional: a property with a default is already optional") end
  return Schema("optional", { item = inner, validator = inner.validator, coercer = inner.coercer, builder = inner.builder })
end

--- Accepts JSON null (`hecate.json.null`) in addition to the values of `inner`. Lua `nil` is absence, never null.
---@param inner hecate.schema.Schema
---@return hecate.schema.Schema
function M.nullable(inner)
  require_schema("nullable", inner)
  local validate_inner = inner.validator
  -- A text is never coerced to null: the textual forms of a missing value are not agreed (OQ-86).
  local build_inner = inner.builder
  return Schema("nullable", { item = inner, coercer = inner.coercer,
    builder = function(value) if value == null then return value end return build_inner(value) end,
    validator = function(value, path, out)
    if value == null then return end
    return validate_inner(value, path, out)
  end })
end

--- A deep copy of a decoded JSON value (markers of `hecate.json` are kept), so that a default is never shared.
function copy_value(value)
  if type(value) ~= "table" or value == null then return value end
  local copy = {}
  for key, member in next, value do copy[key] = copy_value(member) end
  if json.is_array(value) then return json.array(copy) end
  if json.is_object(value) then return json.object(copy) end
  return copy
end

--- Structural equality of decoded JSON values; `1` and `1.0` are equal numbers, as in JSON Schema.
local function json_equal(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" or a == null or b == null then return false end
  local count = 0
  for key, member in next, a do
    if not json_equal(member, b[key]) then return false end
    count = count + 1
  end
  for _ in next, b do count = count - 1 end
  return count == 0
end

--- Index of the first item equal to an earlier one, or nil.
local function first_duplicate(list, length)
  for i = 2, length do
    for j = 1, i - 1 do
      if json_equal(list[i], list[j]) then return i end
    end
  end
  return nil
end

--- Declares a sequence type with a schema for every element. Paths use 0-based indices (RFC 6901 section 4).
---@param item hecate.schema.Schema
---@param options? { min_items?: integer, max_items?: integer, delimiter?: string, unique_items?: boolean }
---@return hecate.schema.Schema
function M.array(item, options)
  require_schema("array", item)
  local o = read_options("array", options, { min_items = "integer", max_items = "integer", delimiter = "string",
    unique_items = "boolean" })
  if o.delimiter == "" then refuse("array: option delimiter must not be empty", { option = "delimiter" }) end
  check_range("array", o, "min_items", "max_items")
  local min_items, max_items = o.min_items, o.max_items
  local unique_items = o.unique_items == true
  local validate_item = item.validator
  local coerce_item = item.coercer
  local delimiter = o.delimiter or ","
  local build_item = item.builder
  local builder = function(value)
    local result = {}
    for i = 1, #value do result[i] = build_item(value[i]) end
    return remark(value, result)
  end
  local coercer = function(value, path, out)
    if type(value) == "string" then
      -- OpenAPI `style: form, explode: false` (delimiter "," by default; " " and "|" for the other styles).
      local parts, start = {}, 1
      if value ~= "" then
        while true do
          local from, to = value:find(delimiter, start, true)
          if not from then parts[#parts + 1] = value:sub(start) break end
          parts[#parts + 1] = value:sub(start, from - 1)
          start = to + 1
        end
      end
      value = parts
    elseif type(value) ~= "table" or value == null then
      return value
    end
    local result = {}
    for i = 1, #value do result[i] = coerce_item(value[i], path .. "/" .. (i - 1), out) end
    if #result ~= #value then return value end
    return result
  end
  return Schema("array", { options = o, item = item, coercer = coercer, builder = builder, validator = function(value, path, out)
    if type(value) ~= "table" or value == null then return type_violation(path, "array", out) end
    local length = #value
    local count = 0
    for _ in next, value do count = count + 1 end
    if count ~= length then return type_violation(path, "array", out) end
    if min_items and length < min_items then
      out[#out + 1] = { path, "min_items", "the array has fewer than " .. min_items .. " items", { min_items = min_items } }
    end
    if max_items and length > max_items then
      out[#out + 1] = { path, "max_items", "the array has more than " .. max_items .. " items", { max_items = max_items } }
    end
    for i = 1, length do
      validate_item(value[i], path .. "/" .. (i - 1), out)
    end
    if unique_items then
      local duplicate = first_duplicate(value, length)
      if duplicate then
        out[#out + 1] = { path .. "/" .. (duplicate - 1), "unique_items", "the item duplicates an earlier one",
          { index = duplicate - 1 } }
      end
    end
  end })
end

--- Declares a product type: named properties, each with a schema. Required unless wrapped in `optional`.
--- Properties not declared are rejected unless `additional_properties = true` (the default for request content).
---@param properties table<string, hecate.schema.Schema>
---@param options? { additional_properties?: boolean }
---@return hecate.schema.Schema
function M.object(properties, options)
  if type(properties) ~= "table" then refuse("object: properties must be a table, got " .. type(properties)) end
  local o = read_options("object", options, { additional_properties = "boolean" })
  local allow_additional = o.additional_properties == true
  local copy, names = {}, {}
  for name, property in pairs(properties) do
    if type(name) ~= "string" then refuse("object: property names are strings, got " .. type(name)) end
    require_schema("object", property)
    copy[name] = property
    names[#names + 1] = name
  end
  table.sort(names) -- a stable order of violations
  local count = #names
  local tokens, validators, optional = {}, {}, {}
  for i = 1, count do
    local property = copy[names[i]]
    tokens[i] = "/" .. escape_token(names[i])
    validators[i] = property.validator
    optional[i] = property.kind == "optional" or property.kind == "default"
  end
  local declared = {}
  for i = 1, count do declared[names[i]] = true end
  local coercers, defaults = {}, {}
  for i = 1, count do
    local property = copy[names[i]]
    coercers[i] = property.coercer
    if property.kind == "default" then defaults[i] = property.options.value end
  end
  local builders = {}
  for i = 1, count do builders[i] = copy[names[i]].builder end
  local builder = function(value)
    local result = {}
    for key, member in next, value do result[key] = member end
    for i = 1, count do
      local member = value[names[i]]
      if member ~= nil then result[names[i]] = builders[i](member) end
    end
    return remark(value, result)
  end
  local coercer = function(value, path, out)
    if type(value) ~= "table" or value == null then return value end
    local result = {}
    for key, member in next, value do result[key] = member end
    for i = 1, count do
      local member = value[names[i]]
      if member ~= nil then
        result[names[i]] = coercers[i](member, path .. tokens[i], out)
      elseif defaults[i] ~= nil then
        result[names[i]] = copy_value(defaults[i]) -- an absent property takes its default
      end
    end
    return result
  end
  --- `relax`: the PATCH variant, where an absent property means unchanged (OQ-90).
  local function make_validator(relax) return function(value, path, out)
    if type(value) ~= "table" or value == null then return type_violation(path, "object", out) end
    for i = 1, count do
      local member = value[names[i]]
      if member == nil then
        if not (relax or optional[i]) then
          out[#out + 1] = { path .. tokens[i], "required", "the property is required", { property = names[i] } }
        end
      else
        validators[i](member, path .. tokens[i], out)
      end
    end
    local extras
    for key in next, value do
      if type(key) ~= "string" then
        return type_violation(path, "object", out)
      elseif not declared[key] and not allow_additional then
        extras = extras or {}
        extras[#extras + 1] = key
      end
    end
    if extras then
      table.sort(extras)
      for _, key in ipairs(extras) do
        out[#out + 1] = { path .. "/" .. escape_token(key), "additional_property",
          "the property is not declared", { property = key } }
      end
    end
  end end
  return Schema("object", { options = o, properties = copy, coercer = coercer, validator = make_validator(false),
    relaxed_validator = make_validator(true), builder = builder })
end

--- Declares a dictionary type: any string keys, every value conforming to `value_schema`. Paths use the key as
--- the reference token. A table with non-string keys is not a map.
---@param value_schema hecate.schema.Schema
---@param options? { min_properties?: integer, max_properties?: integer }
---@return hecate.schema.Schema
function M.map(value_schema, options)
  require_schema("map", value_schema)
  local o = read_options("map", options, { min_properties = "integer", max_properties = "integer" })
  check_range("map", o, "min_properties", "max_properties")
  local min_properties, max_properties = o.min_properties, o.max_properties
  local validate_value, coerce_value = value_schema.validator, value_schema.coercer
  local build_value = value_schema.builder
  local builder = function(value)
    local result = {}
    for key, member in next, value do result[key] = build_value(member) end
    return remark(value, result)
  end
  local coercer = function(value, path, out)
    if type(value) ~= "table" or value == null then return value end
    local result = {}
    for key, member in next, value do
      result[key] = type(key) == "string" and coerce_value(member, path .. "/" .. escape_token(key), out) or member
    end
    return result
  end
  return Schema("map", { options = o, item = value_schema, coercer = coercer, builder = builder, validator = function(value, path, out)
    if type(value) ~= "table" or value == null then return type_violation(path, "object", out) end
    local keys = {}
    for key in next, value do
      if type(key) ~= "string" then return type_violation(path, "object", out) end
      keys[#keys + 1] = key
    end
    table.sort(keys) -- a stable order of violations
    local count = #keys
    if min_properties and count < min_properties then
      out[#out + 1] = { path, "min_properties", "the object has fewer than " .. min_properties .. " properties",
        { min_properties = min_properties } }
    end
    if max_properties and count > max_properties then
      out[#out + 1] = { path, "max_properties", "the object has more than " .. max_properties .. " properties",
        { max_properties = max_properties } }
    end
    for i = 1, count do
      validate_value(value[keys[i]], path .. "/" .. escape_token(keys[i]), out)
    end
  end })
end

--- Declares a sum type: a value conforms when at least one alternative accepts it (JSON Schema `anyOf`).
--- On failure one violation is reported at the union itself; the violations of every alternative are in
--- `context.alternatives`, in declaration order.
---@param alternatives hecate.schema.Schema[]
---@return hecate.schema.Schema
function M.union(alternatives)
  if type(alternatives) ~= "table" or #alternatives == 0 then refuse("union: expects a non-empty list of schemas") end
  local copy, validators = {}, {}
  for i, alternative in ipairs(alternatives) do
    require_schema("union", alternative)
    copy[i] = alternative
    validators[i] = alternative.validator
  end
  local count = #copy
  -- The first alternative that accepts the coerced value wins; when none does, the value is left as it is and
  -- the validator reports the union.
  local coercer = function(value, path)
    for i = 1, count do
      local scratch = {}
      local converted = copy[i].coercer(value, path, scratch)
      if #scratch == 0 then
        local found = {}
        validators[i](converted, path, found)
        if #found == 0 then return converted end
      end
    end
    return value
  end
  local builder = function(value)
    for i = 1, count do
      local found = {}
      validators[i](value, "", found)
      if #found == 0 then return copy[i].builder(value) end
    end
    return value
  end
  return Schema("union", { members = copy, coercer = coercer, builder = builder, validator = function(value, path, out)
    local failures = {}
    for i = 1, count do
      local found = {}
      validators[i](value, path, found)
      if #found == 0 then return end
      local converted = {}
      for j, raw in ipairs(found) do converted[j] = Violation(raw[1], raw[2], raw[3], raw[4]) end
      failures[i] = converted
    end
    out[#out + 1] = { path, "union", "the value matches none of the alternatives", { alternatives = failures } }
  end })
end

--- Gives a property a default: the property may be absent, and `coerce` then supplies `value` (a deep copy).
--- Validation never supplies it (it validates the value it is given), and JSON Schema emits it as the `default`
--- annotation (section 9.2), which does not change what is valid. The default must conform to `inner` (OQ-88).
---@param inner hecate.schema.Schema
---@param value any  a JSON value that conforms to `inner`
---@return hecate.schema.Schema
function M.default(inner, value)
  require_schema("default", inner)
  if inner.kind == "optional" or inner.kind == "default" then refuse("default: the property is already optional") end
  if value == nil then refuse("default: a default value is required (use json.null for null)") end
  local raw = {}
  inner.validator(value, "", raw)
  if #raw > 0 then refuse("default: the value does not conform to the schema", { code = raw[1][2] }) end
  local stored = copy_value(value)
  local coerce_inner = inner.coercer
  return Schema("default", { options = { value = stored }, item = inner, validator = inner.validator, builder = inner.builder,
    coercer = function(v, path, out)
      if v == nil then return copy_value(stored) end
      return coerce_inner(v, path, out)
    end })
end

--- Declares a discriminated sum type: `tag` names the property that selects the variant among `variants` (name to
--- `object` schema). Every variant gains a property `tag` that is the literal of its name, so the variants exclude
--- one another and the emission is `oneOf` (section 10.2.1.3). A variant must not declare `tag` itself.
--- On failure a missing tag is a `required` violation, an unknown one a `tagged_union` violation (both at the tag
--- property); otherwise the violations are those of the selected variant (OQ-88).
---@param tag string
---@param variants table<string, hecate.schema.Schema>
---@return hecate.schema.Schema
function M.tagged_union(tag, variants)
  if type(tag) ~= "string" or tag == "" then refuse("tagged_union: the tag is a non-empty string") end
  if type(variants) ~= "table" or next(variants) == nil then refuse("tagged_union: expects a non-empty table of variants") end
  local names, derived, validators, coercers = {}, {}, {}, {}
  for name in pairs(variants) do
    if type(name) ~= "string" then refuse("tagged_union: variant names are strings, got " .. type(name)) end
    names[#names + 1] = name
  end
  table.sort(names)
  for _, name in ipairs(names) do
    local variant = variants[name]
    require_schema("tagged_union", variant)
    if variant.kind ~= "object" then refuse("tagged_union: variant " .. name .. " is not an object schema") end
    local properties = {}
    for property_name, property in pairs(variant.properties --[[@as table]]) do
      if property_name == tag then
        refuse("tagged_union: variant " .. name .. " declares the tag property " .. tag, { variant = name })
      end
      properties[property_name] = property
    end
    properties[tag] = M.literal(name)
    local object = M.object(properties, { additional_properties = (variant.options --[[@as table]]).additional_properties })
    derived[name], validators[name], coercers[name] = object, object.validator, object.coercer
  end
  local token = "/" .. escape_token(tag)
  return Schema("tagged_union", { options = { tag = tag }, properties = derived, members = names,
    builder = function(value) return derived[value[tag]].builder(value) end,
    coercer = function(value, path, out)
      if type(value) ~= "table" or value == null then return value end
      local name = value[tag]
      local coerce = type(name) == "string" and coercers[name]
      if not coerce then return value end -- the validator reports the tag
      return coerce(value, path, out)
    end,
    validator = function(value, path, out)
      if type(value) ~= "table" or value == null then return type_violation(path, "object", out) end
      local name = value[tag]
      if name == nil then
        out[#out + 1] = { path .. token, "required", "the property is required", { property = tag } }
        return
      end
      local validate = type(name) == "string" and validators[name]
      if not validate then
        out[#out + 1] = { path .. token, "tagged_union", "the value is not the name of a variant",
          { tag = tag, values = { table.unpack(names) } } }
        return
      end
      return validate(value, path, out)
    end })
end

--- Accepts every JSON value. Emitted as the empty schema `{}`.
---@return hecate.schema.Schema
function M.any()
  return Schema("any", { validator = function() end })
end

--- Accepts JSON null only (`hecate.json.null`); Lua `nil` is absence.
---@return hecate.schema.Schema
function M.null()
  return Schema("null", { validator = function(value, path, out)
    if value ~= null then return type_violation(path, "null", out) end
  end })
end

--- Gives a schema a name. The name is the key of the definition in the emission (`$defs`, referenced by `$ref`),
--- and becomes an OpenAPI component. A name is made of letters, digits, `_`, `.` and `-`; two different schemas
--- with the same name in one emission raise `ArgumentError` (OQ-89). Validation and coercion are those of `inner`.
---@param name string
---@param inner hecate.schema.Schema
---@return hecate.schema.Schema
function M.named(name, inner)
  if type(name) ~= "string" or not name:find("^[%w_.%-]+$") then
    refuse("named: the name is a non-empty string of letters, digits, '_', '.' and '-'")
  end
  require_schema("named", inner)
  if inner.kind == "named" then refuse("named: the schema already has the name " .. (inner.options --[[@as table]]).name) end
  return Schema("named", { options = { name = name }, item = inner, validator = inner.validator, coercer = inner.coercer,
    relaxed_validator = inner.relaxed_validator, builder = inner.builder })
end

--- The schema of a class: `target` is a class that declares a class-level function `schema()` returning its schema,
--- or the name of a module returning such a class (loaded at first use, so that two modules can refer to each other).
--- Resolution is lazy and memoized: `schema()` is called at first validation, coercion or emission, never at
--- declaration, so classes may refer to each other, or to themselves. The emission closes a cycle with a `$ref` to the
--- `$defs` entry named after the class (OQ-50). The result of `schema()` is emitted under the class name.
---@param target table|string  a class, or a module name
---@return hecate.schema.Schema
function M.of(target)
  if type(target) ~= "table" and type(target) ~= "string" then
    refuse("of: expects a class or a module name, got " .. type(target))
  end
  local resolved, resolving, bound_class
  local function resolve()
    if resolved ~= nil then return resolved end
    if resolving then error(core.ArgumentError("schema.of: the schema() of a class refers to itself while being resolved; use schema.of(Class) inside it, not Class.schema()")) end
    resolving = true
    local ok, result = pcall(function()
      local class = target
      if type(class) == "string" then class = require(class) end
      if type(class) ~= "table" or type(class.schema) ~= "function" then
        refuse("of: the class must declare a class-level function schema()")
      end
      bound_class = class
      local inner = class.schema()
      require_schema("of", inner)
      if inner.kind == "named" then return inner end
      return M.named(core.name(class), inner)
    end)
    resolving = false
    if not ok then error(result, 0) end
    resolved = result
    return resolved
  end
  --- Builds an instance: the attributes are the declared properties, an explicit null leaves the attribute nil, and the
  --- presence set records which properties were sent (OQ-90). The class is instantiated with no argument.
  local function build(value)
    local named = resolve()
    local object = named.item --[[@as hecate.schema.Schema]]
    local fields = named.builder(value)
    if object.kind ~= "object" then return fields end
    local instance, present = bound_class(), {}
    for name in pairs(object.properties --[[@as table]]) do
      local member = value[name]
      if member ~= nil then
        present[name] = true
        if member ~= null then instance[name] = fields[name] end
      end
    end
    instance[PRESENCE] = present
    return instance
  end
  return Schema("class", { options = { resolve = resolve },
    builder = build,
    relaxed_validator = function(value, path, out) return resolve().relaxed_validator(value, path, out) end,
    validator = function(value, path, out) return resolve().validator(value, path, out) end,
    coercer = function(value, path, out) return resolve().coercer(value, path, out) end })
end

--- Tells whether the attribute `name` was present in the content an instance was built from. An explicit
--- `null` counts as sent; an instance that was not built by `Schema:build` has sent nothing.
---@param instance table
---@param name string
---@return boolean
function M.sent(instance, name)
  local present = type(instance) == "table" and rawget(instance, PRESENCE)
  return present and present[name] == true or false
end

local DIALECT = "https://json-schema.org/draft/2020-12/schema"

--- Definitions collected by the emission in progress (`named` schemas), by name.
local defs
local PENDING = {}

--- Emits the JSON Schema 2020-12 subschema of `s` (no `$schema`). Every construct has an exact emission, or the
--- emission is refused (schemas-and-contracts.md, "JSON Schema").
---@param s hecate.schema.Schema
---@return table
local function emit(s)
  local kind = s.kind
  local o = s.options --[[@as table]]
  if kind == "any" then
    return {}
  elseif kind == "null" then
    return { type = "null" }
  elseif kind == "class" then
    return emit(o.resolve())
  elseif kind == "named" then
    local name = o.name
    if defs[name] == PENDING then return { ["$ref"] = "#/$defs/" .. name } end -- a cycle: closed by the reference
    local previous = defs[name]
    defs[name] = PENDING
    local ok, body = pcall(emit, s.item)
    defs[name] = previous
    if not ok then error(body, 0) end
    if previous == nil then defs[name] = body
    elseif not json_equal(previous, body) then
      error(core.ArgumentError("to_json_schema: two different schemas are named " .. name, { context = { name = name } }))
    end
    return { ["$ref"] = "#/$defs/" .. name }
  elseif kind == "string" then
    return { type = "string", minLength = o.min_length, maxLength = o.max_length,
      pattern = o.pattern ~= nil and pattern_to_ecma(o.pattern) or nil, format = o.format }
  elseif kind == "integer" or kind == "number" then
    return { type = kind, minimum = o.minimum, maximum = o.maximum,
      exclusiveMinimum = o.exclusive_minimum, exclusiveMaximum = o.exclusive_maximum, multipleOf = o.multiple_of }
  elseif kind == "boolean" then
    return { type = "boolean" }
  elseif kind == "literal" then
    return { const = o.value }
  elseif kind == "enumeration" then
    return { enum = s:members() }
  elseif kind == "array" then
    return { type = "array", items = emit(s.item), minItems = o.min_items, maxItems = o.max_items,
      uniqueItems = o.unique_items }
  elseif kind == "map" then
    return { type = "object", additionalProperties = emit(s.item), minProperties = o.min_properties,
      maxProperties = o.max_properties }
  elseif kind == "optional" then
    return emit(s.item) -- absence is expressed by the parent's `required`
  elseif kind == "default" then
    local emitted = emit(s.item)
    emitted.default = copy_value(o.value)
    return emitted
  elseif kind == "tagged_union" then
    local alternatives = {}
    for i, name in ipairs(s:members()) do alternatives[i] = emit(s.properties[name]) end
    return { oneOf = alternatives }
  elseif kind == "nullable" then
    return { anyOf = { emit(s.item), { type = "null" } } }
  elseif kind == "union" then
    local alternatives = {}
    for i, alternative in ipairs(s:members()) do alternatives[i] = emit(alternative) end
    return { anyOf = alternatives }
  elseif kind == "object" then
    local properties, required = {}, {}
    for name, property in pairs(s.properties) do
      properties[name] = emit(property)
      if property.kind ~= "optional" and property.kind ~= "default" then required[#required + 1] = name end
    end
    table.sort(required)
    return {
      type = "object",
      properties = properties,
      required = #required > 0 and required or nil,
      additionalProperties = o.additional_properties == true,
    }
  end
  error(core.ArgumentError("to_json_schema: unknown kind " .. tostring(kind)))
end

--- Emits the schema as a JSON Schema 2020-12 document (a new table of plain values, encodable with `hecate.json`).
--- The emission accepts what Lua validation accepts, with these documented differences (OQ-85): JSON Schema does
--- not tell `1` from `1.0`, so `integer` and the constants also accept float-valued numbers. A `pattern` option
--- is translated to ECMA-262 by `hecate.schema.pattern`; a construct outside its subset raises `ArgumentError`.
---@return table document  the root carries `$schema`
function Schema:to_json_schema()
  defs = {}
  local ok, document = pcall(emit, self)
  local collected = defs
  defs = nil
  if not ok then error(document, 0) end
  if next(collected) ~= nil then document["$defs"] = collected end
  document["$schema"] = DIALECT
  return document
end

--- Validates `value` and collects every violation, in the order of the declaration (properties by name).
---@param value any
---@return boolean ok  true when the value conforms
---@return hecate.schema.Violation[]? violations  present only when `ok` is false
function Schema:validate(value)
  local raw = {}
  self.validator(value, "", raw)
  if #raw == 0 then return true end
  local violations = {}
  for i, v in ipairs(raw) do violations[i] = Violation(v[1], v[2], v[3], v[4]) end
  return false, violations
end

--- Converts a value read from text (path, query or header fields: strings, lists of strings for repeated keys,
--- tables of them) to the type of the schema, then validates the result. Texts convert as follows: `integer` and
--- `number` read the JSON number grammar, `boolean` reads `true` or `false`, `array` splits a text on its
--- `delimiter` option (default ",") or takes a list, `object` converts its declared properties, `union` takes the
--- first alternative that accepts the converted value. Values that are not texts are validated as they are, and
--- the input is never modified. A text that cannot be converted yields a `coercion` violation.
---@param value any
---@return boolean ok  true when the value converted and conforms
---@return any result  the converted value when `ok`, else a list of `hecate.schema.Violation`
function Schema:coerce(value)
  local raw = {}
  local converted = self.coercer(value, "", raw)
  if #raw == 0 then self.validator(converted, "", raw) end
  if #raw == 0 then return true, converted end
  local violations = {}
  for i, v in ipairs(raw) do violations[i] = Violation(v[1], v[2], v[3], v[4]) end
  return false, violations
end

local METHODS = { POST = false, PUT = false, PATCH = true }

--- Validates decoded content (no text conversion) and builds the value it describes: every class-bound part (see
--- `schema.of`) becomes an instance of its class, whose attributes are the properties of its schema. An absent
--- attribute is nil, an explicit `null` is nil too and `schema.sent` tells them apart. `options.method` is the HTTP
--- method the content arrived with (OQ-50): `"POST"` and `"PUT"` (the default) are strict; `"PATCH"` lets the
--- required properties of the top-level object be absent (unchanged), while `null` still fails unless nullable.
---@param value any  decoded content
---@param options? { method?: "POST"|"PUT"|"PATCH" }
---@return boolean ok  true when the content conforms
---@return any result  the built value when `ok`, else a list of `hecate.schema.Violation`
function Schema:build(value, options)
  local relax = false
  if options ~= nil then
    local o = read_options("build", options, { method = "string" })
    if o.method ~= nil then
      relax = METHODS[o.method]
      if relax == nil then refuse("build: method must be POST, PUT or PATCH, got " .. o.method, { option = "method" }) end
    end
  end
  local raw = {}
  ;(relax and self.relaxed_validator or self.validator)(value, "", raw)
  if #raw == 0 then return true, self.builder(value) end
  local violations = {}
  for i, v in ipairs(raw) do violations[i] = Violation(v[1], v[2], v[3], v[4]) end
  return false, violations
end

--- Returns `value` when it conforms; raises `hecate.core.ValidationError` otherwise, with every violation in
--- `context.violations`.
---@generic T
---@param value T
---@return T
function Schema:check(value)
  local ok, violations = self:validate(value)
  if not ok then
    ---@cast violations hecate.schema.Violation[]
    error(core.ValidationError(("%d violation(s); first: %s"):format(#violations, tostring(violations[1])),
      { context = { violations = violations } }))
  end
  return value
end

core.finalise(Schema)

---@diagnostic disable-next-line: assign-type-mismatch
M.Schema = Schema
M.is_schema = is_schema
return M
