-- hecate.schema: refinement types, composition and validation with JSON Pointer error paths
-- (docs/architecture/schemas-and-contracts.md). Coercion, JSON Schema emission and class-bound instances come later.
global <const> require

local schema = require("hecate.schema.schema")
local violation = require("hecate.schema.violation")

--- Declarations of types and their validation; every schema is an immutable value.
---@class hecate.schema
---@field Schema hecate.schema.Schema  the class of every schema
---@field Violation hecate.schema.Violation  one reason why a value does not conform
---@field string fun(options?: { min_length?: integer, max_length?: integer, pattern?: string }): hecate.schema.Schema
---@field integer fun(options?: { minimum?: number, maximum?: number, exclusive_minimum?: number, exclusive_maximum?: number }): hecate.schema.Schema
---@field number fun(options?: { minimum?: number, maximum?: number, exclusive_minimum?: number, exclusive_maximum?: number }): hecate.schema.Schema
---@field boolean fun(): hecate.schema.Schema
---@field literal fun(value: string|number|boolean|hecate.json.Null): hecate.schema.Schema
---@field enumeration fun(values: (string|number|boolean|hecate.json.Null)[]): hecate.schema.Schema
---@field object fun(properties: table<string, hecate.schema.Schema>, options?: { additional_properties?: boolean }): hecate.schema.Schema
---@field array fun(item: hecate.schema.Schema, options?: { min_items?: integer, max_items?: integer, delimiter?: string, unique_items?: boolean }): hecate.schema.Schema
---@field optional fun(inner: hecate.schema.Schema): hecate.schema.Schema
---@field nullable fun(inner: hecate.schema.Schema): hecate.schema.Schema
---@field union fun(alternatives: hecate.schema.Schema[]): hecate.schema.Schema
---@field is_schema fun(value: any): boolean
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
  optional = schema.optional,
  nullable = schema.nullable,
  union = schema.union,
  is_schema = schema.is_schema,
}

return M
