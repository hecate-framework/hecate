-- OQ-52: encoder A (hand-written) against encoder B (serde_json), byte for byte, on random values and options,
-- and the chain encode -> decode -> encode of B (and A) on every value both encode.
-- Usage (from the repository root, A built by `lua tools/run.lua build-native json`, B built from
-- docs/spikes/OQ-52/serde-encoder, see the report):
--   lua docs/spikes/OQ-52/ab-differential.lua <A.so> <B.so> [cases] [seed]
global <const> package, require, print, string, math, tonumber, tostring, arg, assert, table, setmetatable, utf8
package.path = "packages/json/src/?.lua;packages/json/src/?/init.lua;packages/core/src/?.lua;packages/core/src/?/init.lua;"
  .. package.path
local markers = require("hecate.json.internal.markers")
local reference = require("hecate.json.internal.reference")

local function load_encoder(path)
  local open = assert(package.loadlib(path, "luaopen_hecate_json_encoder_native"))
  local module = open()
  module.bind(markers)
  return module
end
local A = load_encoder(arg[1])
local B = load_encoder(arg[2])
local CASES = tonumber(arg[3]) or 200000
math.randomseed(tonumber(arg[4]) or 52)
local random = math.random

local function random_string()
  local kind = random(1, 6)
  if kind == 1 then return "" end
  local parts = {}
  for i = 1, random(1, 24) do
    local r = random(1, 10)
    if r <= 4 then parts[i] = string.char(random(32, 126))
    elseif r == 5 then parts[i] = string.char(random(0, 31))
    elseif r == 6 then parts[i] = ({ '"', "\\", "/", "\127" })[random(1, 4)]
    elseif r == 7 then parts[i] = utf8.char(random(128, 0x7FF))
    elseif r == 8 then parts[i] = utf8.char(random(0x800, 0xD7FF))
    elseif r == 9 then parts[i] = utf8.char(random(0x10000, 0x10FFFF))
    else parts[i] = (kind == 6 and string.char(random(128, 255)) or "x") end -- kind 6: invalid UTF-8 possible
  end
  return table.concat(parts)
end

local function random_float()
  local r = random(1, 6)
  if r == 1 then return string.unpack("<d", string.pack("<I8", random(0, math.maxinteger) ~ (random(0, 1) << 63))) end
  if r == 2 then return random(-1000000, 1000000) / 10 ^ random(0, 8) end
  if r == 3 then return random(1, 9) * 10.0 ^ random(-30, 30) end
  if r == 4 then return ({ 0.0, -0.0, 1e15, 1e16, 1e21, 5e-324, 1.7976931348623157e308, 0 / 0, math.huge, -math.huge })[random(1, 10)] end
  if r == 5 then return random(1, 1000) + 0.0 end
  return random() * 10 ^ random(-8, 8)
end

local function random_value(depth)
  local r = random(1, depth >= 5 and 7 or 12)
  if r == 1 then return random(math.mininteger, math.maxinteger) end
  if r == 2 then return random(-1000, 1000) end
  if r == 3 then return random_float() end
  if r == 4 then return random_string() end
  if r == 5 then return random(1, 2) == 1 end
  if r == 6 then return markers.null end
  if r == 7 then return random(1, 2) == 1 and "k" or 7 end
  local size = random(0, 5)
  local t = {}
  if r <= 9 then -- array, possibly with holes, maybe marked
    for i = 1, size do if random(1, 12) ~= 1 then t[i] = random_value(depth + 1) end end
    if random(1, 3) == 1 then setmetatable(t, markers.array_metatable) end
  elseif r == 10 then -- object, maybe marked
    for _ = 1, size do t[random_string()] = random_value(depth + 1) end
    if random(1, 3) == 1 then setmetatable(t, markers.object_metatable) end
  elseif r == 11 then -- mixed keys (the reference declines)
    t[1] = random_value(depth + 1)
    t.a = random_value(depth + 1)
  else -- deep chain
    local node = t
    for _ = 1, random(1, 30) do
      local child = random(1, 2) == 1 and {} or { random_value(depth + 3) }
      node[#node + 1] = child
      node = child
    end
  end
  return t
end

local INDENTS = { false, "  ", "    ", "\t", " " }
local function random_options()
  local indent = INDENTS[random(1, #INDENTS)]
  return {
    max_depth = ({ 1000, 1000, 1000, 3, 10, 250 })[random(1, 6)],
    max_size = ({ 16 * 1024 * 1024, 16 * 1024 * 1024, 20, 200, 2000 })[random(1, 5)],
    indent = indent or nil,
    canonical = random(1, 3) == 1,
  }
end

local differ, a_only, b_only, encoded, chain_broken = 0, 0, 0, 0, 0
local function show(what, value, options, a, b)
  if differ + a_only + b_only + chain_broken <= 5 then
    print(("%s: options=%s A=%s B=%s"):format(what, table.concat({ tostring(options.max_depth), tostring(options.max_size),
      tostring(options.indent), tostring(options.canonical) }, "/"), tostring(a), tostring(b)))
  end
end

for _ = 1, CASES do
  local value, options = random_value(0), random_options()
  local a, b = A.encode(value, options), B.encode(value, options)
  if a == nil and b ~= nil then a_only = a_only + 1; show("only B encodes", value, options, a, b)
  elseif a ~= nil and b == nil then b_only = b_only + 1; show("only A encodes", value, options, a, b)
  elseif a ~= b then differ = differ + 1; show("different text", value, options, a, b)
  elseif a ~= nil then
    encoded = encoded + 1
    -- The chain, with the reference decoder (the oracle): decode, then encode again with B. Member order of an unmarked
    -- table is the order of `pairs`, which a decode may change, so the chain is compared in canonical order.
    local decoded = reference.decode(a, { max_depth = 1000, max_size = 16 * 1024 * 1024 })
    if decoded == nil then
      chain_broken = chain_broken + 1; show("chain: cannot decode", value, options, a, b)
    else
      local c1 = B.encode(value, { max_depth = 1000, max_size = 16 * 1024 * 1024, canonical = true, indent = options.indent })
      local c2 = c1 and B.encode(decoded, { max_depth = 1000, max_size = 16 * 1024 * 1024, canonical = true, indent = options.indent })
      if c1 ~= nil and c1 ~= c2 then chain_broken = chain_broken + 1; show("chain: re-encoded text differs", value, options, c1, c2) end
    end
  end
end
print(("%d cases: %d encoded by both and identical or declined by both; A and B differ in text: %d; only A encodes: %d; only B encodes: %d; chain broken: %d"):format(
  CASES, encoded, differ, b_only, a_only, chain_broken))
