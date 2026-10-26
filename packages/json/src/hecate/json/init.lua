-- hecate.json: the JSON codec (RFC 8259) of Hecate, with integer/float fidelity, explicit null and
-- array markers and precise error positions (ADR 0020, packages/json/README.md).
--
-- The codec runs on two native modules, required at run time (yyjson decoder, serde_json encoder, ADR 0020 and 0021;
-- OQ-53: no pure-Lua fallback); they sit behind `hecate.json.internal.backend`.
global <const> require, type, getmetatable, setmetatable, table, rawequal, error, math, string, pairs, tostring

local core = require("hecate.core")
local errors = require("hecate.json.errors")
local markers = require("hecate.json.internal.markers")
local backend = require("hecate.json.internal.backend")
local position = require("hecate.json.internal.position")

local null, array_metatable, object_metatable = markers.null, markers.array_metatable, markers.object_metatable
local ArgumentError = core.ArgumentError
local tag = markers.tag

--- Default nesting limit: arrays and objects nested deeper than this are rejected (OQ-48).
local DEFAULT_MAX_DEPTH = 1000
--- The highest `max_depth` accepted, by `decode` and `encode` alike: deeper recursion could exhaust the C or the Lua
--- stack (OQ-48, OQ-54). A deeper text or value is an error (`depth_limit`), not a crash.
local MAX_DEPTH_CEILING = 1000
--- Default size limit in bytes of the text read by `decode` and of the text written by `encode` (OQ-48).
local DEFAULT_MAX_SIZE = 16 * 1024 * 1024
--- Indentation used by `pretty = true`.
local DEFAULT_INDENT = "  "

--- The JSON codec: `encode` and `decode`, the `null` value, the `array` and `object` markers and the errors.
---@class hecate.json
---@field null hecate.json.Null  the value of JSON `null`; decoded nulls are this exact value
---@field JsonError hecate.json.JsonError
---@field DecodeError hecate.json.DecodeError
---@field EncodeError hecate.json.EncodeError
local json = {
  null = null,
  JsonError = errors.JsonError,
  DecodeError = errors.DecodeError,
  EncodeError = errors.EncodeError,
}

--- Options of `json.decode`.
---@class hecate.json.DecodeOptions
---@field max_depth? integer  deepest nesting of arrays and objects accepted, 1 to 1000 (default 1000, as for `encode`)
---@field max_size? integer  longest text accepted, in bytes (default 16 MiB)

