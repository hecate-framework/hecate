-- The emission of a schema as a JSON Schema 2020-12 document (`Schema:to_json_schema`).
-- Internal to `hecate.schema`: not public API. `schema.lua` requires it, for the method it adds to `Schema`.
---@diagnostic disable: invisible -- the `package` fields of `Schema` are shared by the internal modules of this package
global <const> require, error, pcall, ipairs, pairs, table, next, tostring

local core = require("hecate.core")
local model = require("hecate.schema.internal.model")
local json_values = require("hecate.schema.internal.json_values")
local pattern_module = require("hecate.schema.pattern")

---@class hecate.schema.Schema
local Schema = model.Schema
local json_equal = json_values.json_equal
local pattern_to_ecma = pattern_module.to_ecma

local DIALECT = "https://json-schema.org/draft/2020-12/schema"

--- Definitions collected by the emission in progress (`named` schemas), by name.
local defs
--- Where each name of `defs` comes from in the emission in progress: "class" or "named".
local origins
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
    local origin = o.from_class and "class" or "named"
    defs[name] = PENDING
    local ok, body = pcall(emit, s.item)
    defs[name] = previous
    if not ok then error(body, 0) end
    if previous == nil then
      defs[name] = body
      origins[name] = origin
    elseif not json_equal(previous, body) then
      local detail = origins[name] == origin and ("both come from " .. (origin == "class" and "classes" or "named"))
        or "one comes from a class (schema.of) and one from named"
      error(core.ArgumentError("to_json_schema: two different schemas are named " .. name .. ": " .. detail
        .. "; give one of them another name", { context = { name = name } }))
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
    if o.enumeration ~= nil then return { type = "string", enum = s:members() } end -- names of a core enumeration
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
    emitted.default = s.copy_default()
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
  defs, origins = {}, {}
  local ok, document = pcall(emit, self)
  local collected = defs
  defs, origins = nil, nil
  if not ok then error(document, 0) end
  if next(collected) ~= nil then document["$defs"] = collected end
  document["$schema"] = DIALECT
  return document
end
