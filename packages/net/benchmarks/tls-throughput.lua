-- Micro-benchmark: throughput of one TLS stream over the loopback interface (handshake excluded),
-- using the test certificates of packages/net/tests/fixtures. Skips when the native module is not built.
-- Usage: lua packages/net/benchmarks/tls-throughput.lua   (from the repository root)
global <const> _VERSION, package, string, print, require, ipairs, assert, io, os, tostring
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

local available, reason = net.tls.available()
if not available then
  print("# SKIP tls-throughput: " .. tostring(reason))
  os.exit(0)
end

local function fixture(name)
  local f = assert(io.open("packages/net/tests/fixtures/" .. name, "rb"))
  local s = f:read("a")
  f:close()
  return s
end

local CHUNK, COUNT = 16384, 3000
local payload = ("x"):rep(CHUNK)
local server = net.tls.server_config({ cert_pem = fixture("server.pem"), key_pem = fixture("server.key") })
local client_config = net.tls.client_config({ system_roots = false, ca_pem = fixture("ca.pem") })

reactor.run(function()
  local listener <close> = net.listen("127.0.0.1", 0)
  local drained = reactor.fork(function()
    local tls <close> = net.tls.accept(listener:accept(), server)
    local reader = tls:reader()
    reader:read_exact(CHUNK * COUNT, CHUNK * COUNT)
  end)
  local tls <close> = net.tls.connect(net.connect("127.0.0.1", listener:local_address().port), "localhost", client_config)
  local start = reactor.now()
  for _ = 1, COUNT do tls:write(payload) end
  reactor.join(drained)
  local seconds = reactor.now() - start
  print(string.format("tls write %d B %.1f MB/s", CHUNK, CHUNK * COUNT / seconds / 1e6))
end)
