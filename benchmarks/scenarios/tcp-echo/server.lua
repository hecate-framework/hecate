-- tcp-echo server: accepts connections and sends back every byte it receives, on the reactor and `hecate.net`.
-- Usage: lua benchmarks/scenarios/tcp-echo/server.lua [port]   (from the repository root; 0 = a free port)
-- Prints `listening <port>` once it accepts connections, then runs until it is killed.
global <const> _VERSION, package, io, arg, print, require, tonumber, ipairs, pcall
for _, name in ipairs({ "core", "reactor", "net" }) do
  package.path = ("packages/%s/src/?.lua;packages/%s/src/?/init.lua;"):format(name, name) .. package.path
end
local version = _VERSION:match("%d+%.%d+")
for _, tree in ipairs({ ".hecate/rocks", "spikes/rocks" }) do
  package.cpath = tree .. "/lib/lua/" .. version .. "/?.so;" .. package.cpath
end

local reactor = require("hecate.reactor")
local net = require("hecate.net")

local function serve(connection)
  local peer <close> = connection
  peer:set_nodelay(true)
  while true do
    local data = peer:read(65536)
    if data == nil then return end -- the client closed its end
    peer:write(data)
  end
end

reactor.run(function()
  local listener <close> = net.listen("0.0.0.0", tonumber(arg[1]) or 0, { backlog = 4096 })
  print("listening " .. listener:local_address().port)
  io.stdout:flush()
  while true do
    local connection = listener:accept()
    reactor.detach(function() pcall(serve, connection) end)
  end
end)