--- Options of `json.encode`.
---@class hecate.json.EncodeOptions
---@field pretty? boolean  one member or element per line, indented (default `false`: compact text)
---@field indent? integer|string  indentation of a pretty text: a number of spaces or a string of spaces and tabs (implies `pretty`; default 2 spaces)
---@field canonical? boolean|"rfc8785"  `true`: write the members of every object in RFC 8785 order, by UTF-16 code units of their names (numbers keep the codec's own format); `"rfc8785"`: the full JSON Canonicalization Scheme for signing (compact text, every number an IEEE double in the ECMAScript format, an integer beyond +-2^53 raises); default `false`
---@field max_depth? integer  deepest nesting accepted, 1 to 1000 (default 1000, as for `decode`); also stops cycles
---@field max_size? integer  longest text produced, in bytes (default 16 MiB)

local DECODE_OPTIONS = { max_depth = true, max_size = true }
local ENCODE_OPTIONS = { pretty = true, indent = true, canonical = true, max_depth = true, max_size = true }

local function describe(value)
  if type(value) == "string" then return ("%q"):format(value) end
  return type(value) == "table" and "a table" or tostring(value)
end

---@param name string  public function the options belong to
---@param options any
---@param allowed table<string, true>
local function check_options(name, options, allowed)
  if options == nil then return {} end
  if type(options) ~= "table" then
    error(ArgumentError(("json.%s: expects an options table, got %s"):format(name, describe(options))), 3)
  end
  for key in pairs(options) do
    if not allowed[key] then
      error(ArgumentError(("json.%s: unknown option %s"):format(name, describe(key))), 3)
    end
  end
  return options
end

---@param name string
---@param options table
---@param key string
---@param default integer
---@param ceiling integer?
---@return integer
local function integer_option(name, options, key, default, ceiling)
  local value = options[key]
  if value == nil then return default end
  if math.type(value) ~= "integer" or value < 1 or (ceiling and value > ceiling) then
    error(ArgumentError(("json.%s: invalid %s %s: expected an integer in [1, %d]"):format(
      name, key, describe(value), ceiling or math.maxinteger)), 3)
  end
  return value
end

---@param options table
---@return string? unit  the text of one indentation level, `nil` for compact output
local function indent_unit(options)
  local pretty, indent = options.pretty, options.indent
  if pretty ~= nil and type(pretty) ~= "boolean" then
    error(ArgumentError(("json.encode: invalid pretty %s: expected a boolean"):format(describe(pretty))), 3)
  end
  if indent == nil then return pretty and DEFAULT_INDENT or nil end
  if pretty == false then
    error(ArgumentError("json.encode: indent given with pretty = false: drop one of the two options"), 3)
  end
  if math.type(indent) == "integer" and indent >= 0 and indent <= 16 then return string.rep(" ", indent) end
  if type(indent) == "string" and #indent <= 16 and not indent:find("[^ \t]") then return indent end
  error(ArgumentError(("json.encode: invalid indent %s: expected an integer in [0, 16] or a string of at most 16 spaces and tabs"):format(
    describe(indent))), 3)
end

--- Decodes a JSON text (RFC 8259) into a Lua value.
---
--- An integer without fraction or exponent that fits in 64 bits is a Lua integer; any other number is
--- a float (numbers beyond the 64-bit range included); `-0` is the integer 0 while `-0.0` is a float that keeps its sign (both
--- as yyjson reads them, see the README). `null` is `json.null`. Every array is a
--- table marked with `json.array` and every object a table marked with `json.object`, so that an empty
--- `[]` and an empty `{}` stay distinct and `encode` reproduces the text's value model.
---
--- Raises `hecate.json.DecodeError` (with `context.reason`, `offset`, `line` and `column`) when the text
--- is not valid: trailing content, a byte order mark, invalid UTF-8, a lone surrogate escape, a
--- duplicate member name, a number outside the float range, nesting deeper than `max_depth`, or a text
--- longer than `max_size`.
---@param text string
---@param options? hecate.json.DecodeOptions
---@return any value
function json.decode(text, options)
  if type(text) ~= "string" then
    error(ArgumentError(("json.decode: expects a string, got %s"):format(describe(text))), 2)
  end
  options = check_options("decode", options, DECODE_OPTIONS)
  local resolved = {
    max_depth = integer_option("decode", options, "max_depth", DEFAULT_MAX_DEPTH, MAX_DEPTH_CEILING),
    max_size = integer_option("decode", options, "max_size", DEFAULT_MAX_SIZE),
  }
  local value, failure = backend.get().decode(text, resolved)
  if failure ~= nil then
    if failure.offset == nil then
      -- The decoder cannot place a duplicate member name (yyjson keeps no position for it).
      error(errors.DecodeError({ message = failure.message, context = { reason = failure.reason } }), 2)
    end
    local line, column = position.locate(text, failure.offset)
    error(errors.DecodeError({
      message = ("%s at line %d, column %d (offset %d)"):format(failure.message, line, column, failure.offset),
      context = { reason = failure.reason, offset = failure.offset, line = line, column = column },
    }), 2)
  end
  return value
end

--- Encodes a Lua value as JSON text (RFC 8259) that is always valid UTF-8.
---
--- Lua integers are written as integers; floats always carry a decimal point or an exponent, so that
--- `decode` returns a float again. `json.null` is `null`. A table marked with `json.array` is an
--- array, one marked with `json.object` an object. An unmarked table is an array when its keys are
--- positive integers (a hole is written as `null`, while the table stays dense: highest index at most twice the
--- number of entries plus 16), an object when all its keys are strings, and **an object when it is empty**; any
--- other table raises. Object members are written in no defined order unless `canonical` is set.
---
--- Raises `hecate.json.EncodeError` (with `context.reason` and the JSON Pointer `context.path` of the
--- offending value) for NaN, an infinity, a function, userdata, thread or `nil` value, a string that
--- is not valid UTF-8, an ambiguous or sparse table, a nesting deeper than `max_depth` (a cycle
--- included) or an output longer than `max_size`.
---@param value any
---@param options? hecate.json.EncodeOptions
---@return string text
function json.encode(value, options)
  options = check_options("encode", options, ENCODE_OPTIONS)
  local canonical = options.canonical
  if canonical ~= nil and type(canonical) ~= "boolean" and canonical ~= "rfc8785" then
    error(ArgumentError(("json.encode: invalid canonical %s: expected a boolean or \"rfc8785\""):format(
      describe(canonical))), 2)
  end
  if canonical == "rfc8785" and (options.pretty or options.indent ~= nil) then
    error(ArgumentError("json.encode: canonical = \"rfc8785\" is compact by definition: drop pretty and indent"), 2)
  end
  local resolved = {
    max_depth = integer_option("encode", options, "max_depth", DEFAULT_MAX_DEPTH, MAX_DEPTH_CEILING),
    max_size = integer_option("encode", options, "max_size", DEFAULT_MAX_SIZE),
    indent = indent_unit(options),
    canonical = canonical == true or canonical == "rfc8785",
    rfc8785 = canonical == "rfc8785",
  }
  local text, failure = backend.get().encode(value, resolved)
  if failure ~= nil then
    local path = failure.path
    local shown = #path > 120 and (path:sub(1, 117) .. "...") or path -- the whole pointer is in `context.path`
    error(errors.EncodeError({
      message = ("%s at %s"):format(failure.message, path == "" and "the top-level value" or ("'" .. shown .. "'")),
      context = { reason = failure.reason, path = path },
    }), 2)
  end
  return text
end

---@param name string
---@param marker table
---@param t any
---@return table
local function mark(name, marker, t)
  if t == nil then return tag({}, marker) end
  if type(t) ~= "table" then
    error(ArgumentError(("json.%s: expects a table or nothing, got %s"):format(name, describe(t))), 3)
  end
  local existing = getmetatable(t)
  if existing ~= nil and existing ~= array_metatable and existing ~= object_metatable then
    error(ArgumentError(("json.%s: the table already has a metatable"):format(name)), 3)
  end
  return tag(t, marker)
end

--- Marks a table as a JSON array, so that it encodes as `[...]` even when empty. Returns the same
--- table (a new empty one when called without argument).
---@generic T : table
---@param t? T
---@return T
function json.array(t) return mark("array", array_metatable, t) end

--- Marks a table as a JSON object, so that it encodes as `{...}` even when empty. Returns the same
--- table (a new empty one when called without argument).
---@generic T : table
---@param t? T
---@return T
function json.object(t) return mark("object", object_metatable, t) end

--- Tells whether a value is a table marked with `json.array` (every decoded array is).
---@param value any
---@return boolean
function json.is_array(value) return type(value) == "table" and rawequal(getmetatable(value), array_metatable) end

--- Tells whether a value is a table marked with `json.object` (every decoded object is).
---@param value any
---@return boolean
function json.is_object(value) return type(value) == "table" and rawequal(getmetatable(value), object_metatable) end

return json
