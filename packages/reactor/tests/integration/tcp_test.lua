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
    reactor.fork(function()
      local peer <close> = listener:accept()
      peer:write("abcdef")
      peer:shutdown()
      reactor.sleep(0.05) -- keeps the peer open: the end of stream comes from the half-close
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
      reactor.sleep(0.02)
      peer:close()
    end)
    local client <close> = reactor.tcp_connect(LOOPBACK, port)
    self:assert_nil(client:read())
  end)
  with_listener(self, function(listener, port)
    reactor.fork(function()
      local peer <close> = listener:accept()
      reactor.sleep(0.2)
    end)
    local client = reactor.tcp_connect(LOOPBACK, port)
    local closer = reactor.fork(function() reactor.sleep(0.02); client:close() end)
    local errno = errno_of(self, function() client:read() end)
    self:assert_equal("ECANCELED", errno)
    closer:value()
  end)
end

function T:test_connect_refused_raises_io_error_with_errno()
  local before = reactor.Reactor.open_handles()
  -- Binds then closes a listener to learn a port nobody listens on.
  local port = reactor.run(function()
    local listener = reactor.tcp_listen(LOOPBACK, 0)
    local p = listener:local_address().port
    listener:close()
    return p
  end)
  local errno, err = errno_of(self, function()
    reactor.run(function() reactor.tcp_connect(LOOPBACK, port) end)
  end)
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
    reactor.sleep(0.02)
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
    reactor.sleep(0.01)
    listener:close()
    local ok, err = acceptor:value()
    self:assert_false(ok)
    self:assert_equal("ECANCELED", err.context.errno)
  end)
end

function T:test_cancelled_read_keeps_the_stream_and_loses_no_data()
  with_listener(self, function(listener, port)
    local server = reactor.fork(function()
      local peer <close> = listener:accept()
      reactor.sleep(0.1)
      peer:write("after")
      reactor.sleep(0.02)
    end)
    local client <close> = reactor.tcp_connect(LOOPBACK, port)
    local ok, err = pcall(reactor.deadline, 0.02, function() return client:read() end)
    self:assert_false(ok)
    self:assert_true(core.is_instance_of(err, core.DeadlineExceededError))
    self:assert_equal("after", client:read())
    server:value()
  end)
end

function T:test_data_arriving_as_the_read_is_cancelled_is_kept()
  with_listener(self, function(listener, port)
    local peer
    reactor.fork(function() peer = listener:accept() end)
    local client <close> = reactor.tcp_connect(LOOPBACK, port)
    reactor.sleep(0.02)
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
    reactor.fork(function()
      local peer <close> = listener:accept()
      reactor.sleep(0.3) -- never reads: the peer's buffers fill up
    end)
    local client = reactor.tcp_connect(LOOPBACK, port)
    -- Windows loopback buffers far more before a write has to wait.
    local windows = package.config:sub(1, 1) == "\\"
    local big = string.rep("x", (windows and 256 or 32) * 1024 * 1024)
    local started = reactor.now()
    local ok, err = pcall(reactor.deadline, 0.05, function() client:write(big) end)
    self:assert_false(ok)
    self:assert_true(core.is_instance_of(err, core.DeadlineExceededError))
    self:assert_true(reactor.now() - started < 0.25, "the write must have suspended, not completed")
    self:assert_true(client:is_closed())
  end)
end

function T:test_write_to_a_reset_peer_raises_io_error()
  with_listener(self, function(listener, port)
    reactor.fork(function()
      local peer = listener:accept()
      peer:close()
    end)
    local client <close> = reactor.tcp_connect(LOOPBACK, port)
    reactor.sleep(0.05)
    local errno = errno_of(self, function()
      for _ = 1, 50 do client:write(string.rep("x", 65536)); reactor.sleep(0) end
    end)
    -- Windows reports the aborted connection as ECONNABORTED or ECANCELED.
    self:assert_true(errno == "EPIPE" or errno == "ECONNRESET" or errno == "ECONNABORTED"
      or errno == "ECANCELED", tostring(errno))
  end)
end

function T:test_options_have_documented_defaults_and_validate()
  with_listener(self, function(listener, port)
    reactor.fork(function() local peer <close> = listener:accept(); reactor.sleep(0.02) end)
    local client <close> = reactor.tcp_connect(LOOPBACK, port, { nodelay = false, keepalive = true, keepalive_delay = 30 })
    client:set_nodelay(true)
    client:set_keepalive(false)
    -- Wait for the peer to accept and close, so the listener is not closed mid-accept.
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
    reactor.fork(function() local peer <close> = listener:accept(); reactor.sleep(0.1) end)
    local client <close> = reactor.tcp_connect(LOOPBACK, port)
    local first = reactor.fork(function() return client:read() end)
    reactor.sleep(0.01)
    self:assert_error(function() client:read() end)
    first:cancel()
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
