-- The type model and the validation core of hecate.schema (schemas-and-contracts.md, "Types" and "Validation").
--
-- A schema is an immutable value (a core value class). Its constructor compiles a validator closure once, at
-- declaration time; validating never walks the schema description (package invariants).
global <const> require, type, pairs, ipairs, next, table, string, math, utf8, pcall, tostring, tonumber, error

local core = require("hecate.core")
local json = require("hecate.json")
local violation_module = require("hecate.schema.violation")

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

--- A violation as collected during validation, before it becomes a `Violation`.
---@class hecate.schema.RawViolation
---@field [1] string  path
---@field [2] string  code
---@field [3] string  message
---@field [4] table?  context

--- A type declaration: base type, refinement, product, collection or sum.
---@class hecate.schema.Schema
---@field kind string  "string", "integer", "number", "boolean", "literal", "enumeration", "object", "array", "optional", "nullable" or "union"
---@field options hecate.schema.Record  the declared refinements (read-only)
---@field properties? hecate.schema.Record  property name to schema
---@field members fun(self: hecate.schema.Schema): any[]  the alternatives of a `union` or the constants of an `enumeration`, as a new list (empty for other kinds)
---@field item? hecate.schema.Schema  element schema of an `array`, wrapped schema of `optional` and `nullable`
---@field validator hecate.schema.Validator  compiled validator closure
---@field coercer hecate.schema.Coercer  compiled coercion closure (textual input to typed value)
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

local function type_violation(path, expected, out)
  out[#out + 1] = { path, "type", "expected " .. expected, { expected = expected } }
end

---@class hecate.schema
local M = {}

--- Declares a string type.
--- `pattern` is a Lua pattern for now (OQ-85); lengths count Unicode code points (JSON Schema 2020-12 section 6.3.1).
---@param options? { min_length?: integer, max_length?: integer, pattern?: string }
---@return hecate.schema.Schema
function M.string(options)
  local o = read_options("string", options, { min_length = "integer", max_length = "integer", pattern = "string" })
  check_range("string", o, "min_length", "max_length")
  local min_length, max_length, pattern = o.min_length, o.max_length, o.pattern
  if pattern ~= nil and not pcall(string.find, "", pattern) then
    refuse("string: option pattern is not a valid pattern", { option = "pattern" })
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
    exclusive_minimum = "number", exclusive_maximum = "number" })
  check_range(kind, o, "minimum", "maximum")
  check_range(kind, o, "exclusive_minimum", "exclusive_maximum")
  local minimum, maximum = o.minimum, o.maximum
  local exclusive_minimum, exclusive_maximum = o.exclusive_minimum, o.exclusive_maximum
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
  return Schema("optional", { item = inner, validator = inner.validator, coercer = inner.coercer })
end

--- Accepts JSON null (`hecate.json.null`) in addition to the values of `inner`. Lua `nil` is absence, never null.
---@param inner hecate.schema.Schema
---@return hecate.schema.Schema
function M.nullable(inner)
  require_schema("nullable", inner)
  local validate_inner = inner.validator
  -- A text is never coerced to null: the textual forms of a missing value are not agreed (OQ-86).
  return Schema("nullable", { item = inner, coercer = inner.coercer, validator = function(value, path, out)
    if value == null then return end
    return validate_inner(value, path, out)
  end })
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
  return Schema("array", { options = o, item = item, coercer = coercer, validator = function(value, path, out)
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
    optional[i] = property.kind == "optional"
  end
  local declared = {}
  for i = 1, count do declared[names[i]] = true end
  local coercers = {}
  for i = 1, count do coercers[i] = copy[names[i]].coercer end
  local coercer = function(value, path, out)
    if type(value) ~= "table" or value == null then return value end
    local result = {}
    for key, member in next, value do result[key] = member end
    for i = 1, count do
      local member = value[names[i]]
      if member ~= nil then result[names[i]] = coercers[i](member, path .. tokens[i], out) end
    end
    return result
  end
  return Schema("object", { options = o, properties = copy, coercer = coercer, validator = function(value, path, out)
    if type(value) ~= "table" or value == null then return type_violation(path, "object", out) end
    for i = 1, count do
      local member = value[names[i]]
      if member == nil then
        if not optional[i] then
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
  return Schema("union", { members = copy, coercer = coercer, validator = function(value, path, out)
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

local DIALECT = "https://json-schema.org/draft/2020-12/schema"

--- Emits the JSON Schema 2020-12 subschema of `s` (no `$schema`). Every construct has an exact emission, or the
--- emission is refused (schemas-and-contracts.md, "JSON Schema").
---@param s hecate.schema.Schema
---@return table
local function emit(s)
  local kind = s.kind
  local o = s.options --[[@as table]]
  if kind == "string" then
    if o.pattern ~= nil then
      -- A Lua pattern has no exact ECMA-262 translation (OQ-85, point 1); a wrong `pattern` would break
      -- "emitted JSON Schema validates exactly what Lua validation accepts".
      refuse("to_json_schema: a Lua pattern cannot be emitted as a JSON Schema pattern (OQ-85)", { option = "pattern" })
    end
    return { type = "string", minLength = o.min_length, maxLength = o.max_length }
  elseif kind == "integer" or kind == "number" then
    return { type = kind, minimum = o.minimum, maximum = o.maximum,
      exclusiveMinimum = o.exclusive_minimum, exclusiveMaximum = o.exclusive_maximum }
  elseif kind == "boolean" then
    return { type = "boolean" }
  elseif kind == "literal" then
    return { const = o.value }
  elseif kind == "enumeration" then
    return { enum = s:members() }
  elseif kind == "array" then
    return { type = "array", items = emit(s.item), minItems = o.min_items, maxItems = o.max_items,
      uniqueItems = o.unique_items }
  elseif kind == "optional" then
    return emit(s.item) -- absence is expressed by the parent's `required`
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
      if property.kind ~= "optional" then required[#required + 1] = name end
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
--- raises `ArgumentError`, because a Lua pattern has no exact ECMA-262 translation.
---@return table document  the root carries `$schema`
function Schema:to_json_schema()
  local document = emit(self)
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
