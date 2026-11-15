-- Generators of valid values from a schema: the basis of property-based tests (testing.md, "Property-based testing").
-- They work from the JSON Schema 2020-12 document the schema emits, so what is generated is what the contract says,
-- with a seeded pseudo-random source (SplitMix64, Steele, Lea and Flood 2014): one seed, one sequence, on every platform.
global <const> require, type, error, pairs, ipairs, table, math, string, tostring, pcall

local core = require("hecate.core")
local schema_package = require("hecate.schema")
local json = require("hecate.json")

--- A seeded generator of values valid for a schema.
---@class hecate.test.Generator
---@overload fun(schema: hecate.schema.Schema, seed?: integer): hecate.test.Generator
local Generator = core.class("Generator")

local MAX_DEPTH = 6 -- beyond it optional parts are omitted, arrays are as short and unions as plain as allowed
local ALPHABET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 _-"

local function refuse(message) error(core.ArgumentError("test.generate: " .. message), 0) end

-- SplitMix64 on Lua integers (wrapping arithmetic, logical shifts).
local function bits(rng)
  rng.state = rng.state + -7046029254386353131 -- 0x9E3779B97F4A7C15
  local z = rng.state
  z = (z ~ (z >> 30)) * -4658895280553007687 -- 0xBF58476D1CE4E5B9
  z = (z ~ (z >> 27)) * -7723592293110705685 -- 0x94D049BB133111EB
  return z ~ (z >> 31)
end

-- An integer in [lo, hi].
local function between(rng, lo, hi)
  local range = hi - lo + 1
  if range <= 0 then return lo + (bits(rng) >> 1) end -- the range overflows: any non-negative offset fits
  return lo + (bits(rng) >> 1) % range
end

-- A float strictly between 0 and 1.
local function unit(rng) return ((bits(rng) >> 11) + 1) / 9007199254740993 end

