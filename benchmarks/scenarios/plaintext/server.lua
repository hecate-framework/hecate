-- plaintext server: `http.Server` answering every request with a short `text/plain` body, keep-alive and pipelining
-- as the server provides them (no kernel, no routing): the cost of the HTTP/1.1 stack alone.
-- Usage: lua benchmarks/scenarios/plaintext/server.lua [port]   (from the repository root; 0 = a free port)
-- Prints `listening <port>` once it accepts connections, then runs until it is killed. Needs the native module of
-- `http` (`lua tools/run.lua build-native http`).
global <const> io, arg, print, require, tonumber, dofile
dofile("benchmarks/lib/setup.lua")({ "core", "reactor", "net", "json", "log", "http" })

local reactor = require("hecate.reactor")
local http = require("hecate.http")
local log = require("hecate.log")
if not http.Server then -- the server needs the native parser
  print("skipped the native module of http is not built (lua tools/run.lua build-native http)")
  return
end

local BODY <const> = "Hello, World!"

local function action()
  return http.Response(200, { fields = http.Fields({ ["Content-Type"] = "text/plain" }), content = BODY })
end

reactor.run(function()
  -- a logger without sinks: nothing is written per request, and the first line of the output stays `listening`
  local server = http.Server(action, { host = "127.0.0.1", port = tonumber(arg[1]) or 0, backlog = 4096,
    logger = log.Logger({ sinks = {} }) })
  local listener = server:listen()
  print("listening " .. listener:local_address().port)
  io.stdout:flush()
  server:serve(listener)
end)
