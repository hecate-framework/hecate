-- Child of offload_exit_test.lua: its only offload is cancelled by a deadline while the function still
-- runs on a pool thread, then the script ends normally, so the Lua state closes. Without the wait in
-- `Reactor:run`, luv crashes while closing the state (found by the review of `offload`).
local reactor = require("hecate.reactor")
local ok, err = pcall(reactor.run, function()
  return reactor.deadline(0.01, reactor.offload, function()
    local stop = os.clock() + 0.3 -- process CPU time on Linux and macOS, wall time on Windows
    while os.clock() < stop do end
    return "late"
  end)
end)
io.write(ok and "not released" or (tostring(err):match("DeadlineExceededError") and "released" or tostring(err)))
