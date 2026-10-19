-- The value model shared by every backend (ADR 0020, "One public API"): the `null` sentinel and the
-- metatables that mark a table as a JSON array or a JSON object. Backends receive these exact
-- objects; identity (`==` on `null`, `rawequal` on metatables) is the contract.
global <const> setmetatable, error

--- Attaches a marker metatable to a table. This is `setmetatable` under another name, on purpose:
--- marking is the one raw use of metatables of the codec (the markers are tags, not objects of the
--- class model, and decoding tags every container, so no constructor can sit in between).
--- `check-boundaries` reserves the literal call to `hecate.core`; the justification is recorded in
--- OQ-48 and this alias is the only place that needs it.
---@generic T : table
---@param t T
---@param marker table
---@return T
local tag = setmetatable

--- The value of JSON `null`. A unique, immutable table, never `nil`, so that a decoded object keeps
--- its members whose value is null.
---@class hecate.json.Null
local null = tag({}, {
  __tostring = function() return "json.null" end,
  __newindex = function() error("json.null is immutable", 2) end,
  __metatable = "hecate.json.null",
})

--- Metatable of a table marked as a JSON array: it encodes as `[...]` even when empty.
---@type table
local array_metatable = { __name = "hecate.json.array" }

--- Metatable of a table marked as a JSON object: it encodes as `{...}` even when empty.
---@type table
local object_metatable = { __name = "hecate.json.object" }

return { tag = tag, null = null, array_metatable = array_metatable, object_metatable = object_metatable }
