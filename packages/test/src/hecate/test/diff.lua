-- Structural equality and diff of Lua values: the machinery of `assert_equal` on tables.
global <const> type, pairs, ipairs, table, tostring, math

---@class hecate.test.diff
local M = {}

local MAX_DIFFERENCES = 20

--- Renders a value on one line for a failure message: strings quoted, tables abbreviated.
---@param value any
---@param depth? integer  nesting still to expand (default 2)
---@return string
function M.show(value, depth)
  depth = depth or 2
  local kind = type(value)
  if kind == "string" then return (("%q"):format(value):gsub("\\\n", "\\n")) end
  if kind ~= "table" then return tostring(value) end
  if depth == 0 then return "{...}" end
  local keys = {}
  for k in pairs(value) do keys[#keys + 1] = k end
  table.sort(keys, M.key_before)
  local parts = {}
  for i, k in ipairs(keys) do
    if i > 8 then parts[#parts + 1] = "..."; break end
    local v = M.show(value[k], depth - 1)
    if math.type(k) == "integer" and k == i then parts[#parts + 1] = v
    elseif type(k) == "string" and k:find("^[%a_][%w_]*$") then parts[#parts + 1] = k .. " = " .. v
    else parts[#parts + 1] = "[" .. M.show(k, 0) .. "] = " .. v end
  end
  return "{" .. table.concat(parts, ", ") .. "}"
end

local type_rank = { number = 1, string = 2, boolean = 3 }

--- Total order of table keys, deterministic across runs: numbers, strings, booleans, others.
---@param a any
---@param b any
---@return boolean
function M.key_before(a, b)
  local ra, rb = type_rank[type(a)] or 4, type_rank[type(b)] or 4
  if ra ~= rb then return ra < rb end
  if ra == 1 or ra == 2 then return a < b end
  return tostring(a) < tostring(b)
end

local function path_name(path) return path == "" and "<root>" or path end

local function walk(expected, actual, path, out, seen)
  if #out >= MAX_DIFFERENCES then return end
  if expected == actual then return end -- primitives, or the same table
  if type(expected) ~= "table" or type(actual) ~= "table" then
    out[#out + 1] = ("%s: expected %s, got %s"):format(path_name(path), M.show(expected), M.show(actual))
    return
  end
  seen[expected] = seen[expected] or {}
  if seen[expected][actual] then return end -- a cycle already being compared
  seen[expected][actual] = true
  local keys, present = {}, {}
  for k in pairs(expected) do keys[#keys + 1] = k; present[k] = true end
  for k in pairs(actual) do if not present[k] then keys[#keys + 1] = k end end
  table.sort(keys, M.key_before)
  for _, k in ipairs(keys) do
    local child = path .. (type(k) == "string" and k:find("^[%a_][%w_]*$") and ("." .. k) or ("[" .. M.show(k, 0) .. "]"))
    local e, a = expected[k], actual[k]
    if e == nil then out[#out + 1] = ("%s: unexpected %s"):format(child, M.show(a))
    elseif a == nil then out[#out + 1] = ("%s: missing, expected %s"):format(child, M.show(e))
    else walk(e, a, child, out, seen) end
  end
end

--- Compares two values structurally: tables are equal when they have the same keys (compared
--- by `==`) with structurally equal values; other values by `==`. Metatables are ignored.
---@param expected any
---@param actual any
---@return boolean equal
---@return string[] differences  one line per difference (at most 20); empty when equal
function M.compare(expected, actual)
  local out = {}
  walk(expected, actual, "", out, {})
  return #out == 0, out
end

return M
