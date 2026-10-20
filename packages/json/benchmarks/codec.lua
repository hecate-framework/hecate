-- Throughput of the JSON codec: decode and encode of three generated documents, on the reference
-- backend and, when built (lua tools/run.lua build-native json), on the native backends.
-- Usage: lua packages/json/benchmarks/codec.lua   (from the repository root)
global <const> _VERSION, package, os, string, print, require, pcall, tostring, table, ipairs
package.path = "packages/json/src/?.lua;packages/json/src/?/init.lua;packages/core/src/?.lua;"
  .. "packages/core/src/?/init.lua;" .. package.path
local version = _VERSION:match("%d+%.%d+")
package.cpath = ".hecate/rocks/lib/lua/" .. version .. "/?.so;" .. package.cpath

local json = require("hecate.json")
local backend = require("hecate.json.internal.backend")

local ROUNDS = 7
local TARGET_BYTES = 2 * 1024 * 1024

-- A fixed generator: the same documents on every machine and every run.
local seed = 20261020
local function random(n)
  seed = (seed * 1103515245 + 12345) % 2147483648
  return seed % n + 1
end

local WORDS = { "alpha", "bravo", "charlie", "delta", "écho", "foxtrot", "golf", "hôtel", "india", "juliet" }

local function records()
  local list = json.array()
  local size = 0
  while size < TARGET_BYTES do
    local record = {
      id = #list + 1, name = WORDS[random(#WORDS)] .. " " .. WORDS[random(#WORDS)],
      score = random(100000) / 100, active = random(2) == 1, parent = json.null,
      tags = json.array({ WORDS[random(#WORDS)], WORDS[random(#WORDS)] }),
      position = { x = random(1000) / 7, y = random(1000) / 7 },
    }
    list[#list + 1] = record
    size = size + 150
  end
  return list
end

local function numbers()
  local list = json.array()
  for i = 1, TARGET_BYTES // 12 do list[i] = (random(2) == 1) and random(1000000000) or random(1000000000) / 1000 end
  return list
end

local function strings()
  local list = json.array()
  local size = 0
  while size < TARGET_BYTES do
    local text = WORDS[random(#WORDS)] .. '\n"quoted" \\ \t ' .. string.rep(WORDS[random(#WORDS)] .. " ", 12) .. "\u{1F600}"
    list[#list + 1] = text
    size = size + #text + 10
  end
  return list
end

local DOCUMENTS = { { "records", records() }, { "numbers", numbers() }, { "strings", strings() } }

--- Median seconds of ROUNDS runs of f.
local function time(f)
  local samples = {}
  f()
  for i = 1, ROUNDS do
    local start = os.clock()
    f()
    samples[i] = os.clock() - start
  end
  table.sort(samples)
  return samples[(ROUNDS + 1) // 2]
end

local function run(name)
  local ok, problem = pcall(backend.use, name)
  if not ok then
    print(("# backend %s is not available: %s"):format(name, (tostring(problem):gsub("\n.*", ""))))
    return
  end
  for _, document in ipairs(DOCUMENTS) do
    local label, value = document[1], document[2]
    local text = json.encode(value)
    local megabytes = #text / (1024 * 1024)
    print(("decode %s %s %.1f MB/s"):format(label, name, megabytes / time(function() json.decode(text) end)))
    print(("encode %s %s %.1f MB/s"):format(label, name, megabytes / time(function() json.encode(value) end)))
  end
end

run("reference")
run("native")
backend.use(nil)
