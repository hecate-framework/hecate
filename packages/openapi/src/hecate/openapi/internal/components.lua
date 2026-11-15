-- The component registry: collects the schemas that `hecate.schema` emits, moves their `$defs` into
-- `components.schemas` and rewrites the references (OQ-89: OpenAPI rewrites `#/$defs/` to `#/components/schemas/`).
global <const> require, type, pairs, ipairs, error, string, math, table, tostring

local core = require("hecate.core")

local DEFS_PREFIX <const> = "#/$defs/"
local COMPONENTS_PREFIX <const> = "#/components/schemas/"

-- The keywords of a JSON Schema whose value is a schema, a map of schemas or a list of schemas (JSON Schema 2020-12,
-- sections 10 and 8.2.4). Only these are walked: the value of `const`, `enum` or `default` is data, not a schema, and
-- must not be rewritten.
local SCHEMA_KEYWORDS <const> = { items = true, additionalProperties = true, ["not"] = true, contains = true,
  propertyNames = true, ["if"] = true, ["then"] = true, ["else"] = true }
local MAP_KEYWORDS <const> = { properties = true, ["$defs"] = true, patternProperties = true, dependentSchemas = true }
local LIST_KEYWORDS <const> = { oneOf = true, anyOf = true, allOf = true, prefixItems = true }

local rewrite

--- Rewrites, in place, the `$ref` of a schema and of its subschemas.
---@param node any
function rewrite(node)
  if type(node) ~= "table" then return end
  local ref = node["$ref"]
  if type(ref) == "string" and string.sub(ref, 1, #DEFS_PREFIX) == DEFS_PREFIX then
    node["$ref"] = COMPONENTS_PREFIX .. string.sub(ref, #DEFS_PREFIX + 1)
  end
  for keyword, value in pairs(node) do
    if SCHEMA_KEYWORDS[keyword] then
      rewrite(value)
    elseif MAP_KEYWORDS[keyword] and type(value) == "table" then
      for _, subschema in pairs(value) do rewrite(subschema) end
    elseif LIST_KEYWORDS[keyword] and type(value) == "table" then
      for _, subschema in ipairs(value) do rewrite(subschema) end
    end
  end
end

--- Structural equality of two JSON values (tables compared member by member).
---@param a any
---@param b any
---@return boolean
local function equal(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  for key, value in pairs(a) do
    if not equal(value, b[key]) then return false end
  end
  for key in pairs(b) do
    if a[key] == nil then return false end
  end
  return true
end

--- The schemas of one document under assembly.
---@class hecate.openapi.Components
---@field schemas table<string, table>  component name to JSON Schema
---@field private origins table<string, string>
---@overload fun(): hecate.openapi.Components
local Components = core.class("Components")

--- Creates an empty registry.
function Components:init()
  self.schemas = {}
  self.origins = {}
end

--- Registers a component under `name`. A second registration with a different body raises `ArgumentError`
--- (two schemas sharing one name would silently document one of them as the other); an equal body is shared.
---@param name string
---@param body table  already rewritten
---@param source string  where the body comes from, for the message
function Components:define(name, body, source)
  local previous = self.schemas[name]
  if previous == nil then
    self.schemas[name] = body
    self.origins[name] = source
  elseif not equal(previous, body) then
    error(core.ArgumentError(("hecate.openapi.build: two different schemas are named %s (%s and %s); give one of them another name")
      :format(name, self.origins[name], source), { context = { name = name } }), 0)
  end
end

--- Converts a schema of `hecate.schema` to an OpenAPI Schema Object (a JSON Schema 2020-12 subschema, OpenAPI 3.1
--- section 4.8.24): its `$defs` become components, its references point to `#/components/schemas/`, and the
--- `$schema` keyword is dropped (the dialect of an OpenAPI 3.1 document is 2020-12 by default).
---@param s hecate.schema.Schema
---@param source string  where the schema is used, for the message of a collision
---@return table
function Components:convert(s, source)
  local emitted = s:to_json_schema()
  local defs = emitted["$defs"]
  emitted["$defs"] = nil
  emitted["$schema"] = nil
  rewrite(emitted)
  if defs ~= nil then
    local names = {}
    for name in pairs(defs) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
      rewrite(defs[name])
      self:define(name, defs[name], source)
    end
  end
  return emitted
end

core.finalise(Components)

return Components
