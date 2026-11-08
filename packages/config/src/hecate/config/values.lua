-- The frozen values of a configuration: `Section` (an object or a map) and `List` (an array); configuration.md,
-- "Immutability and typed access". Both are value classes of `hecate.core`: a write raises `ConformanceError`.
global <const> require, type, pairs, ipairs, tostring

local core = require("hecate.core")

--- An object or a map of a configuration: immutable, read by field, iterated with `pairs`. It has no method, so that a
--- key named `get` of a map stays readable.
---@class hecate.config.Section
---@overload fun(): hecate.config.Section
local Section = core.value_class("Section")
core.finalise(Section)

--- An array of a configuration: immutable, read by index, iterated with `ipairs` and `pairs`, measured with `#`.
---@class hecate.config.List
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
---@param value any  a plain value (copied, never adopted)
---@param wrap fun(value: any): any
---@param secrets table<string, true>  dotted paths of the secret leaves
---@param path string  dotted path of `value` ("" for the root)
---@return any
function M.freeze(value, wrap, secrets, path)
  if type(value) ~= "table" then
    if secrets[path] then return wrap(value) end
    return value
  end
  local fields = {}
  local is_list = value[1] ~= nil
  if is_list then
    for index, item in ipairs(value) do fields[index] = M.freeze(item, wrap, secrets, path .. "[]") end
  else
    for key, item in pairs(value) do
      local child = path == "" and tostring(key) or (path .. "." .. tostring(key))
      fields[key] = M.freeze(item, wrap, secrets, child)
    end
  end
  local frozen = core.instantiate_value(is_list and List or Section, fields)
  if secrets[path] then return wrap(frozen) end
  return frozen
end

return M
