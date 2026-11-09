-- The discriminated sum type of hecate.schema (`tagged_union`).
-- Internal to `hecate.schema`: not public API. `schema.lua` requires it.
---@diagnostic disable: invisible -- the `package` fields of `Schema` are shared by the internal modules of this package
global <const> require, type, pairs, ipairs, next, table

local json = require("hecate.json")
local model = require("hecate.schema.internal.model")
local violation_module = require("hecate.schema.violation")
local validation = require("hecate.schema.internal.validation")
local base_types = require("hecate.schema.internal.base_types")

local Schema = model.Schema
local refuse, require_schema = model.refuse, model.require_schema
local escape_token = violation_module.escape_token
local where, type_violation, path_to = validation.where, validation.type_violation, validation.path_to
local stop_representation, represented = validation.stop_representation, validation.represented
local attributes_of = validation.attributes_of
local null = json.null

---@class hecate.schema.internal.tagged_union
local M = {}

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
  local names, derived, validators, coercers, representers = {}, {}, {}, {}, {}
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
    properties[tag] = base_types.literal(name)
    local object = validation.object(properties, { additional_properties = (variant.options --[[@as table]]).additional_properties })
    derived[name], validators[name], coercers[name] = object, object.validator, object.coercer
    representers[name] = object.representer
  end
  local token = "/" .. escape_token(tag)
  return Schema("tagged_union", { options = { tag = tag }, properties = derived, members = names,
    builder = function(value) return derived[value[tag]].builder(value) end,
    representer = represented(function(value, at)
      local name = type(value) == "table" and value ~= null and attributes_of(value)[tag] or nil
      local represent = type(name) == "string" and representers[name] or nil
      if represent == nil then
        stop_representation(path_to(at) .. token, "tagged_union", "the value is not the name of a variant",
          { tag = tag, values = { table.unpack(names) } })
      end
      return represent--[[@as hecate.schema.Representer]](value, at)
    end),
    coercer = function(value, at, out)
      if type(value) ~= "table" or value == null then return value end
      local name = value[tag]
      local coerce = type(name) == "string" and coercers[name]
      if not coerce then return value end -- the validator reports the tag
      return coerce(value, at, out)
    end,
    validator = function(value, at, out)
      if type(value) ~= "table" or value == null then return type_violation(at, "object", out, value) end
      local name = value[tag]
      if name == nil then
        out[#out + 1] = { where(at) .. token, "required", "the property is required", { property = tag } }
        return
      end
      local validate = type(name) == "string" and validators[name]
      if not validate then
        out[#out + 1] = { where(at) .. token, "tagged_union", "the value is not the name of a variant",
          { tag = tag, values = { table.unpack(names) } } }
        return
      end
      return validate(value, at, out)
    end })
end

return M
