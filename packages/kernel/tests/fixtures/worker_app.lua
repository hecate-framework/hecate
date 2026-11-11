-- A worker of supervisor_test.lua: serves "<index>:<pid>" on every path, exits on /crash; with HECATE_TEST_MODE=exit
-- it exits at once (a crash loop).
local uv = require("luv")
local reactor = require("hecate.reactor")
local http = require("hecate.http")
local log = require("hecate.log")
local supervisor = require("hecate.kernel.supervisor")

if os.getenv("HECATE_TEST_MODE") == "exit" then os.exit(3) end

reactor.run(function()
  local role = assert(supervisor.worker_role(), "not started as a worker")
  local server = http.Server(function(request)
    if request.target == "/crash" then os.exit(4) end
    return http.Response(200, { content = ("%d:%d"):format(role.index, uv.os_getpid()) })
  end, { logger = log.Logger({ sinks = {} }) })
  role:serve(server, 5)
end)
