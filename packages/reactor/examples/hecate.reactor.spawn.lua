-- A long-lived child with a message pipe. The child is a second Lua interpreter that waits for one
-- message, answers it in capitals and exits; the parent sends, receives and waits for the exit.
-- The child needs the same module paths as this process, hence the two environment variables.
local reactor = require("hecate.reactor")

local CHILD = [[
local reactor = require('hecate.reactor')
reactor.run(function()
  local parent = reactor.ipc.parent()
  parent:send(parent:receive():upper())
end)
]]

reactor.run(function()
  local process = reactor.spawn(arg[-1], { "-e", CHILD }, {
    ipc = true,
    env = { LUA_PATH_5_5 = package.path, LUA_CPATH_5_5 = package.cpath },
  })
  local peer <close> = assert(process.ipc)
  peer:send("hello")
  local answer = peer:receive()
  local status = process:wait()
  print(("%s, exit code %d"):format(answer, status.code))
end)
-- Prints: HELLO, exit code 0
