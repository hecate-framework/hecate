---@diagnostic disable: param-type-mismatch  -- the tests pass invalid arguments on purpose
local test = require("harness.test")
local core = require("hecate.core")
local reactor = require("hecate.reactor")
local net = require("hecate.net")
local T = test.Case("NetTcpTest")

local LOOPBACK = "127.0.0.1"

--- Runs `fn(listener, port)` on a reactor with a listener on an ephemeral loopback port, then
--- checks that no libuv handle is left open.
local function with_listener(self, fn, options)
  local before = reactor.Reactor.open_handles()
  local result = reactor.run(function()
    local listener <close> = net.listen(LOOPBACK, 0, options)
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

function T:test_tcp_stream_implements_the_stream_interface()
  self:assert_true(core.implements(net.TcpStream, net.Stream))
  self:assert_true(core.is_class(net.TcpListener))
end

function T:test_echo_through_buffered_reader_and_writer()
  local lines = with_listener(self, function(listener, port)
    reactor.fork(function()
      local peer <close> = listener:accept()
      local reader, writer = peer:reader(), peer:writer()
      while true do
        local line = reader:read_line()
        if line == nil then break end
        writer:write(line:upper() .. "\n")
        writer:flush()
      end
    end)
    local client <close> = net.connect(LOOPBACK, port)
    local reader, writer = client:reader(), client:writer()
    local got = {}
    for _, word in ipairs({ "alpha", "beta", "gamma" }) do
      writer:write(word)
      writer:write("\r\n") -- a line is never split by the writer
      writer:flush()
      got[#got + 1] = reader:read_line()
    end
    return got
  end)
  self:assert_equal("ALPHA,BETA,GAMMA", table.concat(lines, ","))
end

function T:test_a_large_payload_arrives_whole_through_the_buffered_layer()
  local payload = string.rep("0123456789abcdef", 64 * 1024) -- 1 MiB, far above any chunk size
  local received = with_listener(self, function(listener, port)
    reactor.fork(function()
      local peer <close> = listener:accept()
      local writer = peer:writer({ capacity = 1000 })
      writer:write(payload)
      writer:flush()
      peer:shutdown()
      reactor.sleep(0.05)
    end)
    local client <close> = net.connect(LOOPBACK, port)
    return client:reader():read_exact(#payload)
  end)
  self:assert_equal(#payload, #received)
  self:assert_true(received == payload)
end

function T:test_a_short_stream_raises_end_of_stream_and_keeps_the_bytes()
  with_listener(self, function(listener, port)
    reactor.fork(function()
      local peer <close> = listener:accept()
      peer:write("abc")
      peer:shutdown()
      reactor.sleep(0.05)
    end)
    local client <close> = net.connect(LOOPBACK, port)
    local reader = client:reader()
    local err = self:assert_error(function() reader:read_exact(10) end)
    self:assert_true(core.is_instance_of(err, net.EndOfStreamError))
    self:assert_equal(3, reader:buffered()) -- the partial read did not leak
    self:assert_equal("abc", reader:read_some())
    self:assert_nil(reader:read_some())
  end)
end

function T:test_end_of_stream_is_nil()
  with_listener(self, function(listener, port)
    reactor.fork(function()
      local peer <close> = listener:accept()
      peer:write("x")
    end)
    local client <close> = net.connect(LOOPBACK, port)
    self:assert_equal("x", client:read())
    self:assert_nil(client:read())
  end)
end

function T:test_half_close_keeps_the_stream_readable()
  local reply = with_listener(self, function(listener, port)
    reactor.fork(function()
      local peer <close> = listener:accept()
      local reader = peer:reader()
      -- The delimiter never comes: the client's half-close ends the stream, and the bytes
      -- received before it stay in the reader instead of leaking out as a partial record.
      local ok, err = pcall(reader.read_until, reader, "\0")
      peer:write(("%s %s %d"):format(tostring(ok), core.is_instance_of(err, net.EndOfStreamError), reader:buffered()))
    end)
    local client <close> = net.connect(LOOPBACK, port)
    local writer = client:writer()
    writer:write("ping")
    writer:flush()
    client:shutdown()
    return client:read()
  end)
  self:assert_equal("false true 4", reply)
end

function T:test_close_is_idempotent_and_runs_at_the_end_of_a_close_scope()
  with_listener(self, function(listener, port)
    local stream
    do
      local client <close> = net.connect(LOOPBACK, port)
      stream = client
      self:assert_false(client:is_closed())
      self:assert_equal(port, client:peer_address().port)
      self:assert_equal(LOOPBACK, client:local_address().ip)
    end
    self:assert_true(stream:is_closed())
    stream:close()
    stream:close()
    self:assert_equal("EBADF", errno_of(self, function() stream:write("x") end))
    self:assert_equal("EBADF", errno_of(self, function() stream:read() end))
  end)
end

function T:test_close_runs_when_the_scope_is_cancelled()
  with_listener(self, function(listener, port)
    local stream
    local task = reactor.fork(function()
      local client <close> = net.connect(LOOPBACK, port)
      stream = client
      client:read() -- the server never writes
    end)
    reactor.fork(function() local peer <close> = listener:accept(); reactor.sleep(0.2) end)
    reactor.sleep(0.03)
    task:cancel()
    self:assert_error(function() task:value() end)
    self:assert_true(stream:is_closed())
  end)
end

function T:test_the_listener_is_closed_by_its_scope_and_wakes_a_pending_accept()
  with_listener(self, function(listener)
    local acceptor = reactor.fork(function() return pcall(listener.accept, listener) end)
    reactor.sleep(0.01)
    listener:close()
    listener:close()
    self:assert_true(listener:is_closed())
    local ok, err = acceptor:value()
    self:assert_false(ok)
    self:assert_equal("ECANCELED", err.context.errno)
  end)
end

function T:test_a_deadline_expires_on_a_silent_peer_and_the_stream_stays_usable()
  with_listener(self, function(listener, port)
    local server = reactor.fork(function()
      local peer <close> = listener:accept()
      reactor.sleep(0.1)
      peer:write("late\n")
      reactor.sleep(0.02)
    end)
    local client <close> = net.connect(LOOPBACK, port)
    local reader = client:reader()
    local started = reactor.now()
    local ok, err = pcall(reactor.deadline, 0.03, function() return reader:read_line() end)
    self:assert_false(ok)
    self:assert_true(core.is_instance_of(err, core.DeadlineExceededError))
    self:assert_true(reactor.now() - started < 0.09)
    -- Nothing was lost: the cancelled read left the stream and the reader intact.
    self:assert_false(client:is_closed())
    self:assert_equal("late", reader:read_line())
    server:value()
  end)
end

function T:test_a_deadline_bounds_connect_and_accept()
  with_listener(self, function(listener)
    local ok, err = pcall(reactor.deadline, 0.02, function() return listener:accept() end)
    self:assert_false(ok)
    self:assert_true(core.is_instance_of(err, core.DeadlineExceededError))
    self:assert_false(listener:is_closed())
  end)
  with_listener(self, function(_, port)
    local client <close> = reactor.deadline(5, net.connect, "localhost", port, { family = "inet" })
    self:assert_equal(port, client:peer_address().port)
  end)
end

function T:test_a_reset_peer_raises_io_error_and_never_a_partial_result()
  with_listener(self, function(listener, port)
    reactor.fork(function()
      local peer = listener:accept()
      peer:close()
    end)
    local client <close> = net.connect(LOOPBACK, port)
    reactor.sleep(0.05)
    local errno = errno_of(self, function()
      local writer = client:writer({ capacity = 65536 })
      for _ = 1, 50 do writer:write(string.rep("x", 65536)); reactor.sleep(0) end
      writer:flush()
    end)
    self:assert_true(errno == "EPIPE" or errno == "ECONNRESET", tostring(errno))
  end)
end

function T:test_a_failed_flush_poisons_the_writer_over_a_tcp_stream()
  with_listener(self, function(listener, port)
    reactor.fork(function() local peer = listener:accept(); peer:close() end)
    local client <close> = net.connect(LOOPBACK, port)
    reactor.sleep(0.05)
    local writer = client:writer({ capacity = 1 })
    local _, first = pcall(function()
      for _ = 1, 50 do writer:write(string.rep("x", 65536)); reactor.sleep(0) end
    end)
    self:assert_true(core.is_instance_of(first, reactor.TransportError))
    self:assert_true(core.is_instance_of(first, core.NetworkError))
    local second = self:assert_error(function() writer:write("y") end)
    self:assert_true(first == second) -- the same failure, no bytes after a gap
  end)
end

function T:test_connect_refused_raises_io_error()
  local port = reactor.run(function()
    local listener = net.listen(LOOPBACK, 0)
    local p = listener:local_address().port
    listener:close()
    return p
  end)
  local errno = errno_of(self, function()
    reactor.run(function() net.connect(LOOPBACK, port) end)
  end)
  self:assert_equal("ECONNREFUSED", errno)
end

function T:test_connect_and_listen_resolve_host_names()
  local reply = reactor.run(function()
    local listener <close> = net.listen("localhost", 0, { family = "inet" })
    local port = listener:local_address().port
    reactor.fork(function()
      local peer <close> = listener:accept()
      peer:write("hi")
    end)
    local client <close> = net.connect("localhost", port, { family = "inet" })
    return client:read()
  end)
  self:assert_equal("hi", reply)
end

function T:test_an_unknown_host_raises_io_error_and_leaks_nothing()
  local before = reactor.Reactor.open_handles()
  local _, err = errno_of(self, function()
    reactor.run(function() net.connect("no-such-host.invalid", 80) end)
  end)
  self:assert_equal("resolve", err.context.operation:match("^resolve"))
  self:assert_equal(before, reactor.Reactor.open_handles())
end

function T:test_arguments_and_options_are_validated()
  for _, fn in ipairs({
    function() net.connect(42, 80) end,
    function() net.connect("", 80) end,
    function() net.connect(LOOPBACK, 70000) end,
    function() net.connect(LOOPBACK, 80, { nodelays = true }) end,
    ---@diagnostic disable-next-line: assign-type-mismatch  -- an invalid family is the point of the test
    function() net.connect(LOOPBACK, 80, { family = "ipx" }) end,
    function() net.listen(LOOPBACK, 0, "x") end,
    function() net.listen(LOOPBACK, 0, { backlog = 0 }) end,
  }) do
    local err = self:assert_error(function() reactor.run(fn) end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
  end
end

function T:test_options_reach_the_transport()
  with_listener(self, function(listener, port)
    reactor.fork(function() local peer <close> = listener:accept(); reactor.sleep(0.02) end)
    local client <close> = net.connect(LOOPBACK, port, { nodelay = false, keepalive = true, keepalive_delay = 30 })
    client:set_nodelay(true)
    client:set_keepalive(false)
  end, { backlog = 16, keepalive = true })
end

function T:test_concurrent_connections_do_not_interleave()
  local total = with_listener(self, function(listener, port)
    reactor.fork(function()
      for _ = 1, 20 do
        local peer = listener:accept()
        reactor.fork(function()
          local stream <close> = peer
          local reader, writer = stream:reader(), stream:writer()
          local line = reader:read_line()
          writer:write(line .. "\n")
          writer:flush()
        end)
      end
    end)
    local futures = {}
    for i = 1, 20 do
      futures[i] = reactor.fork(function()
        local client <close> = net.connect(LOOPBACK, port)
        local writer = client:writer()
        writer:write(tostring(i))
        writer:write("\n")
        writer:flush()
        return tonumber(client:reader():read_line())
      end)
    end
    local sum = 0
    for i = 1, 20 do sum = sum + futures[i]:value() end
    return sum
  end)
  self:assert_equal(210, total)
end

function T:test_operations_require_a_managed_coroutine()
  local err = self:assert_error(function() net.connect(LOOPBACK, 1) end)
  self:assert_true(core.is_instance_of(err, core.NonYieldableContextError))
end

return T
