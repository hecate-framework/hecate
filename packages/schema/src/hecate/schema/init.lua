-- hecate.schema: refinement types, composition and validation with JSON Pointer error paths
-- (docs/architecture/schemas-and-contracts.md). 
global <const> require

local schema = require("hecate.schema.schema")
local violation = require("hecate.schema.violation")

--- Declarations of types and their validation; every schema is an immutable value.
---@class hecate.schema
---@field Schema hecate.schema.Schema  the class of every schema
---@field Violation hecate.schema.Violation  one reason why a value does not conform
---@field string fun(options?: { min_length?: integer, max_length?: integer, pattern?: string }): hecate.schema.Schema
---@field integer fun(options?: { minimum?: number, maximum?: number, exclusive_minimum?: number, exclusive_maximum?: number, multiple_of?: number }): hecate.schema.Schema
---@field number fun(options?: { minimum?: number, maximum?: number, exclusive_minimum?: number, exclusive_maximum?: number, multiple_of?: number }): hecate.schema.Schema
---@field boolean fun(): hecate.schema.Schema
---@field literal fun(value: string|number|boolean|hecate.json.Null): hecate.schema.Schema
---@field enumeration fun(values: (string|number|boolean|hecate.json.Null)[]): hecate.schema.Schema
---@field object fun(properties: table<string, hecate.schema.Schema>, options?: { additional_properties?: boolean }): hecate.schema.Schema
---@field array fun(item: hecate.schema.Schema, options?: { min_items?: integer, max_items?: integer, delimiter?: string, unique_items?: boolean }): hecate.schema.Schema
---@field map fun(value_schema: hecate.schema.Schema, options?: { min_properties?: integer, max_properties?: integer }): hecate.schema.Schema
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
  of = schema.of,
  sent = schema.sent,
  is_schema = schema.is_schema,
}

return M
