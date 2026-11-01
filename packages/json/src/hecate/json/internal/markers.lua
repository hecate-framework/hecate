-- The value model shared by the decoder and the encoder (ADR 0020, "One public API"): the `null` sentinel and the
-- metatables that mark a table as a JSON array or a JSON object. The native modules receive these exact
-- objects; identity (`==` on `null`, `rawequal` on metatables) is the contract.
global <const> setmetatable, error

--- Attaches a marker metatable to a table. Marking is the one raw use of metatables of the codec (the
--- markers are tags, not objects of the class model, and decoding tags every container, so no
--- constructor can sit in between): this file is the only one `check-boundaries` lets call
--- `setmetatable` outside `hecate.core` (OQ-48).
---@generic T : table
---@param t T
---@param marker table
---@return T
local function tag(t, marker) return setmetatable(t, marker) end

--- The value of JSON `null`. A unique, immutable table, never `nil`, so that a decoded object keeps
--- its members whose value is null.
---@class hecate.json.Null
local null = tag({}, {
  __tostring = function() return "json.null" end,
  __newindex = function() error("json.null: immutable", 2) end,
  __metatable = "hecate.json.null",
})

--- Metatable of a table marked as a JSON array: it encodes as `[...]` even when empty.
---@type table
local array_metatable = { __name = "hecate.json.array" }

--- Metatable of a table marked as a JSON object: it encodes as `{...}` even when empty.
---@type table
local object_metatable = { __name = "hecate.json.object" }

return { tag = tag, null = null, array_metatable = array_metatable, object_metatable = object_metatable }
