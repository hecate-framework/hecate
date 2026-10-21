-- OQ-52: what mlua's serde bridge writes for the value model of hecate.json, next to the codec.
-- Usage (from the repository root, after building docs/spikes/OQ-52/mlua-bridge into spikes/OQ-52/bridge/bridge.so):
--   lua docs/spikes/OQ-52/bridge-cases.lua
global <const> package, require, print, pcall, tostring, string, table, ipairs, math, setmetatable
package.path = "packages/json/src/?.lua;packages/json/src/?/init.lua;packages/core/src/?.lua;packages/core/src/?/init.lua;"
  .. package.path
package.cpath = "spikes/OQ-52/bridge/?.so;" .. package.cpath
local json = require("hecate.json")
local bridge = require("bridge")

local cases = {
  { "empty table", {} },
  { "json.array()", json.array() },
  { "json.object()", json.object() },
  { "array", { 1, 2, 3 } },
  { "object", { a = 1 } },
  { "null value", { a = json.null } },
  { "hole", { 1, nil, 3 } },
  { "mixed", { 1, 2, a = 3 } },
  { "float 1.0", { 1.0 } },
  { "float 0.1", { 0.1 } },
  { "float 1e21", { 1e21 } },
  { "integer 2^53+1", { 9007199254740993 } },
  { "string escapes", { "a\"b\\c\n\1" } },
  { "invalid UTF-8", { "\255" } },
  { "NaN", { 0 / 0 } },
  { "marked empty in object", { list = json.array(), map = json.object() } },
}

print(("%-26s | %-22s | %-22s | %s"):format("case", "codec", "mlua default", "mlua tuned"))
for _, case in ipairs(cases) do
  local name, value = case[1], case[2]
  local function show(f)
    local ok, result = pcall(f, value)
    if not ok then return "error" end
    return result == nil and "nil (gives up)" or result
  end
  local codec = pcall(json.encode, value) and json.encode(value) or "error"
  print(("%-26s | %-22s | %-22s | %s"):format(name, codec, show(bridge.plain), show(bridge.tuned)))
end
