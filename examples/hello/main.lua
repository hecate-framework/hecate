-- Starts the hello API: `lua main.lua` (port from HELLO_PORT, default 8080; Ctrl+C stops it gracefully).
-- Run it from this directory, with the Hecate packages on `package.path`.
package.path = "src/?.lua;src/?/init.lua;" .. package.path

local reactor = require("hecate.reactor")
local hello = require("hello")

local port = tonumber(os.getenv("HELLO_PORT") or "") or 8080
local app = hello.application({ server = { host = "127.0.0.1", port = port }, grace_timeout = 10 })

io.stdout:write(("hello: listening on http://127.0.0.1:%d (Ctrl+C to stop)\n"):format(port))
-- `serve` returns once SIGINT or SIGTERM has drained the requests in flight.
reactor.run(function() app:serve() end)
io.stdout:write("hello: stopped\n")
