-- Starts the hello API: `lua main.lua` (port from HELLO_PORT, default 8080; worker processes from HELLO_WORKERS,
-- default 1; Ctrl+C stops it gracefully). Run it from this directory, with the Hecate packages on `package.path`.
-- With HELLO_WORKERS above 1 this process is the primary, and the supervisor starts this same script again for each
-- worker (ADR 0023): a worker builds the same application and `serve` detects its role.
package.path = "src/?.lua;src/?/init.lua;" .. package.path

local reactor = require("hecate.reactor")
local kernel = require("hecate.kernel") -- only for `kernel.supervisor.worker_role()`, not in the meta-module `hecate`
local log = require("hecate.log")
local hello = require("hello")

local port = tonumber(os.getenv("HELLO_PORT") or "") or 8080
local workers = math.tointeger(tonumber(os.getenv("HELLO_WORKERS") or "")) or 1
--- Logs each response on the standard error stream (the default logger): the method, the path without the query
--- string (the raw target can carry secrets such as tokens), the status, the bytes sent and the duration.
---@param info hecate.http.ResponseInfo
local function log_response(info)
  local path = (info.target or "-"):match("^[^?]*")
  log.default():informational(("%s %s -> %d"):format(info.method or "-", path, info.status),
    { status = info.status, bytes = info.bytes, duration_ms = math.floor(info.duration * 1000 + 0.5) })
end

local app = hello.application({
  server = { host = "127.0.0.1", port = port, on_response = log_response },
  workers = workers, grace_timeout = 10,
})

-- `serve` logs the address it listens on, and returns once SIGINT or SIGTERM has stopped it: the requests in flight
-- finish within the grace period (10 seconds here).
local primary = kernel.supervisor.worker_role() == nil -- read before `serve`, which takes the role
reactor.run(function() app:serve() end)
if primary then io.stdout:write("hello: stopped\n") end
