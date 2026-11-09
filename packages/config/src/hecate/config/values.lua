-- The frozen values of a configuration: `Section` (an object or a map) and `List` (an array); configuration.md,
-- "Immutability and typed access". Both are value classes of `hecate.core`: a write raises `ConformanceError`.
global <const> require, type, pairs, ipairs, tostring

local core = require("hecate.core")
local declaration = require("hecate.config.declaration")

--- An object or a map of a configuration: immutable, read by field, iterated with `pairs`. It has no method, so that a
--- key named `get` of a map stays readable.
---@class hecate.config.Section
---@field [string] any
---@overload fun(): hecate.config.Section
local Section = core.value_class("Section")
core.finalise(Section)

--- An array of a configuration: immutable, read by index, iterated with `ipairs` and `pairs`, measured with `#`.
---@class hecate.config.List
---@field [integer] any
---@overload fun(): hecate.config.List
local List = core.value_class("List")

--- The number of items: the border of the sequence (a list never holds nil).
---@return integer
function List:__len()
  local count = 0
  while self[count + 1] ~= nil do count = count + 1 end
  return count
end
core.finalise(List)

---@class hecate.config.values
local M = { Section = Section, List = List }

--- Freezes a plain value into `Section`s and `List`s, replacing the value at each path of `secrets` by `wrap(value)`.
--- The declared schema decides what a table becomes (an `array` is a `List` even when empty; an `object` or a `map` is a
--- `Section`); only under a schema that does not say (`union`, `any`, ...) does the shape of the value decide.
---@param value any  a plain value (copied, never adopted)
---@param wrap fun(value: any): any
---@param secrets table<string, true>  dotted paths of the secret leaves
---@param path string  dotted path of `value` ("" for the root)
---@param s? hecate.schema.Schema  the declared schema of `value`, when known
---@return any
function M.freeze(value, wrap, secrets, path, s)
  if type(value) ~= "table" then
    if secrets[path] then return wrap(value) end
    return value
  end
  local inner = s and declaration.unwrap(s) --[[@as hecate.schema.Schema]]
  local kind = s and inner.kind
  local is_list
  if kind == "array" then
    is_list = true
  elseif kind == "object" or kind == "map" then
    is_list = false
  else
    is_list = value[1] ~= nil
  end
  local fields = {}
  if is_list then
    local item = s and kind == "array" and inner.item or nil
    for index, member in ipairs(value) do fields[index] = M.freeze(member, wrap, secrets, path .. "[]", item) end
  else
    for key, member in pairs(value) do
      local child = path == "" and tostring(key) or (path .. "." .. tostring(key))
      local declared
      if s and kind == "object" then declared = inner.properties[key] elseif s and kind == "map" then declared = inner.item end
      fields[key] = M.freeze(member, wrap, secrets, child, declared)
    end
  end
  local frozen = core.instantiate_value(is_list and List or Section, fields)
  if secrets[path] then return wrap(frozen) end
  return frozen
end

return M
