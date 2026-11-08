-- hecate.schema: refinement types, composition and validation with JSON Pointer error paths
-- (docs/architecture/schemas-and-contracts.md). 
global <const> require

local schema = require("hecate.schema.schema")
local violation = require("hecate.schema.violation")

--- Declarations of types and their validation; every schema is an immutable value.
---@class hecate.schema
---@field Schema hecate.schema.Schema  the class of every schema
---@field Violation hecate.schema.Violation  one reason why a value does not conform
---@field Representable table  interface of a class whose instances have a representation: it requires a class-level `schema()`; `of` refuses a class without it
---@field string fun(options?: hecate.schema.StringOptions): hecate.schema.Schema
---@field integer fun(options?: hecate.schema.IntegerOptions): hecate.schema.Schema
---@field number fun(options?: hecate.schema.NumberOptions): hecate.schema.Schema
---@field boolean fun(): hecate.schema.Schema
---@field literal fun(value: hecate.schema.Constant): hecate.schema.Schema
---@field enumeration fun(values: hecate.schema.Constant[]|table): hecate.schema.Schema  a list of constants or a `core.enumeration`
---@field object fun(properties: table<string, hecate.schema.Schema>, options?: hecate.schema.ObjectOptions): hecate.schema.Schema
---@field array fun(item: hecate.schema.Schema, options?: hecate.schema.ArrayOptions): hecate.schema.Schema
---@field map fun(value: hecate.schema.Schema, options?: hecate.schema.MapOptions): hecate.schema.Schema
---@field optional fun(inner: hecate.schema.Schema): hecate.schema.Schema
---@field nullable fun(inner: hecate.schema.Schema): hecate.schema.Schema
---@field union fun(alternatives: hecate.schema.Schema[]): hecate.schema.Schema
---@field default fun(inner: hecate.schema.Schema, value: any): hecate.schema.Schema
---@field tagged_union fun(tag: string, variants: table<string, hecate.schema.Schema>): hecate.schema.Schema
---@field any fun(): hecate.schema.Schema
---@field null fun(): hecate.schema.Schema
---@field named fun(name: string, inner: hecate.schema.Schema): hecate.schema.Schema
---@field of fun(target: table|string): hecate.schema.Schema
---@field sent fun(instance: table, name: string): boolean
---@field is_schema fun(value: any): boolean
---@field private _steps fun(): integer  internal: the steps spent by the last call (read by the step-count tests, not public API)
---@field private _limits { max_steps: integer, max_violations: integer, max_pattern_bytes: integer }  internal: the bounds of a call (read by tests, not public API)
local M = {
  ---@diagnostic disable-next-line: assign-type-mismatch  -- class constructor exported as its class
  Schema = schema.Schema,
  ---@diagnostic disable-next-line: assign-type-mismatch  -- class constructor exported as its class
  Violation = violation.Violation,
  string = schema.string,
  integer = schema.integer,
  number = schema.number,
  boolean = schema.boolean,
  literal = schema.literal,
  enumeration = schema.enumeration,
  object = schema.object,
  array = schema.array,
  map = schema.map,
  optional = schema.optional,
  nullable = schema.nullable,
  union = schema.union,
  default = schema.default,
  tagged_union = schema.tagged_union,
  any = schema.any,
  null = schema.null,
  named = schema.named,
  Representable = schema.Representable,
  of = schema.of,
  sent = schema.sent,
  is_schema = schema.is_schema,
  _limits = schema.limits,
  _steps = schema.steps,
}

return M
