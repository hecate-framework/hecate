-- Child process of process_test.lua: behaviour chosen by the first argument.
local reactor = require("hecate.reactor")

local mode = arg[1]

reactor.run(function()
  local peer = reactor.ipc.parent()
  if mode == "no_channel" then
    os.exit(peer == nil and 0 or 9)
  end
  assert(peer, "no channel to the parent")
  if mode == "env" then
    peer:send(os.getenv("HECATE_TEST_VALUE") or "unset")
  elseif mode == "echo" then
    while true do
      local message = peer:receive()
      if message == nil then return end
      peer:send(message:upper())
    end
  elseif mode == "stream" then
    local message, stream = peer:receive()
    assert(stream, "no stream received")
    stream:write("worker " .. message)
    stream:close()
    peer:send("done")
  end
end)
