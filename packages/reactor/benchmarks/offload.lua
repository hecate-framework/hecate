-- Micro-benchmark: costs of `reactor.offload`: the round trip of an empty function (queueing, the pool
-- thread, the wake-up), many concurrent round trips, and the copy of a large table between Lua states
-- (encoding and decoding run on the reactor thread for arguments and results).
-- Usage: lua packages/reactor/benchmarks/offload.lua   (from the repository root)
global <const> _VERSION, package, string, print, require, ipairs, os, table
for _, name in ipairs({ "core", "reactor" }) do
  package.path = ("packages/%s/src/?.lua;packages/%s/src/?/init.lua;"):format(name, name) .. package.path
end
local version = _VERSION:match("%d+%.%d+")
-- As the test harness: the project tree, then the spike tree (spikes/rocks, git-ignored), which wins.
for _, tree in ipairs({ ".hecate/rocks", "spikes/rocks" }) do
  package.cpath = tree .. "/lib/lua/" .. version .. "/?.so;" .. package.cpath
end
local reactor = require("hecate.reactor")
local codec = require("hecate.reactor.internal.transfer").codec

local function measure(label, count, unit, body)
  reactor.run(function()
    local start = reactor.now()
    body()
    print(string.format("%s %.0f %s", label, count / (reactor.now() - start), unit))
  end)
end

local SEQUENTIAL, CONCURRENT, ENTRIES = 20000, 50000, 200000

measure("sequential round trips", SEQUENTIAL, "calls/s", function()
  for i = 1, SEQUENTIAL do reactor.offload(function(n) return n end, i) end
end)

measure("concurrent round trips", CONCURRENT, "calls/s", function()
  for _ = 1, CONCURRENT // 1000 do
    local batch = {}
    for i = 1, 1000 do batch[i] = reactor.fork(reactor.offload, function(n) return n end, i) end
    reactor.join(table.unpack(batch))
  end
end)

local records = {}
for i = 1, ENTRIES // 4 do records[i] = { id = i, name = "record " .. i, score = i / 3 } end
local encoded
local start = os.clock()
encoded = codec.encode("argument", 1, { records })
print(string.format("encode table %.0f entries/s (%d bytes)", ENTRIES / (os.clock() - start), #encoded))
start = os.clock()
codec.decode(encoded)
print(string.format("decode table %.0f entries/s", ENTRIES / (os.clock() - start)))
