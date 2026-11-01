-- Micro-benchmark: BufferedWriter over a TCP stream (and over TLS), for small writes (coalesced in the buffer)
-- at several buffer capacities and for large payloads (sent directly), on the loopback interface.
-- Usage: lua packages/net/benchmarks/buffered-writer.lua   (from the repository root)
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

-- Capacities swept for small writes: 4096 is the default of Go's `bufio.Writer`, 8192 the current
-- default of `BufferedWriter`, 16384 one TLS record of plaintext (RFC 8446 section 5.1). The measurement decides
-- the default (OQ-47 (7)): it is not changed here.
local CAPACITIES = { 4096, 8192, 16384, 32768, 65536 }
local SMALL_WRITES = { { size = 64, count = 100000 }, { size = 512, count = 50000 } }

local function fixture(name)
  local f = assert(io.open("packages/net/tests/fixtures/" .. name, "rb"))
  local s = f:read("a")
  f:close()
  return s
end

--- Sends `count` writes of `payload` through a `BufferedWriter` of `capacity` bytes over `open(listener_port)`
--- (a TCP stream, or a TLS stream) and prints MB/s and writes/s.
local function measure(label, payload, count, capacity, accept, open)
  reactor.run(function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local total = #payload * count
    local drained = reactor.fork(function()
      local peer <close> = accept(listener:accept())
      local reader = peer:reader()
      reader:read_exact(total, total)
    end)
    local client <close> = open(listener:local_address().port)
    local writer = net.BufferedWriter(client, { capacity = capacity })
    local start = reactor.now()
    for _ = 1, count do writer:write(payload) end
    writer:flush()
    reactor.join(drained)
    local seconds = reactor.now() - start
    print(string.format("%s %.1f MB/s", label, total / seconds / 1e6))
    print(string.format("%s %.0f writes/s", label, count / seconds))
  end)
end

local function tcp_accept(stream) return stream end
local function tcp_open(port) return net.connect("127.0.0.1", port, { nodelay = true }) end

-- Large payloads bypass the buffer: one reference measurement with the default capacity.
measure("write 1 MiB", ("x"):rep(1024 * 1024), 200, 8192, tcp_accept, tcp_open)

for _, spec in ipairs(SMALL_WRITES) do
  for _, capacity in ipairs(CAPACITIES) do
    measure(("write %d B capacity %d"):format(spec.size, capacity), ("x"):rep(spec.size), spec.count, capacity, tcp_accept, tcp_open)
  end
end

-- The same sweep over TLS, where the capacity decides how full each record is (needs the native module).
local available, reason = net.tls.available()
if not available then
  print("# SKIP tls sweep: " .. tostring(reason))
else
  local server = net.tls.server_config({ cert_pem = fixture("server.pem"), key_pem = fixture("server.key") })
  local client_config = net.tls.client_config({ system_roots = false, ca_pem = fixture("ca.pem") })
  local function tls_accept(stream) return net.tls.accept(stream, server) end
  local function tls_open(port) return net.tls.connect(net.connect("127.0.0.1", port), "localhost", client_config) end
  for _, capacity in ipairs(CAPACITIES) do
    measure(("tls write 64 B capacity %d"):format(capacity), ("x"):rep(64), 50000, capacity, tls_accept, tls_open)
  end
end
