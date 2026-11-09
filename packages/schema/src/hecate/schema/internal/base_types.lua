-- The base types and wrappers of hecate.schema: string, integer, number, boolean, literal, enumeration, null, any,
-- optional, nullable and named. None of them reads the state of a call: they use only the helpers of `validation`.
-- Internal to `hecate.schema`: not public API. `schema.lua` and the other `internal/` modules require it.
---@diagnostic disable: invisible -- the `package` fields of `Schema` are shared by the internal modules of this package
global <const> require, type, pairs, ipairs, table, string, math, utf8, pcall, tostring, tonumber, error

local core = require("hecate.core")
local json = require("hecate.json")
local pattern_module = require("hecate.schema.pattern")
local model = require("hecate.schema.internal.model")
local formats = require("hecate.schema.internal.formats")
local validation = require("hecate.schema.internal.validation")

local pattern_to_ecma = pattern_module.to_ecma
local check_pattern = pattern_module.check
local Schema = model.Schema
local refuse, read_options, check_range = model.refuse, model.read_options, model.check_range
local require_schema = model.require_schema
local where, type_violation, path_to = validation.where, validation.type_violation, validation.path_to
local stop_representation, copy_plain, limits = validation.stop_representation, validation.copy_plain, validation.limits
local FORMATS = formats
local find = string.find
local math_type = math.type
local null = json.null

---@class hecate.schema.internal.base_types
local M = {}

