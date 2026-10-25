-- Micro-benchmark: BufferedReader:read_line over a TCP stream whose peer sends many small chunks (the
-- buffered `read_until` path), on the loopback interface.
-- Usage: lua packages/net/benchmarks/read-until.lua   (from the repository root)
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

local LINES, LINE, CHUNK = 200000, ("x"):rep(63) .. "\n", 100

reactor.run(function()
  local listener <close> = net.listen("127.0.0.1", 0)
  local port = listener:local_address().port
  reactor.fork(function()
    local peer <close> = listener:accept()
    local text = LINE:rep(LINES)
    for i = 1, #text, CHUNK do peer:write(text:sub(i, i + CHUNK - 1)) end
  end)
  local client <close> = net.connect("127.0.0.1", port)
  local reader = client:reader()
  local start = reactor.now()
  for _ = 1, LINES do assert(reader:read_line() == LINE:sub(1, -2)) end
  local seconds = reactor.now() - start
  print(string.format("read_line %d-byte chunks %.0f lines/s", CHUNK, LINES / seconds))
  print(string.format("read_line %d-byte chunks %.1f MB/s", CHUNK, LINES * #LINE / seconds / 1e6))
end)
