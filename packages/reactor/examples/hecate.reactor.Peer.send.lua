-- Hands a connection to another process. The parent accepts a TCP connection
-- and passes it to the child with the message "serve"; the child writes on the
-- stream it received, and the connection is closed in the parent by the
-- hand-over. The parent waits for the child's acknowledgement before it goes
-- on, as a sender should (on Windows the receiver's copy of the socket depends
-- on the sender still being there).
local reactor = require("hecate.reactor")

local CHILD = [[
local reactor = require('hecate.reactor')
reactor.run(function()
  local parent = reactor.ipc.parent()
  local message, stream = parent:receive()
  stream:write('handled by the child after ' .. message .. '\n')
  stream:close()
  parent:send('done')
end)
]]

reactor.run(function()
  local listener <close> = reactor.tcp_listen("127.0.0.1", 0)
  local port = listener:local_address().port
  local client = reactor.fork(function()
    local stream <close> = reactor.tcp_connect("127.0.0.1", port)
    return stream:read()
  end)
  local process = reactor.spawn(arg[-1], { "-e", CHILD }, {
    ipc = true,
    env = { LUA_PATH_5_5 = package.path, LUA_CPATH_5_5 = package.cpath },
  })
  local peer <close> = assert(process.ipc)
  peer:send("serve", listener:accept()) -- the stream now belongs to the child
  peer:receive() -- the child's acknowledgement
  process:wait()
  print((reactor.join(client):gsub("\n$", "")))
end)
-- Prints: handled by the child after serve