--- Declares a string type.
--- `pattern` is a Lua pattern for now (OQ-85); lengths count Unicode code points (JSON Schema 2020-12 section 6.3.1).
--- A `pattern` that `to_json_schema` cannot translate (`%b`, `%f`, ...) is reported at declaration with
--- `logger:warning(message, fields)` when a `logger` (any object with that method, for example a `hecate.log` logger) is given
--- (OQ-85, point 1); the schema stays valid for Lua validation and emission refuses it.
--- A malformed `pattern` is refused here (`ArgumentError`). `pattern` and `format` are not run on a value that already has an
--- `invalid_utf8` or `max_length` violation, nor, without `max_length`, on a string longer than `limits.max_pattern_bytes`
--- (violation `reason = "too_long_for_pattern"`); a match that Lua gives up on is a `pattern` violation (`malformed_pattern`).
---@param options? hecate.schema.StringOptions
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
      local accepted = {}
      for name in pairs(FORMATS) do accepted[#accepted + 1] = name end
      table.sort(accepted)
      refuse(("string: unknown format %s; accepted formats: %s"):format(o.format, table.concat(accepted, ", ")),
        { option = "format", accepted = accepted })
    end
  end
  if pattern ~= nil then
    -- Lua reports a malformed pattern only when a match reaches the fault: check the structure (the reasons of lstrlib.c),
    -- then probe with subjects, one of which walks the characters of the pattern itself (S3).
    local reason = check_pattern(pattern)
    if reason == nil then
      for _, subject in ipairs({ "", pattern, pattern:rep(2), ("a"):rep(8) }) do
        local ok, err = pcall(find, subject, pattern)
        if not ok then reason = tostring(err):gsub("^.-:%d+: ", ""); break end
      end
    end
    if reason ~= nil then
      refuse(("string: option pattern %q is not a valid Lua pattern: %s (it is a Lua pattern, not a regular expression; OQ-85)")
        :format(pattern, reason), { option = "pattern", reason = reason })
    end
  end
  if pattern ~= nil and logger ~= nil then
    local translated, err = pcall(pattern_to_ecma, pattern)
    if not translated then
      local reason = type(err) == "table" and type(err.context) == "table" and err.context.reason or tostring(err)
      logger:warning(("schema: pattern %q cannot be emitted: %s"):format(pattern, reason),
        { pattern = pattern, reason = reason })
    end
  end
  local checks_length = min_length ~= nil or max_length ~= nil
  local format_name = o.format
  local validator = function(value, at, out)
    if type(value) ~= "string" then return type_violation(at, "string", out, value) end
    local unreadable = false -- an encoding or a length violation: pattern and format are not run on this value (S2)
    if checks_length then
      local length = utf8.len(value)
      if length == nil then
        unreadable = true
        out[#out + 1] = { where(at), "invalid_utf8", "the string is not well-formed UTF-8" }
      else
        if min_length and length < min_length then
          out[#out + 1] = { where(at), "min_length", "the string is shorter than " .. min_length, { min_length = min_length } }
        end
        if max_length and length > max_length then
          unreadable = true
          out[#out + 1] = { where(at), "max_length", "the string is longer than " .. max_length, { max_length = max_length } }
        end
      end
    end
    if unreadable or (pattern == nil and check_format == nil) then return end
    -- Without `max_length` the input is unbounded: beyond the ceiling the match is not run (anchor patterns, README).
    if max_length == nil and #value > limits.max_pattern_bytes then
      if pattern then
        out[#out + 1] = { where(at), "pattern", "the string is too long to be matched against the pattern",
          { pattern = pattern, reason = "too_long_for_pattern", max_bytes = limits.max_pattern_bytes } }
      end
      if check_format then
        out[#out + 1] = { where(at), "format", "the string is too long to be checked as a " .. format_name,
          { format = format_name, reason = "too_long_for_pattern", max_bytes = limits.max_pattern_bytes } }
      end
      return
    end
    if pattern then
      -- `pcall`: a pattern that Lua gives up on ("pattern too complex") is a violation, never a raw error (S3).
      local ok, matched = pcall(find, value, pattern)
      if not ok then
        out[#out + 1] = { where(at), "pattern", "the pattern cannot be matched", { pattern = pattern, reason = "malformed_pattern" } }
      elseif not matched then
        out[#out + 1] = { where(at), "pattern", "the string does not match the pattern", { pattern = pattern } }
      end
    end
    if check_format and not check_format(value) then
      out[#out + 1] = { where(at), "format", "the string is not a valid " .. format_name, { format = format_name } }
    end
  end
  return Schema("string", { options = o, validator = validator })
end

local function coercion_violation(at, expected, out)
  out[#out + 1] = { where(at), "coercion", "the text is not " .. expected, { expected = expected } }
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
  return function(value, at, out)
    if type(value) ~= "string" then return value end
    local converted = convert(value)
    if converted == nil then
      coercion_violation(at, expected, out)
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
  if o.multiple_of ~= nil and math_type(o.multiple_of) ~= "integer" and o.multiple_of ~= math.floor(o.multiple_of) then
    -- Binary floats cannot express decimal steps (0.1 is not exact), and JSON Schema has no decimal-places keyword (OQ-87).
    refuse(kind .. ": option multiple_of must be a whole number; use integers in minor units, or a string with a pattern"
      .. " for a fixed number of decimals", { option = "multiple_of" })
  end
  check_range(kind, o, "minimum", "maximum")
  check_range(kind, o, "exclusive_minimum", "exclusive_maximum")
  local minimum, maximum = o.minimum, o.maximum
  local exclusive_minimum, exclusive_maximum = o.exclusive_minimum, o.exclusive_maximum
  local multiple_of = o.multiple_of
  local validator = function(value, at, out)
    if not accepts(value) then return type_violation(at, expected, out, value) end
    if minimum and value < minimum then
      out[#out + 1] = { where(at), "minimum", "the value is less than " .. minimum, { minimum = minimum } }
    end
    if maximum and value > maximum then
      out[#out + 1] = { where(at), "maximum", "the value is greater than " .. maximum, { maximum = maximum } }
    end
    if exclusive_minimum and value <= exclusive_minimum then
      out[#out + 1] = { where(at), "exclusive_minimum", "the value is not greater than " .. exclusive_minimum,
        { exclusive_minimum = exclusive_minimum } }
    end
    if exclusive_maximum and value >= exclusive_maximum then
      out[#out + 1] = { where(at), "exclusive_maximum", "the value is not less than " .. exclusive_maximum,
        { exclusive_maximum = exclusive_maximum } }
    end
    -- Exact remainder (math.fmod is exact for floats): 0.3 is not a multiple of 0.1, as in IEEE 754 arithmetic.
    if multiple_of and math.fmod(value, multiple_of) ~= 0 then
      out[#out + 1] = { where(at), "multiple_of", "the value is not a multiple of " .. multiple_of, { multiple_of = multiple_of } }
    end
  end
  local coercer = scalar_coercer(kind == "integer" and text_to_integer or text_to_number, "a" .. (kind == "integer" and "n integer" or " number"))
  return Schema(kind, { options = o, validator = validator, coercer = coercer })
end

--- Declares an integer type: only Lua integers conform, `1.0` does not (OQ-85).
---@param options? hecate.schema.IntegerOptions
---@return hecate.schema.Schema
function M.integer(options)
  return numeric("integer", function(v) return math_type(v) == "integer" end, "integer", options)
end

--- Declares a number type: Lua integers and finite floats conform, NaN and infinities do not (JSON has none).
---@param options? hecate.schema.NumberOptions
---@return hecate.schema.Schema
function M.number(options)
  return numeric("number", function(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end,
    "number", options)
end

--- Declares a boolean type.
---@return hecate.schema.Schema
function M.boolean()
  return Schema("boolean", { validator = function(value, at, out)
    if type(value) ~= "boolean" then return type_violation(at, "boolean", out, value) end
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
  return function(value, at, out)
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
---@param value hecate.schema.Constant
---@return hecate.schema.Schema
function M.literal(value)
  require_constant("literal", value)
  return Schema("literal", { options = { value = value }, coercer = constants_coercer({ value }),
    validator = function(v, at, out)
      if not same_constant(v, value) then
        out[#out + 1] = { where(at), "literal", "the value is not the expected constant", { value = value } }
      end
    end })
end

--- Declares a type whose values are the members of a list of constants (JSON Schema `enum`), or the values of a
--- `core.enumeration`. For a `core.enumeration` the JSON representation of a value is its name (a member object is not
--- JSON, and a name round-trips through `json.encode` and `json.decode`): the schema accepts exactly the names of the
--- enumeration, in JSON Schema `{ type = "string", enum = names }`, and `build` replaces a name by the member. The names
--- are read once, here; an enumeration is closed, so they cannot change afterwards.
---@param values hecate.schema.Constant[]|table  a list of constants, or a `core.enumeration` (its names are the constants)
---@return hecate.schema.Schema
function M.enumeration(values)
  local source = nil
  if core.is_enumeration(values) then
    source = values
    values = source:names() -- a fresh list, in declaration order
  end
  if type(values) ~= "table" or #values == 0 then refuse("enumeration: expects a non-empty list of constants") end
  local copy = {}
  for i, value in ipairs(values) do
    require_constant("enumeration", value)
    copy[i] = value
  end
  local count = #copy
  local builder = nil
  local options = nil
  local representer = nil
  if source ~= nil then
    options = { enumeration = source.__name }
    builder = function(value) return source:find(value) end
    -- A member becomes its name; a name (a hand-made value) stays as it is; anything else has no JSON form.
    representer = function(value, at)
      if type(value) == "string" then return value end
      local name = type(value) == "table" and value.name or nil
      if type(name) == "string" and source:find(name) == value then return name end
      stop_representation(path_to(at), "enum", "the value is not a member of the enumeration " .. source.__name)
    end
  end
  return Schema("enumeration", { options = options, members = copy, coercer = constants_coercer(copy), builder = builder,
    representer = representer,
    validator = function(v, at, out)
      for i = 1, count do
        if same_constant(v, copy[i]) then return end
      end
      out[#out + 1] = { where(at), "enum", "the value is not one of the allowed values", { values = { table.unpack(copy) } } }
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
  return Schema("optional", { item = inner, validator = inner.validator, coercer = inner.coercer, builder = inner.builder,
    representer = inner.representer, prefilter = inner.prefilter })
end

--- Accepts JSON null (`hecate.json.null`) in addition to the values of `inner`. Lua `nil` is absence, never null.
---@param inner hecate.schema.Schema
---@return hecate.schema.Schema
function M.nullable(inner)
  require_schema("nullable", inner)
  local validate_inner = inner.validator
  -- A text is never coerced to null: the textual forms of a missing value are not agreed (OQ-86).
  local build_inner = inner.builder
  local represent_inner = inner.representer
  return Schema("nullable", { item = inner, coercer = inner.coercer,
    representer = function(value, at) if value == null then return value end return represent_inner(value, at) end,
    builder = function(value) if value == null then return value end return build_inner(value) end,
    validator = function(value, at, out)
    if value == null then return end
    return validate_inner(value, at, out)
  end })
end

--- Accepts every JSON value. Emitted as the empty schema `{}`.
---@return hecate.schema.Schema
function M.any()
  return Schema("any", { validator = function() end, representer = copy_plain })
end

--- Accepts JSON null only (`hecate.json.null`); Lua `nil` is absence.
---@return hecate.schema.Schema
function M.null()
  return Schema("null", { validator = function(value, at, out)
    if value ~= null then return type_violation(at, "null", out, value) end
  end })
end

local make_named

--- Gives a schema a name. The name is the key of the definition in the emission (`$defs`, referenced by `$ref`),
--- and becomes an OpenAPI component. A name is made of letters, digits, `_`, `.` and `-`; two different schemas
--- with the same name in one emission raise `ArgumentError` (OQ-89). Validation and coercion are those of `inner`.
---@param name string
---@param inner hecate.schema.Schema
---@return hecate.schema.Schema
function M.named(name, inner)
  return make_named(name, inner, false)
end

--- The shared constructor of `named` and of the class-bound schemas; `from_class` records where the name comes from.
---@param name string
---@param inner hecate.schema.Schema
---@param from_class boolean
---@return hecate.schema.Schema
function make_named(name, inner, from_class)
  if type(name) ~= "string" or not name:find("^[%w_.%-]+$") then
    refuse("named: the name is a non-empty string of letters, digits, '_', '.' and '-'")
  end
  require_schema("named", inner)
  if inner.kind == "named" then refuse("named: the schema already has the name " .. (inner.options --[[@as table]]).name) end
  return Schema("named", { options = { name = name, from_class = from_class or nil }, item = inner, validator = inner.validator, coercer = inner.coercer,
    prefilter = inner.prefilter,
    relaxed_validator = inner.relaxed_validator, builder = inner.builder, representer = inner.representer })
end

M.make_named = make_named
return M
