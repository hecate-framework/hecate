-- A worker of tests/integration/application_workers_test.lua: the same application as the primary (same options, so
-- `workers = 2` here too), started again by the supervisor of the primary. `Application:serve` detects the worker role
-- and serves through it; the route answers the process id.
local uv = require("luv")
local reactor = require("hecate.reactor")
local kernel = require("hecate.kernel")
local log = require("hecate.log")

local routes = kernel.routes("whoami")
routes:get("/whoami", { action = function() return { pid = uv.os_getpid() } end })

local app = kernel.Application({
  routes = { routes }, workers = 2, strategy = "round_robin", grace_timeout = 5,
  logger = log.Logger({ sinks = {} }), server = { host = "127.0.0.1", port = 0 },
})
reactor.run(function() app:serve() end)
