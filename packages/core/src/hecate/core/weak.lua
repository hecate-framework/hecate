-- Weak tables: a table whose keys and/or values do not keep their referents alive. Lives in
-- core because raw `setmetatable` is reserved to this package (check-boundaries).
global <const> setmetatable, require

local raise = require("hecate.core.internal.raise")

---@class hecate.core
local M = {}

--- Which references of a weak table do not keep their referents alive: keys (`"k"`), values (`"v"`) or both (`"kv"`).
---@alias hecate.core.WeakMode "k"|"v"|"kv"

local MODES = { k = true, v = true, kv = true }

--- Creates an empty table with weak keys (`"k"`, the default), weak values (`"v"`) or both
--- (`"kv"`). Typical use: a side table keyed by instance (the presence set of the schema, an
--- identity map) that must not keep the instances alive. The table carries no other metamethod.
---
--- Raises `hecate.core.ArgumentError` if `mode` is not `"k"`, `"v"` or `"kv"`.
---@param mode? hecate.core.WeakMode  which references are weak; default `"k"`
---@return table weak  a new empty table
function M.weak_table(mode)
  if mode == nil then mode = "k" end
  if not MODES[mode] then raise.argument("weak_table expects mode \"k\", \"v\" or \"kv\"") end
  return setmetatable({}, { __mode = mode }) -- hecate: raw-metatable weak table
end

return { weak_table = M.weak_table }
