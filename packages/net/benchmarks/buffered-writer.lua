-- Micro-benchmark: BufferedWriter over a TCP stream, for small writes (coalesced in the buffer) and for
-- large payloads (sent directly), on the loopback interface.
-- Usage: lua packages/net/benchmarks/buffered-writer.lua   (from the repository root)
global <const> _VERSION, package, string, print, require, ipairs, assert, io, os
for _, name in ipairs({ "core", "reactor", "net" }) do
  package.path = ("packages/%s/src/?.lua;packages/%s/src/?/init.lua;"):format(name, name) .. package.path
end
local version = _VERSION:match("%d+%.%d+")
-- As the test harness: the project tree, then the spike tree (spikes/rocks, git-ignored), which wins.
for _, tree in ipairs({ ".hecate/rocks", "spikes/rocks" }) do
  package.cpath = tree .. "/lib/lua/" .. version .. "/?.so;" .. package.cpath
end
local reactor = require("hecate.reactor")
local net = require("hecate.net")

local function measure(label, payload, count)
  reactor.run(function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local total = #payload * count
    local drained = reactor.fork(function()
      local peer <close> = listener:accept()
      local reader = peer:reader()
      reader:read_exact(total, total)
    end)
    local client <close> = net.connect("127.0.0.1", listener:local_address().port, { nodelay = true })
    local writer = client:writer()
    local start = reactor.now()
    for _ = 1, count do writer:write(payload) end
    writer:flush()
    reactor.join(drained)
    local seconds = reactor.now() - start
    print(string.format("%s %.1f MB/s", label, total / seconds / 1e6))
    print(string.format("%s %.0f writes/s", label, count / seconds))
  end)
end

measure("write 64 B", ("x"):rep(64), 200000)
measure("write 1 MiB", ("x"):rep(1024 * 1024), 200)
