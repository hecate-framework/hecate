-- Child process of process_test.lua: behaviour chosen by the first argument.
local reactor = require("hecate.reactor")
local uv = require("luv")

local mode = arg[1]

--- Starts a plain child (no message pipe) running Lua `code`, with the paths of this process.
local function lua_child(code, options)
  options = options or {}
  options.env = { LUA_PATH = package.path, LUA_PATH_5_5 = package.path, LUA_CPATH = package.cpath,
    LUA_CPATH_5_5 = package.cpath }
  return reactor.spawn(uv.exepath(), { "-e", code }, options)
end

reactor.run(function()
  local peer = reactor.ipc.parent()
  if mode == "no_pipe" then
    os.exit(peer == nil and 0 or 9)
  end
  assert(peer, "no message pipe to the parent")
  if mode == "env" then
    peer:send(os.getenv("HECATE_TEST_VALUE") or "unset")
  elseif mode == "getenv" then
    peer:send(os.getenv(arg[2]) or "unset")
  elseif mode == "cwd" then
    peer:send(uv.fs_realpath(uv.cwd()) or uv.cwd())
  elseif mode == "parent_twice" then
    peer:send(reactor.ipc.parent() == peer and "same" or "different")
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
  elseif mode == "grandchild_env" then
    -- A plain grandchild must neither see the marker nor reach the message pipe (it runs the
    -- "no_pipe" mode of this fixture), also when started through `run_process`.
    local plain = reactor.spawn(uv.exepath(), { arg[0], "no_pipe" })
    local result = reactor.run_process(uv.exepath(), { "-e", "io.write(os.getenv('HECATE_IPC_FD') or 'unset')" })
    peer:send(("%d %s"):format(plain:wait().code, result.stdout))
  elseif mode == "grandchild_fd" then
    -- Starts a long-lived grandchild, reports its pid and exits at once: the parent sees the end of
    -- the message pipe only if the grandchild did not inherit the descriptor.
    local long = lua_child("require('luv').sleep(60000)")
    peer:send(tostring(long.pid))
    os.exit(0)
  elseif mode == "connect" then
    -- Hands a connected stream over to the parent, then waits until the parent has taken it:
    -- on Windows the sender must keep its handle until the receiver acknowledged.
    local stream = reactor.connect_tcp("127.0.0.1", assert(tonumber(arg[2])))
    peer:send("connected", stream)
    peer:receive()
  elseif mode == "delayed" then
    -- Receives only after a delay: the hand-overs queue up in the operating system meanwhile.
    reactor.sleep(0.3)
    for _ = 1, assert(tonumber(arg[2])) do
      local message, stream = peer:receive()
      assert(message and stream, "no message with a stream")
      stream:write(message)
      stream:close()
    end
    peer:send("done")
  elseif mode == "handover" then
    -- Echoes each message with the handed-over stream, if any, written with "ack:" first.
    while true do
      local message, stream = peer:receive()
      if message == nil then return end
      if stream then stream:write("ack:" .. message); stream:close() end
      peer:send(("%d:%s"):format(#message, stream and "stream" or "plain"))
    end
  end
end)