local function letters(rng, length)
  local out = {}
  for i = 1, length do
    local k = between(rng, 1, #ALPHABET)
    out[i] = ALPHABET:sub(k, k)
  end
  return table.concat(out)
end

local function word(rng, length)
  local out = {}
  for i = 1, length do out[i] = string.char(between(rng, 97, 122)) end
  return table.concat(out)
end

local function date(rng)
  return ("%04d-%02d-%02d"):format(between(rng, 1970, 2100), between(rng, 1, 12), between(rng, 1, 28))
end

local FORMATS = {
  uuid = function(rng)
    return ("%08x-%04x-4%03x-8%03x-%012x"):format(between(rng, 0, 0xFFFFFFFF), between(rng, 0, 0xFFFF),
      between(rng, 0, 0xFFF), between(rng, 0, 0xFFF), between(rng, 0, 0xFFFFFFFFFFFF))
  end,
  date = date,
  ["date-time"] = function(rng)
    return ("%sT%02d:%02d:%02dZ"):format(date(rng), between(rng, 0, 23), between(rng, 0, 59), between(rng, 0, 59))
  end,
  email = function(rng) return word(rng, between(rng, 1, 8)) .. "@" .. word(rng, between(rng, 1, 8)) .. ".example" end,
  uri = function(rng) return "https://" .. word(rng, between(rng, 1, 8)) .. ".example/" .. word(rng, between(rng, 0, 8)) end,
  ipv4 = function(rng)
    return ("%d.%d.%d.%d"):format(between(rng, 0, 255), between(rng, 0, 255), between(rng, 0, 255), between(rng, 0, 255))
  end,
}

local generate

local function string_value(node, rng)
  if node.pattern ~= nil then refuse("a string with a pattern cannot be generated") end
  if node.format ~= nil then
    local make = FORMATS[node.format]
    if make == nil then refuse("the format " .. tostring(node.format) .. " cannot be generated") end
    return (make --[[@as function]])(rng)
  end
  local minimum = node.minLength or 0
  local maximum = node.maxLength or (minimum + 16)
  if maximum < minimum then refuse("minLength is above maxLength") end
  return letters(rng, between(rng, minimum, maximum))
end

-- The bounds of a numeric node as { low, high, low_open, high_open }, with a window of 1000 when one side is free.
local function bounds(node, whole)
  local low, high = node.minimum, node.maximum
  local low_open, high_open = false, false
  if node.exclusiveMinimum ~= nil and (low == nil or node.exclusiveMinimum >= low) then
    low, low_open = node.exclusiveMinimum, true
  end
  if node.exclusiveMaximum ~= nil and (high == nil or node.exclusiveMaximum <= high) then
    high, high_open = node.exclusiveMaximum, true
  end
  if low == nil and high == nil then low, high = -1000, 1000
  elseif low == nil then low = high - 1000
  elseif high == nil then high = low + 1000 end
  if whole then
    low = math.ceil(low)
    if low_open and low == node.exclusiveMinimum then low = low + 1 end
    high = math.floor(high)
    if high_open and high == node.exclusiveMaximum then high = high - 1 end
  end
  return low, high, low_open, high_open
end

local function integer_value(node, rng)
  local low, high = bounds(node, true)
  local step = node.multipleOf
  if step ~= nil then
    local k_low, k_high = math.ceil(low / step), math.floor(high / step)
    if k_low > k_high then refuse("no integer multiple fits the bounds") end
    return math.tointeger(between(rng, k_low, k_high) * step) or refuse("multipleOf must give integers")
  end
  if low > high then refuse("no integer fits the bounds") end
  return math.tointeger(between(rng, low, high)) or refuse("the bounds are not integers")
end

local function number_value(node, rng)
  local low, high, low_open, high_open = bounds(node, false)
  local step = node.multipleOf
  if step ~= nil then
    local k_low, k_high = math.ceil(low / step), math.floor(high / step)
    if low_open and k_low * step <= low then k_low = k_low + 1 end
    if high_open and k_high * step >= high then k_high = k_high - 1 end
    if k_low > k_high then refuse("no multiple fits the bounds") end
    return between(rng, k_low, k_high) * step + 0.0
  end
  if low > high or (low == high and (low_open or high_open)) then refuse("no number fits the bounds") end
  if low == high then return low + 0.0 end
  return low + unit(rng) * (high - low)
end

local function key_of(value)
  if type(value) == "table" then return "t" .. json.encode(value) end
  return type(value) .. tostring(value)
end

local function array_value(node, rng, context, depth)
  local minimum = node.minItems or 0
  local maximum = node.maxItems or (minimum + 4)
  if maximum < minimum then refuse("minItems is above maxItems") end
  local count = depth > MAX_DEPTH and minimum or between(rng, minimum, maximum)
  local items, seen = {}, {}
  local item_node = node.items or {}
  for _ = 1, count do
    local value
    for attempt = 1, 100 do
      value = generate(item_node, rng, context, depth + 1)
      if not node.uniqueItems or not seen[key_of(value)] then break end
      if attempt == 100 then refuse("not enough distinct items for uniqueItems") end
    end
    seen[key_of(value)] = true
    items[#items + 1] = value
  end
  return items
end

local function object_value(node, rng, context, depth)
  local required = {}
  for _, name in ipairs(node.required or {}) do required[name] = true end
  local names = {}
  for name in pairs(node.properties or {}) do names[#names + 1] = name end
  table.sort(names)
  local out = {}
  for _, name in ipairs(names) do
    if required[name] or (depth <= MAX_DEPTH and between(rng, 0, 1) == 1) then
      out[name] = generate(node.properties[name], rng, context, depth + 1)
    end
  end
  local extra = node.additionalProperties
  if type(extra) == "table" then
    local minimum = node.minProperties or 0
    local maximum = node.maxProperties or (minimum + 3)
    if maximum < minimum then refuse("minProperties is above maxProperties") end
    local count = depth > MAX_DEPTH and minimum or between(rng, minimum, maximum)
    local made = 0
    while made < count do
      local key = word(rng, between(rng, 1, 6))
      if out[key] == nil then
        out[key] = generate(extra, rng, context, depth + 1)
        made = made + 1
      end
    end
  end
  return out
end

local function plain(alternative) return alternative["$ref"] == nil and alternative.type ~= "object" and alternative.type ~= "array" end

function generate(node, rng, context, depth)
  if type(node) ~= "table" then refuse("the schema holds a boolean schema, which is not generated") end
  local reference = node["$ref"]
  if reference ~= nil then
    local name = reference:match("^#/%$defs/(.+)$")
    local target = name and context.defs[name]
    if target == nil then refuse("unresolved reference " .. tostring(reference)) end
    return generate(target, rng, context, depth)
  end
  if node.const ~= nil then return node.const end
  if node.enum ~= nil then return node.enum[between(rng, 1, #node.enum)] end
  local alternatives = node.anyOf or node.oneOf
  if alternatives ~= nil then
    if depth > MAX_DEPTH then
      for _, alternative in ipairs(alternatives) do
        if plain(alternative) then return generate(alternative, rng, context, depth + 1) end
      end
    end
    return generate(alternatives[between(rng, 1, #alternatives)], rng, context, depth + 1)
  end
  local kind = node.type
  if kind == "string" then return string_value(node, rng)
  elseif kind == "integer" then return integer_value(node, rng)
  elseif kind == "number" then return number_value(node, rng)
  elseif kind == "boolean" then return between(rng, 0, 1) == 1
  elseif kind == "null" then return json.null
  elseif kind == "array" then return array_value(node, rng, context, depth)
  elseif kind == "object" then return object_value(node, rng, context, depth)
  elseif kind == nil then return between(rng, -1000, 1000) -- `any`: a small integer
  end
  refuse("the type " .. tostring(kind) .. " cannot be generated")
end

--- Creates a generator. The emission of the schema is read once; `pattern` options and unknown formats cannot be
--- generated and raise `hecate.core.ArgumentError` at the first `next`.
---
--- Class-bound parts (`schema.of`) are generated as plain tables of the attributes their schema declares, which
--- `schema:build` turns into instances.
---
--- Raises `hecate.core.ArgumentError` when `schema` is not a schema or `seed` is not an integer.
---@param schema hecate.schema.Schema
---@param seed? integer  default 0
function Generator:init(schema, seed)
  if not core.is_instance_of(schema, schema_package.Schema) then
    error(core.ArgumentError("test.Generator: expects a schema (hecate.schema)"), 3)
  end
  if seed ~= nil and math.type(seed) ~= "integer" then
    error(core.ArgumentError("test.Generator: the seed must be an integer"), 3)
  end
  self._document = schema:to_json_schema()
  self._rng = { state = seed or 0 }
end

--- Returns the next valid value of the sequence.
---
--- Raises `hecate.core.ArgumentError` for a schema that cannot be generated (a pattern, an unknown format, bounds
--- that no value satisfies, `uniqueItems` with too few distinct items).
---@return any value
function Generator:next()
  local ok, value = pcall(generate, self._document, self._rng, { defs = self._document["$defs"] or {} }, 0)
  if not ok then
    if core.is_instance_of(value, core.ArgumentError) then error(value, 2) end
    error(value, 0)
  end
  return value
end

--- The first value of the sequence of `seed`: `Generator(schema, seed):next()`.
---@param schema hecate.schema.Schema
---@param seed? integer  default 0
---@return any value
local function generate_one(schema, seed) return Generator(schema, seed):next() end

return { Generator = core.finalise(Generator), generate = generate_one }
