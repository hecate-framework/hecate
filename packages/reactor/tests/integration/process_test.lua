local test = require("harness.test")
local core = require("hecate.core")
local uv = require("luv")
local reactor = require("hecate.reactor")
local T = test.Case("ProcessTest")

local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]integration[/\\][^/\\]+$") or "."
-- Absolute: a test sets the working directory of the child.
local child_script = uv.fs_realpath(here .. "/fixtures/ipc_child.lua") or here .. "/fixtures/ipc_child.lua"
local wrapper_script = uv.fs_realpath(here .. "/fixtures/spawn_wrapper.lua") or here .. "/fixtures/spawn_wrapper.lua"
local is_windows = package.config:sub(1, 1) == "\\"

--- Makes the relative entries of a search path absolute: a child may run in another directory.
local function absolute(search_path)
  local entries = {}
  for entry in search_path:gmatch("[^;]+") do
    local absolute_entry = entry
    if not (entry:match("^[/\\]") or entry:match("^%a:") or entry:match("^!")) then
      absolute_entry = uv.cwd() .. "/" .. entry
    end
    entries[#entries + 1] = absolute_entry
  end
  return table.concat(entries, ";")
end

--- The environment that lets a child find the modules of this test run.
local function lua_env(extra)
  local path, cpath = absolute(package.path), absolute(package.cpath)
  local env = { LUA_PATH = path, LUA_PATH_5_5 = path, LUA_CPATH = cpath, LUA_CPATH_5_5 = cpath }
  for name, value in pairs(extra or {}) do env[name] = value end
  return env
end

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
  local args = { child_script, mode }
  for _, value in ipairs(options.args or {}) do args[#args + 1] = value end
  options.args = nil
  options.env = lua_env(options.env)
  return reactor.spawn(uv.exepath(), args, options)
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

function T:test_a_process_without_a_message_pipe_has_no_parent_peer()
  local status = run(self, function() return child("no_pipe"):wait() end)
  self:assert_equal(0, status.code)
  self:assert_equal(nil, reactor.ipc.parent())
end

function T:test_messages_round_trip_through_the_message_pipe()
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
    process:wait() -- the child sees the message pipe close and returns
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
    local listener <close> = reactor.listen_tcp("127.0.0.1", 0)
    local port = listener:local_address().port
    local process = child("stream", { ipc = true })
    local peer = process.ipc --[[@as hecate.reactor.Peer]]
    local client <close> = reactor.connect_tcp("127.0.0.1", port)
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
    local listener <close> = reactor.listen_tcp("127.0.0.1", 0)
    local closed = reactor.connect_tcp("127.0.0.1", listener:local_address().port)
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
    -- Let the first receive park (bounded poll, no fixed delay).
    for _ = 1, 2000 do
      if peer._receiving then break end ---@diagnostic disable-line: invisible
      reactor.sleep(0.001)
    end
    self:assert_true(peer._receiving, "the first receive parked") ---@diagnostic disable-line: invisible
    self:assert_error(function() peer:receive() end)
    peer:send("go")
    self:assert_equal("GO", reactor.join(waiting))
    peer:close()
    process:wait()
  end)
end

function T:test_ignored_output_is_discarded_and_inherited_output_reaches_the_parent()
  run(self, function()
    for _, case in ipairs({
      { mode = "ignore", out = "wrapper", err = "" },
      { mode = "inherit", out = "OUTwrapper", err = "ERR" },
      { mode = "default", out = "OUTwrapper", err = "ERR" },
    }) do
      local result = reactor.run_process(uv.exepath(), { wrapper_script, package.path, package.cpath, case.mode })
      self:assert_equal(0, result.code, case.mode)
      self:assert_equal(case.out, result.stdout, case.mode)
      self:assert_equal(case.err, result.stderr, case.mode)
    end
  end)
end

function T:test_cwd_sets_the_working_directory_of_the_child()
  local dir = assert(uv.fs_mkdtemp(uv.os_tmpdir() .. "/hecate-cwd-XXXXXX"))
  local reported = run(self, function()
    local process = child("cwd", { ipc = true, cwd = dir })
    local value = process.ipc:receive()
    process.ipc:close()
    process:wait()
    return value
  end)
  self:assert_equal(uv.fs_realpath(dir), reported)
  uv.fs_rmdir(dir)
end

function T:test_env_overrides_an_inherited_variable()
  uv.os_setenv("HECATE_TEST_INHERITED", "from the parent")
  local values = run(self, function()
    local result = {}
    for index, env in ipairs({ {}, { HECATE_TEST_INHERITED = "overridden" } }) do
      local process = child("getenv", { ipc = true, args = { "HECATE_TEST_INHERITED" }, env = env })
      result[index] = process.ipc:receive()
      process.ipc:close()
      process:wait()
    end
    return result
  end)
  uv.os_unsetenv("HECATE_TEST_INHERITED")
  self:assert_equal("from the parent", values[1])
  self:assert_equal("overridden", values[2])
end

function T:test_the_marker_and_the_message_pipe_do_not_leak_into_grandchildren()
  local report = run(self, function()
    local process = child("grandchild_env", { ipc = true })
    local value = process.ipc:receive()
    process.ipc:close()
    process:wait()
    return value
  end)
  self:assert_equal("0 unset", report) -- plain grandchild: no parent peer; run_process child: no marker
end

function T:test_a_grandchild_does_not_keep_the_message_pipe_open()
  local ended = run(self, function()
    local process = child("grandchild_fd", { ipc = true })
    local peer = process.ipc --[[@as hecate.reactor.Peer]]
    local pid = tonumber(peer:receive())
    -- The worker exited; if the long-lived grandchild inherited descriptor 3 the end of the
    -- message pipe would only show when it exits (60 s): the deadline turns that into a failure.
    local ok, message = pcall(reactor.deadline, 5, peer.receive, peer)
    uv.kill(pid, "sigkill")
    process:wait()
    peer:close()
    return { ok = ok, message = message }
  end)
  self:assert_true(ended.ok, tostring(ended.message))
  self:assert_nil(ended.message)
end

function T:test_the_parent_peer_is_the_same_on_every_call()
  local answer = run(self, function()
    local process = child("parent_twice", { ipc = true })
    local value = process.ipc:receive()
    process.ipc:close()
    process:wait()
    return value
  end)
  self:assert_equal("same", answer)
end

function T:test_a_failed_spawn_with_a_message_pipe_leaves_no_handle()
  run(self, function() -- `run` compares the number of open handles
    local err = self:assert_error(function() reactor.spawn("hecate-no-such-program-xyz", {}, { ipc = true }) end)
    self:assert_true(core.is_instance_of(err, reactor.IoError))
  end)
end

function T:test_a_running_child_keeps_the_loop_alive_so_waiting_for_it_is_no_deadlock()
  local before = reactor.Reactor.open_handles()
  local status = reactor.run(function()
    -- Nothing else is scheduled and there is no timer: only the process handle keeps libuv running.
    local process = reactor.spawn(uv.exepath(), { "-e", "require(\"luv\").sleep(100); os.exit(3)" }, { env = lua_env() })
    self:assert_true(process:is_running())
    return process:wait()
  end)
  self:assert_equal(3, status.code)
  self:assert_equal(before, reactor.Reactor.open_handles())
end

function T:test_kill_validates_the_signal_and_accepts_a_number()
  run(self, function()
    local process = child("echo", { ipc = true })
    local err = self:assert_error(function() process:kill("sigbogus") end)
    self:assert_true(core.is_instance_of(err, reactor.IoError), tostring(err))
    err = self:assert_error(function() process:kill(100000) end)
    self:assert_true(core.is_instance_of(err, reactor.IoError), tostring(err))
    self:assert_true(process:is_running())
    process:kill(9) -- SIGKILL by number (also supported on Windows)
    process:wait()
    process.ipc:close()
    self:assert_false(process:is_running())
  end)
end

function T:test_kill_treats_a_vanished_process_as_success_and_reports_other_failures()
  local function stub(failure)
    return { is_closing = function() return false end, kill = function() return nil, failure end,
      close = function() end }
  end
  local gone = reactor.Process(stub("ESRCH: no such process"), 1)
  gone:kill() -- the child exited between the last check and the signal: nothing to report
  local denied = reactor.Process(stub("EPERM: operation not permitted"), 2)
  local err = self:assert_error(function() denied:kill() end)
  self:assert_true(core.is_instance_of(err, reactor.IoError), tostring(err))
  self:assert_equal("EPERM", err.context.errno)
end

function T:test_a_child_hands_a_stream_over_to_the_parent()
  local text = run(self, function()
    local listener <close> = reactor.listen_tcp("127.0.0.1", 0)
    local process = child("connect", { ipc = true, args = { tostring(listener:local_address().port) } })
    local peer = process.ipc --[[@as hecate.reactor.Peer]]
    local server <close> = listener:accept()
    local message, handed = peer:receive()
    self:assert_equal("connected", message)
    local stream <close> = handed --[[@as hecate.reactor.TcpStream]]
    stream:write("from the parent") -- through the child's socket, now owned here
    local received = server:read()
    peer:send("taken") -- acknowledgement: the child may exit now
    peer:close()
    process:wait()
    return received
  end)
  self:assert_equal("from the parent", text)
end

function T:test_hand_overs_queue_up_while_the_child_is_not_receiving()
  local count = 200
  local replies = run(self, function()
    local listener <close> = reactor.listen_tcp("127.0.0.1", 0, { backlog = 256 })
    local port = listener:local_address().port
    local process = child("delayed", { ipc = true, args = { tostring(count) } })
    local peer = process.ipc --[[@as hecate.reactor.Peer]]
    local clients = {}
    for index = 1, count do
      clients[index] = reactor.connect_tcp("127.0.0.1", port)
      local accepted = listener:accept()
      peer:send("c" .. index, accepted)
    end
    local replies = {}
    for index = 1, count do replies[index] = clients[index]:read() end
    local done = peer:receive()
    for _, client in ipairs(clients) do client:close() end
    peer:close()
    process:wait()
    return { replies = replies, done = done }
  end)
  self:assert_equal("done", replies.done)
  for index = 1, count do self:assert_equal("c" .. index, replies.replies[index]) end
end

function T:test_back_to_back_hand_overs_keep_every_stream_with_its_message()
  local result = run(self, function()
    local listener <close> = reactor.listen_tcp("127.0.0.1", 0)
    local port = listener:local_address().port
    local process = child("handover", { ipc = true })
    local peer = process.ipc --[[@as hecate.reactor.Peer]]
    local function pair()
      local client = reactor.connect_tcp("127.0.0.1", port)
      return client, listener:accept()
    end
    local c1, s1 = pair()
    local c2, s2 = pair()
    local c3, s3 = pair()
    local c4, s4 = pair()
    local big = ("b"):rep(500000)
    peer:send("one", s1)
    peer:send("two", s2)
    peer:send("plain")
    peer:send("three", s3)
    peer:send(big, s4)
    local replies = {}
    for index = 1, 5 do replies[index] = peer:receive() end
    local acks = { c1:read(), c2:read(), c3:read() }
    local last = ""
    while #last < #"ack:" + #big do
      local chunk = c4:read()
      if chunk == nil then break end
      last = last .. chunk
    end
    for _, client in ipairs({ c1, c2, c3, c4 }) do client:close() end
    peer:close()
    process:wait()
    return { replies = replies, acks = acks, big_ok = last == "ack:" .. big }
  end)
  self:assert_equal("3:stream", result.replies[1])
  self:assert_equal("3:stream", result.replies[2])
  self:assert_equal("5:plain", result.replies[3])
  self:assert_equal("5:stream", result.replies[4])
  self:assert_equal("500000:stream", result.replies[5])
  self:assert_equal("ack:one", result.acks[1])
  self:assert_equal("ack:two", result.acks[2])
  self:assert_equal("ack:three", result.acks[3])
  self:assert_true(result.big_ok)
end

return T
