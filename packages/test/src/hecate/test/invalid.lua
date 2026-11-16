-- Invalid values: a valid value broken in exactly one place. Every candidate is checked with `schema:validate`
-- and kept only when it yields exactly one violation, so the expectation returned is what validation reports.
global <const> require, type, error, pairs, ipairs, table, math, string, next

local core = require("hecate.core")
local json = require("hecate.json")

---@class hecate.test.invalid
local M = {}

local MAX_ATTEMPTS = 300

--- A bound above this is not used to build a value that crosses it (the value would be huge).
M.MAX_SIZE = 10000

local function copy(value)
  local out = {}
  for key, item in pairs(value) do out[key] = item end
  return out
end

-- Returns `value` with the node at `keys` replaced by `new` (or removed): the path is copied, the rest is shared.
local function replaced(value, keys, new, remove, depth)
  depth = depth or 1
  if depth > #keys then return new end
  local out = copy(value)
  local key = keys[depth]
  if depth == #keys and remove then out[key] = nil
  else out[key] = replaced(value[key], keys, new, remove, depth + 1) end
  return out
end

local function with_key(keys, key)
  local out = {}
  for i, k in ipairs(keys) do out[i] = k end
  out[#out + 1] = key
  return out
end

local function is_list(value) return type(value) == "table" and value ~= json.null and value[1] ~= nil end

local WRONG_TYPE = { string = 42, integer = "x", number = "x", boolean = "x", array = "x", object = "x", null = 0 }

-- Collects the candidates `{ keys, new, remove? }` of the node `node` holding `value`.
local function collect(node, value, keys, defs, out)
  if type(node) ~= "table" then return end
  local reference = node["$ref"]
  if reference ~= nil then
    local name = reference:match("^#/%$defs/(.+)$")
    if name and defs[name] then collect(defs[name], value, keys, defs, out) end
    return
  end
  local function add(new, remove) out[#out + 1] = { keys = keys, new = new, remove = remove } end
  local kind = node.type
  if node.anyOf ~= nil or node.oneOf ~= nil then
    local alternatives = node.anyOf or node.oneOf
    add(true) -- a value no alternative accepts
    if node.oneOf ~= nil and type(value) == "table" then
      -- a tagged union: a property that is a constant in each variant is the tag
      local first = alternatives[1] and alternatives[1].properties
      for name, property in pairs(first or {}) do
        if property.const ~= nil then
          local broken = copy(value)
          broken[name] = "\0unknown"
          add(broken)
        end
      end
    end
    -- recurse into the alternative the value was generated from, when it is an object variant
    if node.oneOf ~= nil and type(value) == "table" then
      for _, alternative in ipairs(alternatives) do collect(alternative, value, keys, defs, out) end
    end
    return
  end
  if node.const ~= nil then add("\0invalid"); return end
  if node.enum ~= nil then add("\0invalid"); return end
  if kind == nil then return end
  local wrong = WRONG_TYPE[kind]
  if wrong ~= nil then add(wrong) end
  if kind == "string" and type(value) == "string" then
    if (node.minLength or 0) > 0 then add(value:sub(1, node.minLength - 1)) end
    if node.maxLength ~= nil and node.maxLength <= M.MAX_SIZE then add(value .. string.rep("a", node.maxLength + 1 - #value)) end
    if node.format ~= nil then add("not valid") end
    if node.pattern ~= nil then
      -- a few strings no ordinary pattern accepts; validation keeps the ones that break exactly the pattern
      for _, text in ipairs({ "", "\0", "~~~~", "\0invalid", "!" }) do add(text) end
    end
  elseif (kind == "integer" or kind == "number") and type(value) == "number" then
    if node.minimum ~= nil then add(node.minimum - 1) end
    if node.maximum ~= nil then add(node.maximum + 1) end
    if node.exclusiveMinimum ~= nil then add(node.exclusiveMinimum) end
    if node.exclusiveMaximum ~= nil then add(node.exclusiveMaximum) end
    if node.multipleOf ~= nil then add(value + 1) end
    if kind == "integer" then add(value + 0.5) end
  elseif kind == "array" and type(value) == "table" and (is_list(value) or next(value) == nil) then
    local count = #value
    if (node.minItems or 0) > 0 then
      local shorter = {}
      for i = 1, node.minItems - 1 do shorter[i] = value[i] end
      add(shorter)
    end
    if node.maxItems ~= nil and node.maxItems <= M.MAX_SIZE and count > 0 then
      local longer = {}
      for i = 1, count do longer[i] = value[i] end
      for i = count + 1, node.maxItems + 1 do longer[i] = value[(i - 1) % count + 1] end
      add(longer)
    end
    for index, item in ipairs(value) do collect(node.items or {}, item, with_key(keys, index), defs, out) end
  elseif kind == "object" and type(value) == "table" then
    local required = {}
    for _, name in ipairs(node.required or {}) do required[name] = true end
    local names = {}
    for name in pairs(value) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
      if required[name] then out[#out + 1] = { keys = with_key(keys, name), remove = true } end
      local property = node.properties and node.properties[name]
      if property ~= nil then collect(property, value[name], with_key(keys, name), defs, out)
      elseif type(node.additionalProperties) == "table" then
        collect(node.additionalProperties, value[name], with_key(keys, name), defs, out)
      end
    end
    if node.additionalProperties == false then
      local extended = copy(value)
      extended["unexpected_property"] = 1
      add(extended)
    end
    if node.minProperties ~= nil and node.minProperties > 0 then add({}) end
    if node.maxProperties ~= nil and node.maxProperties <= M.MAX_SIZE then
      local more = copy(value)
      for i = 1, node.maxProperties + 1 do more["extra" .. i] = value[names[1]] or 0 end
      add(more)
    end
  end
end

-- A deterministic shuffle (Fisher-Yates) with the generator's random source.
local function shuffle(list, between, rng)
  for i = #list, 2, -1 do
    local j = between(rng, 1, i)
    list[i], list[j] = list[j], list[i]
  end
end

--- Breaks `valid` (a value valid for `schema`, generated from `document`) in exactly one place.
---
--- Raises `hecate.core.ArgumentError` when no single violation could be produced (for example the schema accepts
--- every value).
---@param schema hecate.schema.Schema
---@param document table  the emitted JSON Schema of `schema`
---@param valid any
---@param between fun(rng: table, low: integer, high: integer): integer
---@param rng table
---@return any value
---@return { path: string, code: string } expected
function M.break_value(schema, document, valid, between, rng)
  local candidates = {}
  collect(document, valid, {}, document["$defs"] or {}, candidates)
  shuffle(candidates, between, rng)
  for attempt, candidate in ipairs(candidates) do
    if attempt > MAX_ATTEMPTS then break end
    local value
    if #candidate.keys == 0 then value = candidate.new
    else value = replaced(valid, candidate.keys, candidate.new, candidate.remove) end
    local ok, violations = schema:validate(value)
    local only = violations and #violations == 1 and violations[1] or nil
    if not ok and only then
      return value, { path = only.path, code = only.code }
    end
  end
  error(core.ArgumentError("test.generate_invalid: no value violating exactly one constraint could be built for this schema (it accepts every value, or only combined constraints apply): add a constraint such as a bound, or write the invalid value by hand"), 0)
end

return M
