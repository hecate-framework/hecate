-- Compatibility shims for library functions that differ between Lua versions
-- (ADR 0001). Library code calls these, never the version-specific function directly.
global <const> table, _VERSION

--- Shims for library functions that differ between Lua versions (ADR 0001).
---@class hecate.core.compat
---@field lua_version string  Major.minor version of the running interpreter ("5.5").
---@field table_create fun(array_size?: integer, hash_size?: integer): table
local compat = {}

compat.lua_version = _VERSION:match("%d+%.%d+") or _VERSION

--- Creates an empty table, pre-sized when the interpreter supports it.
--- Lua 5.5 provides `table.create`; the 5.4 lowering returns a plain table.
---@param array_size? integer  expected number of sequence elements
---@param hash_size? integer  expected number of other fields
---@return table
function compat.table_create(array_size, hash_size)
  local create = table.create
  if create then return create(array_size or 0, hash_size or 0) end
  return {}
end

return compat
