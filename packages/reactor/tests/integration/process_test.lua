local test = require("harness.test")
local core = require("hecate.core")
local uv = require("luv")
local reactor = require("hecate.reactor")
local T = test.Case("ProcessTest")

local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]integration[/\\][^/\\]+$") or "."
local child_script = here .. "/fixtures/ipc_child.lua"

--- Runs `fn` on a reactor and checks that no libuv handle is left behind.
local function run(self, fn)
  local before = reactor.Reactor.open_handles()
  local result = reactor.run(fn)
  self:assert_equal(before, reactor.Reactor.open_handles())
  return result
end

--- Starts the fixture. The test runner finds modules through `package.path` set in this process, so
--- the child gets the same search paths through the environment.
local function child(mode, options)
  options = options or {}
  local env = { LUA_PATH = package.path, LUA_PATH_5_5 = package.path, LUA_CPATH = package.cpath, LUA_CPATH_5_5 = package.cpath }
  for name, value in pairs(options.env or {}) do env[name] = value end
  options.env = env
  return reactor.spawn(uv.exepath(), { child_script, mode }, options)
end

function T:test_wait_reports_the_exit_status()
  local status = run(self, function()
    local process = reactor.spawn(uv.exepath(), { "-e", "os.exit(7)" }, { stdout = "ignore", stderr = "ignore" })
    self:assert_true(process.pid > 0)
    return process:wait()
  end)
  self:assert_equal(7, status.code)
end

function T:test_kill_ends_a_running_child()
  local status = run(self, function()
    local process = child("echo", { ipc = true })
    self:assert_true(process:is_running())
    process:kill("sigkill")
    local result = process:wait()
    process.ipc:close()
    self:assert_false(process:is_running())
    process:kill() -- no effect on an exited child
    return result
  end)
  self:assert_true(status.signal ~= 0 or status.code ~= 0)
end

function T:test_several_coroutines_may_wait()
  local codes = run(self, function()
    local process = reactor.spawn(uv.exepath(), { "-e", "os.exit(4)" })
    local a = reactor.fork(function() return process:wait().code end)
    local b = reactor.fork(function() return process:wait().code end)
    return { reactor.join(a), reactor.join(b), process:wait().code }
  end)
  self:assert_equal(4, codes[1])
  self:assert_equal(4, codes[2])
  self:assert_equal(4, codes[3])
end

function T:test_a_cancelled_wait_leaves_the_child_running()
  run(self, function()
    local process = child("echo", { ipc = true })
    self:assert_false((pcall(reactor.deadline, 0.05, process.wait, process)))
    self:assert_true(process:is_running())
    process:kill("sigkill")
    process:wait()
    process.ipc:close()
  end)
end

function T:test_env_is_added_to_the_inherited_environment()
  local values = run(self, function()
    local process = child("env", { ipc = true, env = { HECATE_TEST_VALUE = "from the parent" } })
    local value = process.ipc:receive()
    process.ipc:close()
    process:wait()
    local plain = child("env", { ipc = true })
    local unset = plain.ipc:receive()
    plain.ipc:close()
    plain:wait()
    return { value, unset }
  end)
  self:assert_equal("from the parent", values[1])
  self:assert_equal("unset", values[2])
end

function T:test_unknown_program_raises_io_error()
  local err = self:assert_error(function()
    reactor.run(function() reactor.spawn("hecate-no-such-program-xyz") end)
  end)
  self:assert_true(core.is_instance_of(err, reactor.IoError))
end

function T:test_argument_validation()
  ---@diagnostic disable: param-type-mismatch, assign-type-mismatch  -- the point is to pass wrong types
  reactor.run(function()
    for _, call in ipairs({
      function() reactor.spawn(42) end,
      function() reactor.spawn("x", "not a list") end,
      function() reactor.spawn("x", {}, { bogus = true }) end,
      function() reactor.spawn("x", {}, { ipc = "yes" }) end,
      function() reactor.spawn("x", {}, { stdout = "pipe" }) end,
      function() reactor.spawn("x", {}, { env = { ["A=B"] = "c" } }) end,
      function() reactor.spawn("x", {}, { env = { A = 1 } }) end,
    }) do
      local err = self:assert_error(call)
      self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
    end
  end)
end

function T:test_a_process_without_a_channel_has_no_parent_peer()
  local status = run(self, function() return child("no_channel"):wait() end)
  self:assert_equal(0, status.code)
  self:assert_equal(nil, reactor.ipc.parent())
end

