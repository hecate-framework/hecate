local test = require("harness.test")
local core = require("hecate.core")
local reactor = require("hecate.reactor")
local T = test.Case("TcpTest")

local LOOPBACK = "127.0.0.1"

--- Runs `fn(listener, port)` on a reactor with a listener on an ephemeral loopback port, then
--- checks that no libuv handle is left open.
local function with_listener(self, fn, options)
  local before = reactor.Reactor.open_handles()
  local result = reactor.run(function()
    local listener <close> = reactor.tcp_listen(LOOPBACK, 0, options)
    return fn(listener, listener:local_address().port)
  end)
  self:assert_equal(before, reactor.Reactor.open_handles())
  return result
end

--- Polls `condition` (bounded, no fixed delay) until it holds: used to wait for a coroutine to park.
local function wait_until(self, condition, what)
  for _ = 1, 5000 do
    if condition() then return end
    reactor.sleep(0.001)
  end
  self:fail("timed out waiting for " .. what)
end

--- A loopback port nobody listens on: binds an ephemeral port and closes the listener at once.
--- Another process may take the port before the test connects: callers retry once on success.
local function closed_port()
  return reactor.run(function()
    local listener = reactor.tcp_listen(LOOPBACK, 0)
    local port = listener:local_address().port
    listener:close()
    return port
  end)
end

local function errno_of(self, fn)
  local err = self:assert_error(fn)
  self:assert_true(core.is_instance_of(err, reactor.TransportError), tostring(err))
  self:assert_true(core.is_instance_of(err, core.NetworkError), tostring(err))
  self:assert_false(core.is_instance_of(err, reactor.IoError), tostring(err))
  return err.context.errno, err
end

function T:test_echo_round_trip_with_addresses()
  local result = with_listener(self, function(listener, port)
    local server = reactor.fork(function()
      local peer <close> = listener:accept()
      local data = peer:read()
      peer:write(data:upper())
      return peer:peer_address().ip
    end)
    local client <close> = reactor.tcp_connect(LOOPBACK, port)
    client:write("hello")
    local reply = client:read()
    self:assert_equal(port, client:peer_address().port)
    self:assert_equal(LOOPBACK, client:local_address().ip)
    self:assert_equal("inet", client:peer_address().family)
    return { reply = reply, peer_ip = server:value() }
  end)
  self:assert_equal("HELLO", result.reply)
  self:assert_equal(LOOPBACK, result.peer_ip)
end

