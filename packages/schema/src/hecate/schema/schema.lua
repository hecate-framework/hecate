-- The type model and the validation core of hecate.schema (schemas-and-contracts.md, "Types" and "Validation").
--
-- A schema is an immutable value (a core value class). Its constructor compiles a validator closure once, at
-- declaration time; validating never walks the schema description (package invariants).
--
-- The work is split into internal modules (not public API): `internal/model` (the `Schema` class, the option checks),
-- `internal/validation` (the state of a call, the compound constructors and the methods that run a schema),
-- `internal/base_types` (the base types and wrappers), `internal/tagged_union`, `internal/classes` (`of`, `sent`),
-- `internal/emission` (JSON Schema), `internal/formats` and `internal/json_values`. This file keeps the public
-- surface: the exports, and the types of the options.
global <const> require

local core = require("hecate.core")
local model = require("hecate.schema.internal.model")
local validation = require("hecate.schema.internal.validation")
local base_types = require("hecate.schema.internal.base_types")
local tagged_union = require("hecate.schema.internal.tagged_union")
local classes = require("hecate.schema.internal.classes")
require("hecate.schema.internal.emission") -- adds `Schema:to_json_schema`

local Schema = model.Schema

---@class hecate.schema
local M = {}
M.limits = validation.limits
M.steps = validation.steps

--- An object that receives the declaration warnings of `string` (for example a `hecate.log` logger).
---@class hecate.schema.WarningLogger
---@field warning fun(self: hecate.schema.WarningLogger, message: string, fields?: table)

--- A `format` of `string`: a conservative subset of JSON Schema 2020-12 section 7.3.
---@alias hecate.schema.Format "uuid"|"date"|"date-time"|"email"|"ipv4"|"uri"

--- Options of `schema.string`.
---@class hecate.schema.StringOptions
---@field min_length? integer  fewest code points
---@field max_length? integer  most code points
---@field pattern? string  a Lua pattern (translated to ECMA-262 on emission)
---@field format? hecate.schema.Format  a well-known string format
---@field logger? hecate.schema.WarningLogger  receives a warning when `pattern` cannot be emitted (OQ-86)

--- Options of `schema.integer`.
---@class hecate.schema.IntegerOptions
---@field minimum? number
---@field maximum? number
---@field exclusive_minimum? number
---@field exclusive_maximum? number
---@field multiple_of? integer  a whole-number divisor greater than zero (OQ-87)

--- Options of `schema.number`.
---@class hecate.schema.NumberOptions
---@field minimum? number
---@field maximum? number
---@field exclusive_minimum? number
---@field exclusive_maximum? number
---@field multiple_of? integer  a whole-number divisor greater than zero (OQ-87)

--- Options of `schema.array`.
---@class hecate.schema.ArrayOptions
---@field min_items? integer
---@field max_items? integer
---@field delimiter? string  how `coerce` splits a text (default ","; not empty)
---@field unique_items? boolean  no two items are equal

--- Options of `schema.map`.
---@class hecate.schema.MapOptions
---@field min_properties? integer
---@field max_properties? integer

--- Options of `schema.object`.
---@class hecate.schema.ObjectOptions
---@field additional_properties? boolean  accept undeclared properties (default false: they are rejected)

--- Options of `Schema:build`.
---@class hecate.schema.BuildOptions
---@field method? "POST"|"PUT"|"PATCH"  the HTTP method the content arrived with (default "POST")
---@field coerce? boolean  read the content from text (path, query, header fields) first

--- A constant of a `literal` or an `enumeration`.
---@alias hecate.schema.Constant string|number|boolean|hecate.json.Null

M.string = base_types.string
M.integer = base_types.integer
M.number = base_types.number
M.boolean = base_types.boolean
M.literal = base_types.literal
M.enumeration = base_types.enumeration
M.optional = base_types.optional
M.nullable = base_types.nullable
M.any = base_types.any
M.null = base_types.null
M.named = base_types.named
M.array = validation.array
M.object = validation.object
M.map = validation.map
M.union = validation.union
M.default = validation.default
M.tagged_union = tagged_union.tagged_union
M.Representable = classes.Representable
M.of = classes.of
M.sent = classes.sent

core.finalise(Schema)

---@diagnostic disable-next-line: assign-type-mismatch
M.Schema = Schema
M.is_schema = model.is_schema
return M
