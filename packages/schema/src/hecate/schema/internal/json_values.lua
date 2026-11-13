-- Operations on decoded JSON values: the marker-preserving result, the deep copy and the structural equality.
-- Internal to `hecate.schema`: not public API. `schema.lua` and the other `internal/` modules require it.
global <const> require, type, next

local json = require("hecate.json")

local null = json.null

---@class hecate.schema.internal.json_values
local M = {}

--- Gives `result` the JSON array or object marker of `value`, so that an empty one still encodes as it was sent.
local function remark(value, result)
  if json.is_array(value) then return json.array(result) end
  if json.is_object(value) then return json.object(result) end
  return result
end

--- A deep copy of a decoded JSON value (markers of `hecate.json` are kept), so that a default is never shared.
local function copy_value(value)
  if type(value) ~= "table" or value == null then return value end
  local copy = {}
  for key, member in next, value do copy[key] = copy_value(member) end
  if json.is_array(value) then return json.array(copy) end
  if json.is_object(value) then return json.object(copy) end
  return copy
end

--- Structural equality of decoded JSON values; `1` and `1.0` are equal numbers, as in JSON Schema. Bounded like the
--- depth guard (OQ-99): two tables that are still different tables below `json.DEFAULT_MAX_DEPTH` levels are reported as DIFFERENT, never
--- by a Lua stack overflow. Decoded content stops at the same depth, so only a hand-built table can reach the bound.
---@param a any
---@param b any
---@param level? integer  nesting already entered (0 at the top)
---@return boolean
local function json_equal(a, b, level)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" or a == null or b == null then return false end
  level = (level or 0) + 1
  if level > json.DEFAULT_MAX_DEPTH then return false end -- read at call time: `limits.max_depth` lowers it at boot
  local count = 0
  for key, member in next, a do
    if not json_equal(member, b[key], level) then return false end
    count = count + 1
  end
  for _ in next, b do count = count - 1 end
  return count == 0
end

M.remark = remark
M.copy_value = copy_value
M.json_equal = json_equal
return M
