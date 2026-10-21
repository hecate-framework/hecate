-- OQ-52: the float and string text of the codec next to serde_json's own output (mlua bridge, default options).
-- Usage (from the repository root, after building docs/spikes/OQ-52/mlua-bridge into spikes/OQ-52/bridge/bridge.so):
--   lua docs/spikes/OQ-52/float-layout.lua
global <const> package, require, print, string, ipairs
package.path = "packages/json/src/?.lua;packages/json/src/?/init.lua;packages/core/src/?.lua;packages/core/src/?/init.lua;" .. package.path
package.cpath = "spikes/OQ-52/bridge/?.so;" .. package.cpath
local json = require("hecate.json")
local bridge = require("bridge")
local samples = { 1.0, 0.5, 100.0, 123456.789, 1e14, 1e15, 1e16, 1e17, 1e21, 1.5e300, 0.001, 0.0001, 0.00001, 1e-7, 1.5e-10, 5e-324, 2.2250738585072014e-308, -0.0, 0.0, -2.5, 0.1 + 0.2, 2^53, 2^63 }
print(("%-24s | %-24s | %s"):format("value", "codec", "serde_json"))
for _, x in ipairs(samples) do
  local a = json.encode(json.array({ x })):sub(2, -2)
  local b = bridge.plain(json.array({ x })):sub(2, -2)
  print(("%-24s | %-24s | %s%s"):format(string.format("%.17g", x), a, b, a == b and "" or "   <- differs"))
end
local text = json.encode(json.array({ "a\"b\\c\n\r\t\b\f\1\31\127é\u{1F600}</script>" }))
print(text, bridge.plain(json.array({ "a\"b\\c\n\r\t\b\f\1\31\127é\u{1F600}</script>" })))
