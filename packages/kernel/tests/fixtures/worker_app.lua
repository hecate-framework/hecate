-- A worker of the supervisor tests: serves "<index>:<pid>" on every path and exits on /crash (the exit code, 4, is
-- not asserted by any test: the supervisor only sees that the worker ended). With HECATE_TEST_MODE=exit it exits at
-- once (a crash loop).
--
-- Modes: when the file named by HECATE_TEST_FLAG exists at start, the first process that gets to it takes it
-- (a rename, so that only one process ever receives it), removes it, and its content picks the behaviour of that
-- process alone:
--   exit               exits at once, before it is ready
--   hang               never reports ready, ignores every message of the primary (`stop` included) until it is killed
--   deaf               reports ready, then ignores every message of the primary, `stop` included, until it is killed
--   mute               reports ready, then never reads its message pipe again (connections handed over pile up in it);
--                      exits by itself after 60 s at the latest, so that it never outlives a failed test for long
--   slow_ready=<s>     waits <s> seconds before it serves and reports ready
--   exit_after_ready   reports ready, then exits
local uv = require("luv")
local reactor = require("hecate.reactor")
local http = require("hecate.http")
local log = require("hecate.log")
local supervisor = require("hecate.kernel.supervisor")

if os.getenv("HECATE_TEST_MODE") == "exit" then os.exit(3) end

--- The mode this process takes from the flag file, nil when there is none or another process took it.
---@return string? name
---@return string? value
local function take_mode()
  local flag = os.getenv("HECATE_TEST_FLAG")
  if flag == nil then return nil end
  local mine = flag .. "." .. uv.os_getpid()
  if not os.rename(flag, mine) then return nil end
  local handle = io.open(mine, "r")
  local text = handle and handle:read("a") or ""
  if handle then handle:close() end
  os.remove(mine)
  return text:match("^([%w_]+)=?(.*)$")
end

local mode, value = take_mode()
if mode == "exit" then os.exit(3) end

reactor.run(function()
  if mode == "hang" or mode == "deaf" then
    local peer = assert(reactor.ipc.parent(), "not started as a worker")
    if mode == "deaf" then peer:send("ready") end
    while true do
      local message, stream = peer:receive()
      if message == nil then os.exit(0) end -- the primary is gone: do not outlive it
      if stream ~= nil then stream:close() end
    end
  end
  if mode == "mute" then
    assert(reactor.ipc.parent(), "not started as a worker"):send("ready")
    reactor.sleep(60)
    os.exit(0)
  end
  if mode == "exit_after_ready" then
    assert(reactor.ipc.parent(), "not started as a worker"):send("ready")
    os.exit(3)
  end
  if mode == "slow_ready" then reactor.sleep(tonumber(value) or 1) end
  local role = assert(supervisor.worker_role(), "not started as a worker")
  local server = http.Server(function(request)
    if request.target == "/crash" then os.exit(4) end
    return http.Response(200, { content = ("%d:%d"):format(role.index, uv.os_getpid()) })
  end, { logger = log.Logger({ sinks = {} }) })
  role:serve(server, 5)
end)
