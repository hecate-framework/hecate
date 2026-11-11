-- A worker of supervisor_test.lua: serves "<index>:<pid>" on every path, exits on /crash; with HECATE_TEST_MODE=exit
-- it exits at once (a crash loop). When the file named by HECATE_TEST_FLAG exists at start, its content picks the
-- behaviour of this process: `exit` (exits at once) or `hang` (never reports ready), to make a reload replacement fail.
local uv = require("luv")
local reactor = require("hecate.reactor")
local http = require("hecate.http")
local log = require("hecate.log")
local supervisor = require("hecate.kernel.supervisor")

if os.getenv("HECATE_TEST_MODE") == "exit" then os.exit(3) end

local flag = os.getenv("HECATE_TEST_FLAG")
local handle = flag and io.open(flag, "r")
if handle then
  local mode = handle:read("a")
  handle:close()
  if mode:match("^exit") then os.exit(3) end
  if mode:match("^hang") then reactor.run(function() reactor.sleep(3600) end) os.exit(0) end
end

reactor.run(function()
  local role = assert(supervisor.worker_role(), "not started as a worker")
  local server = http.Server(function(request)
    if request.target == "/crash" then os.exit(4) end
    return http.Response(200, { content = ("%d:%d"):format(role.index, uv.os_getpid()) })
  end, { logger = log.Logger({ sinks = {} }) })
  role:serve(server, 5)
end)
