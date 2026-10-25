-- Micro-benchmark: scheduler costs of the reactor: forking and joining coroutines, a rendezvous channel
-- ping-pong between two coroutines, and many concurrent timers.
-- Usage: lua packages/reactor/benchmarks/scheduler.lua   (from the repository root)
global <const> _VERSION, package, string, print, require, ipairs, assert, os, table
for _, name in ipairs({ "core", "reactor", "net" }) do
  package.path = ("packages/%s/src/?.lua;packages/%s/src/?/init.lua;"):format(name, name) .. package.path
end
local version = _VERSION:match("%d+%.%d+")
-- As the test harness: the project tree, then the spike tree (spikes/rocks, git-ignored), which wins.
for _, tree in ipairs({ ".hecate/rocks", "spikes/rocks" }) do
  package.cpath = tree .. "/lib/lua/" .. version .. "/?.so;" .. package.cpath
end
local reactor = require("hecate.reactor")

local function measure(label, count, unit, body)
  reactor.run(function()
    local start = reactor.now()
    body()
    print(string.format("%s %.0f %s", label, count / (reactor.now() - start), unit))
  end)
end

local FORKS, MESSAGES, TIMERS = 200000, 200000, 10000

measure("fork and join", FORKS, "coroutines/s", function()
  for _ = 1, FORKS // 1000 do
    local batch = {}
    for i = 1, 1000 do batch[i] = reactor.fork(function() return i end) end
    reactor.join(table.unpack(batch))
  end
end)

measure("channel ping-pong", MESSAGES, "messages/s", function()
  local channel = reactor.Channel(0)
  local consumer = reactor.fork(function()
    for _ = 1, MESSAGES do channel:receive() end
  end)
  for i = 1, MESSAGES do channel:send(i) end
  reactor.join(consumer)
end)

measure("concurrent timers", TIMERS, "timers/s", function()
  local batch = {}
  for i = 1, TIMERS do batch[i] = reactor.fork(function() reactor.sleep(0.05) end) end
  reactor.join(table.unpack(batch))
end)
