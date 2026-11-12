-- kernel-json server: a `kernel.Application` with one route, `GET /json`, whose action returns a table that the kernel
-- represents with the declared response schema and encodes as JSON: routing, dispatch, the filter chain and the JSON
-- codec on top of the HTTP/1.1 stack of the `plaintext` scenario.
-- Usage: lua benchmarks/scenarios/kernel-json/server.lua [port]   (from the repository root; 0 = a free port)
-- Prints `listening <port>` once it accepts connections, then runs until it is killed. Needs the native modules of
-- `json` and `http` (`lua tools/run.lua build-native json`, then `http`).
global <const> io, arg, print, require, tonumber, dofile, ipairs, pcall
dofile("benchmarks/lib/setup.lua")({ "core", "reactor", "net", "json", "log", "http", "router", "schema", "container",
  "config", "kernel" })

for _, native in ipairs({ { "hecate.json", "json" }, { "hecate.http.native", "http" } }) do
  if not pcall(require, native[1]) then
    print(("skipped the native modules of %s are not built (lua tools/run.lua build-native %s)"):format(native[2], native[2]))
    return
  end
end

local reactor = require("hecate.reactor")
local schema = require("hecate.schema")
local kernel = require("hecate.kernel")
local log = require("hecate.log")

local routes = kernel.routes("benchmark")
routes:get("/json", {
  summary = "A fixed message",
  responses = { [200] = schema.object({ message = schema.string() }) },
  action = function() return { message = "Hello, World!" } end,
})

-- a logger without sinks (nothing written per request, the first output line stays `listening`); no signal handling,
-- the runner stops the process with SIGTERM; response validation off, as in production
local app = kernel.Application({ routes = { routes }, logger = log.Logger({ sinks = {} }), signals = false,
  validate_responses = false, server = { host = "127.0.0.1", port = tonumber(arg[1]) or 0, backlog = 4096 } })

reactor.run(function()
  local serving = reactor.fork(function() app:serve() end)
  while app:local_address() == nil do reactor.sleep(0.005) end
  print("listening " .. app:local_address().port)
  io.stdout:flush()
  reactor.join(serving)
end)
