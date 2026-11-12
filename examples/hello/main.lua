-- Starts the hello API: `lua main.lua` (port from HELLO_PORT, default 8080; worker processes from HELLO_WORKERS,
-- default 1; Ctrl+C stops it gracefully). Run it from this directory, with the Hecate packages on `package.path`.
-- With HELLO_WORKERS above 1 this process is the primary, and the supervisor starts this same script again for each
-- worker (ADR 0023): a worker builds the same application and `serve` detects its role.
package.path = "src/?.lua;src/?/init.lua;" .. package.path

local reactor = require("hecate.reactor")
local kernel = require("hecate.kernel")
local hello = require("hello")

local port = tonumber(os.getenv("HELLO_PORT") or "") or 8080
local workers = math.tointeger(tonumber(os.getenv("HELLO_WORKERS") or "")) or 1
local app = hello.application({ server = { host = "127.0.0.1", port = port }, workers = workers, grace_timeout = 10 })

local primary = kernel.supervisor.worker_role() == nil
if primary then
  io.stdout:write(("hello: listening on http://127.0.0.1:%d with %d process(es) (Ctrl+C to stop)\n"):format(port, workers))
end
-- `serve` returns once SIGINT or SIGTERM has drained the requests in flight.
reactor.run(function() app:serve() end)
if primary then io.stdout:write("hello: stopped\n") end
