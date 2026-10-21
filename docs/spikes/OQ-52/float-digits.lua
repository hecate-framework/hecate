-- OQ-52: do the digits of serde_json's own float output (shortest round trip) equal the digits of the codec
-- (the fewest of 15, 16, 17 significant digits that read back)? Random IEEE doubles; only the layout of the
-- exponent and the point is allowed to differ.
-- Usage: lua docs/spikes/OQ-52/float-digits.lua [count]   (needs spikes/OQ-52/bridge/bridge.so, see bridge-cases.lua)
global <const> package, require, print, string, math, tonumber, arg, pcall, os
package.path = "packages/json/src/?.lua;packages/json/src/?/init.lua;packages/core/src/?.lua;packages/core/src/?/init.lua;"
  .. package.path
package.cpath = "spikes/OQ-52/bridge/?.so;" .. package.cpath
local json = require("hecate.json")
local bridge = require("bridge")

--- digits and decimal exponent of a number text, ignoring layout and trailing zeros.
local function normal(text)
  text = text:gsub("^%[", ""):gsub("%]$", ""):gsub("^%-", "")
  local mantissa, exponent = text:match("^([^eE]+)[eE]([-+]?%d+)$")
  mantissa = mantissa or text
  exponent = tonumber(exponent or 0)
  local whole, fraction = mantissa:match("^(%d*)%.?(%d*)$")
  local digits = whole .. fraction
  local point = #whole + exponent
  local lead = #digits:match("^0*")
  digits = digits:sub(lead + 1):gsub("0+$", "")
  return digits .. "e" .. (point - lead)
end

math.randomseed(52)
local count = tonumber(arg[1]) or 300000
local differ, denormal, shown = 0, 0, 0
for _ = 1, count do
  local x = string.unpack("<d", string.pack("<I8", math.random(0, math.maxinteger) ~ (math.random(0, 1) << 63)))
  if x == x and x ~= math.huge and x ~= -math.huge and x ~= 0 then
    local mine = json.encode(json.array({ x }))
    local theirs = bridge.plain(json.array({ x }))
    if normal(mine) ~= normal(theirs) then
      differ = differ + 1
      if math.abs(x) < 2.2250738585072014e-308 then denormal = denormal + 1 end
      if shown < 5 then shown = shown + 1; print("differ:", mine, theirs) end
    end
  end
end
print(("%d random doubles, digits differ for %d (%d of them subnormal)"):format(count, differ, denormal))

-- Doubles that come from decimal text (prices, coordinates, measurements): few digits, many magnitudes.
local differ_decimal = 0
for _ = 1, count do
  local x = math.random(1, 10 ^ math.random(1, 17)) / 10 ^ math.random(0, 25)
  if normal(json.encode(json.array({ x }))) ~= normal(bridge.plain(json.array({ x }))) then
    differ_decimal = differ_decimal + 1
    if differ_decimal <= 5 then print("differ:", json.encode(json.array({ x })), bridge.plain(json.array({ x }))) end
  end
end
print(("%d decimal-looking doubles, digits differ for %d"):format(count, differ_decimal))