function T:test_read_returns_nil_at_end_of_stream_and_honours_max()
  with_listener(self, function(listener, port)
    local done = reactor.Channel(1)
    reactor.fork(function()
      local peer <close> = listener:accept()
      peer:write("abcdef")
      peer:shutdown()
      done:receive() -- keeps the peer open: the end of stream comes from the half-close
    end)
    local client <close> = reactor.tcp_connect(LOOPBACK, port)
    local got = {}
    while true do
      local chunk = client:read(4)
      if chunk == nil then break end
      self:assert_true(#chunk >= 1 and #chunk <= 4)
      got[#got + 1] = chunk
    end
    self:assert_equal("abcdef", table.concat(got))
    self:assert_nil(client:read()) -- stays at end of stream
    done:send(true)
  end)
end

function T:test_shutdown_is_a_half_close_that_keeps_the_stream_readable()
  local reply = with_listener(self, function(listener, port)
    reactor.fork(function()
      local peer <close> = listener:accept()
      local request = {}
      while true do
        local chunk = peer:read()
        if chunk == nil then break end
        request[#request + 1] = chunk
      end
      peer:write("got " .. table.concat(request))
    end)
    local client <close> = reactor.tcp_connect(LOOPBACK, port)
    client:write("ping")
    client:shutdown()
    return client:read()
  end)
  self:assert_equal("got ping", reply)
end

function T:test_close_is_idempotent_and_closes_on_scope_exit()
  with_listener(self, function(listener, port)
    local stream
    do
      local client <close> = reactor.tcp_connect(LOOPBACK, port)
      stream = client
      self:assert_false(client:is_closed())
    end
    self:assert_true(stream:is_closed())
    stream:close()
    stream:close()
    local errno = errno_of(self, function() stream:write("x") end)
    self:assert_equal("EBADF", errno)
    errno = errno_of(self, function() stream:read() end)
    self:assert_equal("EBADF", errno)
    listener:close()
    listener:close()
    self:assert_true(listener:is_closed())
  end)
end

function T:test_close_by_the_peer_ends_the_stream_and_close_wakes_a_pending_read()
  with_listener(self, function(listener, port)
    reactor.fork(function()
      local peer = listener:accept()
      peer:close()
    end)
    local client <close> = reactor.tcp_connect(LOOPBACK, port)
    self:assert_nil(client:read())
  end)
  with_listener(self, function(listener, port)
    local release = reactor.Channel(1)
    reactor.fork(function()
      local peer <close> = listener:accept()
      release:receive()
    end)
    local client = reactor.tcp_connect(LOOPBACK, port)
    local closer = reactor.fork(function()
      wait_until(self, function() return client._reading end, "the read to park") ---@diagnostic disable-line: invisible
      client:close()
    end)
    local errno = errno_of(self, function() client:read() end)
    self:assert_equal("ECANCELED", errno)
    closer:value()
    release:send(true)
  end)
end

function T:test_connect_refused_raises_transport_error_with_errno()
  local before = reactor.Reactor.open_handles()
  local errno, err
  for _ = 1, 2 do -- the port may have been taken in between: one retry on an unexpected success
    local port = closed_port()
    local ok, failure = pcall(reactor.run, function() reactor.tcp_connect(LOOPBACK, port) end)
    if not ok then
      self:assert_true(core.is_instance_of(failure, reactor.TransportError), tostring(failure))
      errno, err = failure.context.errno, failure
      break
    end
  end
  self:assert_not_nil(err, "the connection to a closed port succeeded twice")
  self:assert_equal("ECONNREFUSED", errno)
  self:assert_equal("connect", err.context.operation:match("^connect"))
  self:assert_equal(before, reactor.Reactor.open_handles())
end

function T:test_a_host_name_is_not_resolved()
  local errno = errno_of(self, function()
    reactor.run(function() reactor.tcp_connect("localhost", 80) end)
  end)
  self:assert_equal("EINVAL", errno)
end

function T:test_listen_on_a_used_port_raises_eaddrinuse()
  with_listener(self, function(_, port)
    local errno = errno_of(self, function() reactor.tcp_listen(LOOPBACK, port) end)
    self:assert_equal("EADDRINUSE", errno)
  end)
end

function T:test_cancelled_connect_leaks_no_handle()
  with_listener(self, function(_, port)
    -- The connector starts and suspends; the canceller runs before libuv completes it.
    local connector = reactor.fork(function() return reactor.tcp_connect(LOOPBACK, port) end)
    reactor.fork(function() connector:cancel() end)
    self:assert_error(function() connector:value() end)
    self:assert_equal("cancelled", connector:state())
  end)
end

function T:test_connect_cancelled_before_it_starts()
  with_listener(self, function(_, port)
    local connector = reactor.fork(function() return reactor.tcp_connect(LOOPBACK, port) end)
    connector:cancel()
    self:assert_error(function() connector:value() end)
    self:assert_equal("cancelled", connector:state())
  end)
end

function T:test_cancelled_accept_keeps_the_listener_and_queued_connections()
  with_listener(self, function(listener, port)
    local ok, err = pcall(reactor.deadline, 0.02, function() return listener:accept() end)
    self:assert_false(ok)
    self:assert_true(core.is_instance_of(err, core.DeadlineExceededError))
    -- The listener still works, and a connection that arrived with nobody accepting is kept.
    local client <close> = reactor.tcp_connect(LOOPBACK, port)
    wait_until(self, function() return listener._incoming > 0 end, "the connection to be queued") ---@diagnostic disable-line: invisible
    local peer <close> = listener:accept()
    client:write("late")
    self:assert_equal("late", peer:read())
  end)
end

function T:test_closing_the_listener_wakes_a_pending_accept()
  with_listener(self, function(listener)
    local acceptor = reactor.fork(function()
      local ok, err = pcall(listener.accept, listener)
      return ok, err
    end)
    wait_until(self, function() return listener._accepting end, "the acceptor to park") ---@diagnostic disable-line: invisible
    listener:close()
    local ok, err = acceptor:value()
    self:assert_false(ok)
    self:assert_equal("ECANCELED", err.context.errno)
  end)
end

function T:test_cancelled_read_keeps_the_stream_and_loses_no_data()
  with_listener(self, function(listener, port)
    local release = reactor.Channel(1)
    local server = reactor.fork(function()
      local peer <close> = listener:accept()
      release:receive() -- silent until the deadline has expired
      peer:write("after")
    end)
    local client <close> = reactor.tcp_connect(LOOPBACK, port)
    local ok, err = pcall(reactor.deadline, 0.02, function() return client:read() end)
    self:assert_false(ok)
    self:assert_true(core.is_instance_of(err, core.DeadlineExceededError))
    release:send(true)
    self:assert_equal("after", client:read())
    server:value()
  end)
end

function T:test_data_arriving_as_the_read_is_cancelled_is_kept()
  with_listener(self, function(listener, port)
    local peer
    local accepted = reactor.Channel(1)
    reactor.fork(function() peer = listener:accept(); accepted:send(true) end)
    local client <close> = reactor.tcp_connect(LOOPBACK, port)
    accepted:receive()
    local reader = reactor.fork(function() return client:read() end)
    -- The writer sends and the canceller cancels in the same turn: libuv may deliver the
    -- data after the reader was withdrawn.
    reactor.fork(function() peer:write("kept"); reader:cancel() end)
    -- Either the read won the race and returned the data, or it was withdrawn and the data
    -- stays available: in both cases it is delivered exactly once.
    local ok, value = pcall(reader.value, reader)
    if ok then
      self:assert_equal("kept", value)
    else
      self:assert_equal("kept", client:read())
    end
    peer:close()
  end)
end

function T:test_write_applies_back_pressure_and_cancelled_write_closes_the_stream()
  with_listener(self, function(listener, port)
    local release = reactor.Channel(1)
    reactor.fork(function()
      local peer <close> = listener:accept()
      release:receive() -- never reads: the peer's buffers fill up, until the test is done
    end)
    local client = reactor.tcp_connect(LOOPBACK, port)
    -- The peer never reads, so a stream of large writes must end up waiting (Windows loopback
    -- buffers far more than Linux before a write has to wait). A write that never waited would
    -- let the loop finish and `ok` be true: the deadline expiring is the proof that it suspended.
    local big = string.rep("x", 4 * 1024 * 1024)
    local ok, err = pcall(reactor.deadline, 0.05, function()
      for _ = 1, 4096 do client:write(big); reactor.sleep(0) end
    end)
    self:assert_false(ok)
    self:assert_true(core.is_instance_of(err, core.DeadlineExceededError), tostring(err))
    self:assert_true(client:is_closed())
    release:send(true)
  end)
end

function T:test_write_to_a_reset_peer_raises_io_error()
  with_listener(self, function(listener, port)
    local closed = reactor.Channel(1)
    reactor.fork(function()
      local peer = listener:accept()
      peer:close()
      closed:send(true)
    end)
    local client <close> = reactor.tcp_connect(LOOPBACK, port)
    closed:receive()
    local errno = errno_of(self, function()
      -- The first writes may sit in kernel buffers: write until the failure shows.
      for _ = 1, 2000 do client:write(string.rep("x", 65536)); reactor.sleep(0) end
    end)
    -- Windows reports the aborted connection as ECONNABORTED or ECANCELED.
    self:assert_true(errno == "EPIPE" or errno == "ECONNRESET" or errno == "ECONNABORTED"
      or errno == "ECANCELED", tostring(errno))
  end)
end

function T:test_options_have_documented_defaults_and_validate()
  with_listener(self, function(listener, port)
    local release = reactor.Channel(1)
    reactor.fork(function() local peer <close> = listener:accept(); release:receive() end)
    local client <close> = reactor.tcp_connect(LOOPBACK, port, { nodelay = false, keepalive = true, keepalive_delay = 30 })
    client:set_nodelay(true)
    client:set_keepalive(false)
    -- The peer closes only now (some systems refuse socket options on a reset connection); the end
    -- of stream shows that it accepted, so the listener is not closed mid-accept.
    release:send(true)
    self:assert_nil(client:read())
  end, { backlog = 16, nodelay = true, keepalive = true })
  local err = self:assert_error(function()
    reactor.run(function() reactor.tcp_connect(LOOPBACK, 1, { nodelays = true }) end)
  end)
  self:assert_true(core.is_instance_of(err, core.ArgumentError))
  err = self:assert_error(function()
    reactor.run(function() reactor.tcp_connect(LOOPBACK, 70000) end)
  end)
  self:assert_true(core.is_instance_of(err, core.ArgumentError))
  -- keepalive_delay is a positive integer number of seconds (libuv takes an unsigned integer)
  for _, delay in ipairs({ 0, -1, 1.5, "30", true }) do
    err = self:assert_error(function()
      reactor.run(function() reactor.tcp_connect(LOOPBACK, 1, { keepalive_delay = delay }) end)
    end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(delay))
    self:assert_true(tostring(err):find("keepalive_delay", 1, true) ~= nil, tostring(err))
  end
  with_listener(self, function(listener, port)
    local release = reactor.Channel(1)
    reactor.fork(function() local peer <close> = listener:accept(); release:receive() end)
    local client <close> = reactor.tcp_connect(LOOPBACK, port)
    for _, call in ipairs({
      function() client:set_keepalive(true, 0) end,
      function() client:set_keepalive(true, 2.5) end,
      function() client:set_keepalive("yes") end,
      function() client:set_nodelay(1) end,
    }) do
      self:assert_true(core.is_instance_of(self:assert_error(call), core.ArgumentError))
    end
    client:set_keepalive(true, 5)
    release:send(true)
    self:assert_nil(client:read())
  end)
end

function T:test_concurrent_streams()
  local total = with_listener(self, function(listener, port)
    reactor.fork(function()
      for _ = 1, 20 do
        local peer = listener:accept()
        reactor.fork(function()
          local stream <close> = peer
          while true do
            local chunk = stream:read()
            if chunk == nil then return end
            stream:write(chunk)
          end
        end)
      end
    end)
    local futures = {}
    for i = 1, 20 do
      futures[i] = reactor.fork(function()
        local client <close> = reactor.tcp_connect(LOOPBACK, port)
        client:write(tostring(i))
        return tonumber(client:read())
      end)
    end
    local sum = 0
    for i = 1, 20 do sum = sum + futures[i]:value() end
    return sum
  end)
  self:assert_equal(210, total)
end

function T:test_a_second_concurrent_read_is_refused()
  with_listener(self, function(listener, port)
    local release = reactor.Channel(1)
    reactor.fork(function() local peer <close> = listener:accept(); release:receive() end)
    local client <close> = reactor.tcp_connect(LOOPBACK, port)
    local first = reactor.fork(function() return client:read() end)
    wait_until(self, function() return client._reading end, "the first read to park") ---@diagnostic disable-line: invisible
    local err = self:assert_error(function() client:read() end)
    self:assert_true(tostring(err):find("another coroutine is already reading", 1, true) ~= nil, tostring(err))
    first:cancel()
    release:send(true)
  end)
end

function T:test_operations_require_a_managed_coroutine()
  for _, fn in ipairs({
    function() reactor.tcp_connect(LOOPBACK, 1) end,
    function() reactor.tcp_listen(LOOPBACK, 0) end,
  }) do
    local err = self:assert_error(fn)
    self:assert_true(core.is_instance_of(err, core.NonYieldableContextError))
  end
end

function T:test_transport_on_a_virtual_clock_is_refused()
  local err = self:assert_error(function()
    reactor.Reactor({ clock = "virtual" }):run(function() reactor.tcp_listen(LOOPBACK, 0) end)
  end)
  self:assert_true(core.is_instance_of(err, core.Error))
end

return T