function T:test_messages_round_trip_through_the_channel()
  local replies = run(self, function()
    local process = child("echo", { ipc = true })
    local peer = process.ipc --[[@as hecate.reactor.Peer]]
    peer:send("hello")
    local first = peer:receive()
    peer:send("")
    local second = peer:receive()
    local large = ("x"):rep(300000)
    peer:send(large)
    local third = peer:receive()
    peer:close()
    process:wait() -- the child sees the channel close and returns
    return { first, second, third }
  end)
  self:assert_equal("HELLO", replies[1])
  self:assert_equal("", replies[2])
  self:assert_equal(("X"):rep(300000), replies[3])
end

function T:test_messages_sent_back_to_back_keep_their_boundaries()
  local replies = run(self, function()
    local process = child("echo", { ipc = true })
    local peer = process.ipc --[[@as hecate.reactor.Peer]]
    for index = 1, 50 do peer:send("m" .. index) end
    local received = {}
    for index = 1, 50 do received[index] = peer:receive() end
    peer:close()
    process:wait()
    return received
  end)
  for index = 1, 50 do self:assert_equal("M" .. index, replies[index]) end
end

function T:test_a_stream_is_handed_over_to_the_child()
  local text = run(self, function()
    local listener <close> = reactor.tcp_listen("127.0.0.1", 0)
    local port = listener:local_address().port
    local process = child("stream", { ipc = true })
    local peer = process.ipc --[[@as hecate.reactor.Peer]]
    local client <close> = reactor.tcp_connect("127.0.0.1", port)
    local accepted = listener:accept()
    peer:send("job", accepted)
    self:assert_true(accepted:is_closed(), "the sender gives the stream up")
    local data = {}
    while true do
      local chunk = client:read()
      if chunk == nil then break end
      data[#data + 1] = chunk
    end
    self:assert_equal("done", peer:receive())
    peer:close()
    process:wait()
    return table.concat(data)
  end)
  self:assert_equal("worker job", text)
end

function T:test_receive_returns_nil_when_the_child_exits()
  run(self, function()
    local process = child("stream", { ipc = true })
    local peer = process.ipc --[[@as hecate.reactor.Peer]]
    process:kill("sigkill")
    process:wait()
    self:assert_equal(nil, peer:receive())
    peer:close()
  end)
end

function T:test_send_validation()
  run(self, function()
    local process = child("echo", { ipc = true })
    local peer = process.ipc --[[@as hecate.reactor.Peer]]
    local function refused(message, handle)
      local err = self:assert_error(function() peer:send(message, handle) end)
      self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
    end
    refused(42)
    refused(("x"):rep(16 * 1024 * 1024 + 1))
    refused("m", {})
    local listener <close> = reactor.tcp_listen("127.0.0.1", 0)
    local closed = reactor.tcp_connect("127.0.0.1", listener:local_address().port)
    closed:close()
    refused("m", closed)
    peer:close()
    process:wait()
  end)
end

function T:test_concurrent_receivers_are_refused()
  run(self, function()
    local process = child("echo", { ipc = true })
    local peer = process.ipc --[[@as hecate.reactor.Peer]]
    local waiting = reactor.fork(function() return peer:receive() end)
    reactor.sleep(0.02)
    self:assert_error(function() peer:receive() end)
    peer:send("go")
    self:assert_equal("GO", reactor.join(waiting))
    peer:close()
    process:wait()
  end)
end

function T:test_reuseport_is_reported_and_enforced()
  run(self, function()
    local supported = reactor.supports_reuseport()
    self:assert_equal("boolean", type(supported))
    if supported then
      local a <close> = reactor.tcp_listen("127.0.0.1", 0, { reuseport = true })
      local b <close> = reactor.tcp_listen("127.0.0.1", a:local_address().port, { reuseport = true })
      -- both sockets accept: connect until each one has taken a connection
      local seen = { a = 0, b = 0 }
      local port = a:local_address().port
      for _, pair in ipairs({ { "a", a }, { "b", b } }) do
        local name, listener = pair[1], pair[2]
        reactor.fork(function() listener:accept():close(); seen[name] = seen[name] + 1 end)
      end
      local clients = {}
      for index = 1, 40 do
        clients[index] = reactor.tcp_connect("127.0.0.1", port)
        if seen.a + seen.b >= 2 then break end
        reactor.sleep(0)
      end
      for _, client in ipairs(clients) do client:close() end
    else
      local err = self:assert_error(function() reactor.tcp_listen("127.0.0.1", 0, { reuseport = true }) end)
      self:assert_true(core.is_instance_of(err, reactor.TransportError), tostring(err))
      self:assert_equal("ENOTSUP", err.context.errno)
    end
    local err = self:assert_error(function() reactor.tcp_listen("127.0.0.1", 0, { reuseport = "yes" }) end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError))
  end)
end

return T
