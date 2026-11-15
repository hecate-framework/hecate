-- Property runner: checks a property over values generated from a schema and shrinks a counterexample to a minimal
-- one (QuickCheck, Claessen and Hughes 2000). Shrinking is structural and schema-agnostic: a candidate is kept only
-- when the schema still accepts it, so a counterexample always conforms to the contract.
global <const> require, type, error, pairs, ipairs, pcall, table, math, tostring, next

local core = require("hecate.core")
local json = require("hecate.json")
local schema_package = require("hecate.schema")
local generate = require("hecate.test.generate")

--- Options of `check_property`.
---@class hecate.test.PropertyOptions
---@field runs? integer  values to try (default 100)
---@field seed? integer  seed of the generator (default 1)
---@field max_shrinks? integer  evaluations of the property allowed while shrinking (default 1000)

--- Outcome of `check_property`.
---@class hecate.test.PropertyResult
---@field ok boolean  the property held for every value
---@field runs integer  values tried (up to and including the failing one)
---@field seed integer
---@field run? integer  1-based index of the failing value
---@field original? any  the first failing value
---@field counterexample? any  the failing value after shrinking
---@field shrinks? integer  accepted shrinking steps
---@field failure? string  why the shrunk value fails: the error message, or "the property returned false"

---@class hecate.test.property
local M = {}

local function sorted_keys(value)
  local keys = {}
  for key in pairs(value) do keys[#keys + 1] = key end
  table.sort(keys)
  return keys
end

local function is_list(value) return value[1] ~= nil end

local function copy(value)
  local out = {}
  for key, item in pairs(value) do out[key] = item end
  return out
end

local candidates

-- Simpler variants of `value`, simplest first. Each is a new value; the input is never changed.
function candidates(value)
  local out = {}
  local kind = type(value)
  if math.type(value) == "integer" then
    if value ~= 0 then out[#out + 1] = 0 end
    local half = value // 2
    if value < 0 then half = -((-value) // 2) end
    if half ~= 0 and half ~= value then out[#out + 1] = half end
    local step = value > 0 and value - 1 or value + 1
    if value ~= 0 and step ~= half and step ~= 0 then out[#out + 1] = step end
  elseif kind == "number" then
    if value ~= 0 then out[#out + 1] = 0.0 end
    local whole = value >= 0 and math.floor(value) or math.ceil(value)
    if whole ~= value then out[#out + 1] = whole + 0.0 end
  elseif kind == "boolean" then
    if value then out[#out + 1] = false end
  elseif kind == "string" then
    if #value > 0 then out[#out + 1] = "" end
    if #value > 1 then out[#out + 1] = value:sub(1, #value // 2) end
    if #value > 0 then
      out[#out + 1] = value:sub(1, #value - 1)
      out[#out + 1] = value:sub(2)
    end
  elseif kind == "table" and value ~= json.null then
    if is_list(value) then
      if #value > 1 then out[#out + 1] = {} end
      for index = 1, #value do
        local shorter = {}
        for i, item in ipairs(value) do if i ~= index then shorter[#shorter + 1] = item end end
        out[#out + 1] = shorter
      end
      for index, item in ipairs(value) do
        for _, variant in ipairs(candidates(item)) do
          local changed = copy(value)
          changed[index] = variant
          out[#out + 1] = changed
        end
      end
    elseif next(value) ~= nil then
      local keys = sorted_keys(value)
      for _, key in ipairs(keys) do
        local smaller = copy(value)
        smaller[key] = nil
        out[#out + 1] = smaller
      end
      for _, key in ipairs(keys) do
        for _, variant in ipairs(candidates(value[key])) do
          local changed = copy(value)
          changed[key] = variant
          out[#out + 1] = changed
        end
      end
    end
  end
  return out
end

local function describe(error_value)
  if type(error_value) == "table" and error_value.message ~= nil then return tostring(error_value.message) end
  return tostring(error_value)
end

-- Runs the property: nil when it holds, else the reason it fails (it returned false, or raised).
local function falsified(property, value)
  local ok, result = pcall(property, value)
  if not ok then return describe(result) end
  if result == false then return "the property returned false" end
  return nil
end

local function check_arguments(schema, property, options)
  if not core.is_instance_of(schema, schema_package.Schema) then
    error(core.ArgumentError("test.check_property: expects a schema (hecate.schema)"), 3)
  end
  if type(property) ~= "function" then
    error(core.ArgumentError("test.check_property: the property must be a function of a value"), 3)
  end
  if options ~= nil and type(options) ~= "table" then
    error(core.ArgumentError("test.check_property: options must be a table"), 3)
  end
  for key, value in pairs(options or {}) do
    if key ~= "runs" and key ~= "seed" and key ~= "max_shrinks" then
      error(core.ArgumentError("test.check_property: unknown option " .. tostring(key)), 3)
    end
    if math.type(value) ~= "integer" or (key ~= "seed" and value < 1) then
      error(core.ArgumentError("test.check_property: option " .. key .. " must be an integer"
        .. (key ~= "seed" and " of at least 1" or "")), 3)
    end
  end
end

--- Checks that `property` holds for values generated from `schema`. The property receives a value and fails by
--- returning `false` or raising; anything else (including no result) is success. On the first failing value, the
--- value is shrunk: simpler variants (smaller numbers, shorter strings and arrays, fewer properties) that the schema
--- still accepts and that still fail replace it, until none does or `max_shrinks` evaluations were spent.
---
--- Integers shrink toward zero, so a bound far from zero is reached one step at a time. The seed and the index of the
--- failing run reproduce a failure; `generate` limits apply (a `pattern` cannot be generated).
---
--- Raises `hecate.core.ArgumentError` for bad arguments or a schema that cannot be generated.
---@param schema hecate.schema.Schema
---@param property fun(value: any): boolean?
---@param options? hecate.test.PropertyOptions
---@return hecate.test.PropertyResult result
function M.check_property(schema, property, options)
  check_arguments(schema, property, options)
  options = options or {}
  local runs, seed, budget = options.runs or 100, options.seed or 1, options.max_shrinks or 1000
  local generator = generate.Generator(schema, seed)
  for run = 1, runs do
    local original = generator:next()
    local failure = falsified(property, original)
    if failure ~= nil then
      local value, shrinks, progress = original, 0, true
      while progress and budget > 0 do
        progress = false
        for _, candidate in ipairs(candidates(value)) do
          if budget <= 0 then break end
          if schema:validate(candidate) then
            budget = budget - 1
            local reason = falsified(property, candidate)
            if reason ~= nil then
              value, failure, shrinks, progress = candidate, reason, shrinks + 1, true
              break
            end
          end
        end
      end
      return { ok = false, runs = run, seed = seed, run = run, original = original, counterexample = value,
        shrinks = shrinks, failure = failure }
    end
  end
  return { ok = true, runs = runs, seed = seed }
end

--- Text of a counterexample for a failure message.
---@param value any
---@return string
function M.render(value)
  local ok, text = pcall(json.encode, value)
  return ok and text or tostring(value)
end

return M
