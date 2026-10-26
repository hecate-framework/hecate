---@diagnostic disable: param-type-mismatch, assign-type-mismatch  -- the tests pass invalid arguments on purpose
local test = require("harness.test")
local core = require("hecate.core")
local reactor = require("hecate.reactor")
local net = require("hecate.net")
local T = test.Case("NetTcpTest")

local LOOPBACK = "127.0.0.1"
local IS_WINDOWS = package.config:sub(1, 1) == "\\"

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

--- A loopback port on which nothing listens: bind to learn a free port, then close at once. Another
--- process could take the port in that window; `refused_connect` retries once with a new port.
local function closed_port()
  return reactor.run(function()
    local listener = net.listen(LOOPBACK, 0)
    local port = listener:local_address().port
    listener:close()
    return port
  end)
end

--- Connects to a closed port and returns the failure; retries once if the port was taken meanwhile.
local function refused_connect(self, options)
  for attempt = 1, 2 do
    local port = closed_port()
    local ok, err = pcall(reactor.run, function()
      local stream = net.connect(LOOPBACK, port, options)
      stream:close()
    end)
    if not ok then return err, port end
    if attempt == 2 then self:fail("a closed port accepted a connection twice") end
  end
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
    local done = reactor.Channel(1)
    reactor.fork(function()
      local peer <close> = listener:accept()
      local writer = peer:writer({ capacity = 1000 })
      writer:write(payload)
      writer:flush()
      peer:shutdown()
      done:receive() -- stays open until the reader has read everything
    end)
    local client <close> = net.connect(LOOPBACK, port)
    local data = client:reader():read_exact(#payload)
    done:send(true)
    return data
  end)
  self:assert_equal(#payload, #received)
  self:assert_true(received == payload)
end

function T:test_a_short_stream_raises_end_of_stream_and_keeps_the_bytes()
  with_listener(self, function(listener, port)
    local done = reactor.Channel(1)
    reactor.fork(function()
      local peer <close> = listener:accept()
      peer:write("abc")
      peer:shutdown()
      done:receive()
    end)
    local client <close> = net.connect(LOOPBACK, port)
    local reader = client:reader()
    local err = self:assert_error(function() reader:read_exact(10) end)
    self:assert_true(core.is_instance_of(err, net.EndOfStreamError))
    self:assert_equal(3, reader:buffered()) -- the partial read did not leak
    self:assert_equal("abc", reader:read_some())
    self:assert_nil(reader:read_some())
    done:send(true)
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
    local connected = reactor.Channel(1)
    local future = reactor.fork(function()
      local client <close> = net.connect(LOOPBACK, port)
      stream = client
      connected:send(true)
      client:read() -- the server never writes
    end)
    local accepted = reactor.Channel(1)
    reactor.fork(function() local peer <close> = listener:accept(); accepted:send(true); peer:read() end) -- until the client closes
    connected:receive()
    accepted:receive() -- the listener must not close before the accept completed
    future:cancel()
    self:assert_error(function() future:value() end)
    self:assert_true(stream:is_closed())
  end)
end

function T:test_the_listener_is_closed_by_its_scope_and_wakes_a_pending_accept()
  with_listener(self, function(listener)
    local parked = reactor.Channel(1)
    local acceptor = reactor.fork(function()
      -- Scheduling is cooperative: `send` does not yield, so the receiver below runs only once this
      -- coroutine has parked inside `accept`, the next suspension point.
      parked:send(true)
      return pcall(listener.accept, listener)
    end)
    parked:receive()
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
    local release = reactor.Channel(1)
    local server = reactor.fork(function()
      local peer <close> = listener:accept()
      release:receive() -- silent until the deadline has expired
      peer:write("late\n")
    end)
    local client <close> = net.connect(LOOPBACK, port)
    local reader = client:reader()
    local ok, err = pcall(reactor.deadline, 0.03, function() return reader:read_line() end)
    self:assert_false(ok)
    self:assert_true(core.is_instance_of(err, core.DeadlineExceededError))
    release:send(true)
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

function T:test_a_reset_peer_raises_a_transport_error_and_never_a_partial_result()
  with_listener(self, function(listener, port)
    local closed = reactor.Channel(1)
    reactor.fork(function()
      local peer = listener:accept()
      peer:close()
      closed:send(true)
    end)
    local client <close> = net.connect(LOOPBACK, port)
    closed:receive()
    -- The first writes may sit in kernel buffers: write until the failure shows.
    local errno = errno_of(self, function()
      local writer = client:writer({ capacity = 65536 })
      for _ = 1, 2000 do writer:write(string.rep("x", 65536)); reactor.sleep(0) end
      writer:flush()
    end)
    self:assert_true(errno == "EPIPE" or errno == "ECONNRESET" or errno == "ECONNABORTED"
      or (IS_WINDOWS and errno == "ECANCELED"), tostring(errno))
  end)
end

function T:test_a_failed_flush_poisons_the_writer_over_a_tcp_stream()
  with_listener(self, function(listener, port)
    local closed = reactor.Channel(1)
    reactor.fork(function() local peer = listener:accept(); peer:close(); closed:send(true) end)
    local client <close> = net.connect(LOOPBACK, port)
    closed:receive()
    local writer = client:writer({ capacity = 1 })
    local _, first = pcall(function()
      for _ = 1, 2000 do writer:write(string.rep("x", 65536)); reactor.sleep(0) end
    end)
    self:assert_true(core.is_instance_of(first, reactor.TransportError))
    self:assert_true(core.is_instance_of(first, core.NetworkError))
    local second = self:assert_error(function() writer:write("y") end)
    self:assert_true(core.is_instance_of(second, core.NetworkError)) -- poisoned: no bytes after a gap
    self:assert_true(second.cause == first)
  end)
end

function T:test_connect_refused_raises_a_transport_error()
  local err, port = refused_connect(self)
  self:assert_true(core.is_instance_of(err, reactor.TransportError), tostring(err))
  self:assert_false(core.is_instance_of(err, reactor.IoError), tostring(err))
  self:assert_equal("ECONNREFUSED", err.context.errno)
  -- The message names the endpoint and the failure, and the original error is kept as the cause.
  self:assert_equal(("connect to %s:%d failed: ECONNREFUSED connection refused"):format(LOOPBACK, port), err.message)
  self:assert_equal(LOOPBACK, err.context.host)
  self:assert_equal(port, err.context.port)
  self:assert_true(core.is_instance_of(err.cause, reactor.TransportError))
  self:assert_equal("ECONNREFUSED", err.cause.context.errno)
end

function T:test_a_failed_connect_reports_every_attempt()
  local err = refused_connect(self)
  local attempts = err.context.attempts
  self:assert_equal(1, #attempts)
  self:assert_equal(LOOPBACK, attempts[1].address)
  self:assert_equal(err.context.errno, attempts[1].errno)
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

function T:test_an_unknown_host_raises_a_transport_error_and_leaks_nothing()
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

--- Records the calls `nodelay` and `keepalive` receive while `fn` runs. The libuv TCP handle is a
--- userdata whose methods live in a shared table, so wrapping them there observes every handle the
--- reactor creates. (Tests may require luv; only `src` is forbidden to, OQ-28.)
local function spying_on_handles(fn)
  local uv = require("luv")
  local probe = uv.new_tcp()
  local methods = getmetatable(probe).__index
  probe:close()
  local calls = {}
  local originals = { nodelay = methods.nodelay, keepalive = methods.keepalive }
  for name, original in pairs(originals) do
    methods[name] = function(handle, ...)
      calls[#calls + 1] = { name = name, args = table.pack(...) }
      return original(handle, ...)
    end
  end
  local ok, err = pcall(fn, calls)
  for name, original in pairs(originals) do methods[name] = original end
  if not ok then error(err, 0) end
  return calls
end

local function calls_named(calls, name)
  local found = {}
  for _, call in ipairs(calls) do
    if call.name == name then found[#found + 1] = call.args end
  end
  return found
end

function T:test_options_reach_the_transport()
  local calls = spying_on_handles(function()
    with_listener(self, function(listener, port)
      -- The acceptor is joined after the client closed: the listener must not be closed before
      -- the accept completed (on macOS the scheduling made that race visible).
      local acceptor = reactor.fork(function() local peer <close> = listener:accept(); peer:read() end)
      do
        local client <close> = net.connect(LOOPBACK, port, { nodelay = false, keepalive = true, keepalive_delay = 30 })
        client:set_nodelay(true)
        client:set_keepalive(false)
      end
      reactor.join(acceptor)
    end, { backlog = 16, keepalive = true, keepalive_delay = 45 })
  end)
  local nodelay, keepalive = calls_named(calls, "nodelay"), calls_named(calls, "keepalive")
  self:assert_true(#nodelay >= 3, "nodelay calls: " .. #nodelay)
  local seen = {}
  for _, args in ipairs(keepalive) do seen[#seen + 1] = ("%s/%s"):format(tostring(args[1]), tostring(args[2])) end
  local text = table.concat(seen, " ")
  -- connect options, the explicit set_keepalive(false), and the listener's options on the accepted socket
  self:assert_true(text:find("true/30", 1, true) ~= nil, text)
  self:assert_true(text:find("true/45", 1, true) ~= nil, text)
  self:assert_true(text:find("false/", 1, true) ~= nil, text)
  local values = {}
  for _, args in ipairs(nodelay) do values[#values + 1] = tostring(args[1]) end
  -- `nodelay = false` of connect (the default of every other socket is true) and the later set_nodelay(true)
  self:assert_true(table.concat(values, " "):find("false", 1, true) ~= nil, table.concat(values, " "))
  self:assert_equal("true", values[#values])
end

function T:test_defaults_are_nodelay_on_keepalive_off_and_a_delay_of_60_seconds()
  local calls = spying_on_handles(function()
    with_listener(self, function(listener, port)
      local acceptor = reactor.fork(function() local peer <close> = listener:accept(); peer:read() end)
      do
        local client <close> = net.connect(LOOPBACK, port)
        self:assert_equal(port, client:peer_address().port)
      end
      reactor.join(acceptor)
    end)
  end)
  self:assert_true(#calls >= 4) -- two sockets, two calls each
  for _, args in ipairs(calls_named(calls, "nodelay")) do self:assert_equal(true, args[1]) end
  for _, args in ipairs(calls_named(calls, "keepalive")) do
    self:assert_equal(false, args[1])
    self:assert_equal(60, args[2])
  end
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

function T:test_a_malformed_port_is_refused_before_any_resolution()
  reactor.run(function()
    local core = require("hecate.core")
    for _, port in ipairs({ -1, 65536, 1.5, "80" }) do
      local err = self:assert_error(function() net.connect("no-such-host.invalid", port) end)
      self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
      err = self:assert_error(function() net.listen("127.0.0.1", port) end)
      self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
      err = self:assert_error(function() net.bind_udp("127.0.0.1", port) end)
      self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
    end
  end)
end

-- A slow peer: one byte per write, with a yield between writes, so the reader receives the
-- stream in the smallest pieces the transport can deliver (a CRLF is split across two reads).
function T:test_a_peer_writing_one_byte_at_a_time_is_reassembled()
  with_listener(self, function(listener, port)
    local message = "hello\r\nworld\r\n\r\nlast"
    local server = reactor.fork(function()
      local peer <close> = listener:accept()
      for k = 1, #message do
        peer:write(message:sub(k, k))
        reactor.sleep(0)
      end
      peer:shutdown()
    end)
    local client <close> = net.connect(LOOPBACK, port, { nodelay = true })
    local reader = client:reader()
    self:assert_equal("hello", reader:read_line())
    self:assert_equal("world", reader:read_line())
    self:assert_equal("", reader:read_line())
    self:assert_equal("last", reader:read_exact(4))
    self:assert_nil(reader:read_line())
    server:value()
  end)
end
-- ---------------------------------------------------------------------------------------------
-- Option and error ergonomics

function T:test_option_errors_name_the_net_function_and_come_before_any_resolution()
  reactor.run(function()
    -- A host that cannot resolve: if resolution came first the error would be a TransportError.
    local host = "no-such-host.invalid"
    local cases = {
      { "connect", function() net.connect(host, 80, { nodelays = true }) end, "connect: unknown option nodelays" },
      { "connect", function() net.connect(host, 80, { backlog = 5 }) end, "connect: unknown option backlog" },
      { "connect", function() net.connect(host, 80, { reuseport = true }) end, "connect: unknown option reuseport" },
      { "connect", function() net.connect(host, 80, { nodelay = "yes" }) end, "connect: option nodelay must be a boolean" },
      { "connect", function() net.connect(host, 80, { keepalive = 1 }) end, "connect: option keepalive must be a boolean" },
      { "connect", function() net.connect(host, 80, { keepalive_delay = 1.5 }) end, "connect: option keepalive_delay must be a positive integer" },
      { "connect", function() net.connect(host, 80, { keepalive_delay = 0 }) end, "connect: option keepalive_delay must be a positive integer" },
      { "connect", function() net.connect(host, 80, { family = "ipx" }) end, "connect: option family must be" },
      { "listen", function() net.listen(host, 80, { backlog = 0 }) end, "listen: option backlog must be a positive integer" },
      { "listen", function() net.listen(host, 80, { backlog = 1.5 }) end, "listen: option backlog must be a positive integer" },
      { "listen", function() net.listen(host, 80, { reuseport = "yes" }) end, "listen: option reuseport must be a boolean" },
      { "listen", function() net.listen(host, 80, { reuse_port = true }) end, "listen: unknown option reuse_port" },
    }
    for _, case in ipairs(cases) do
      local err = self:assert_error(case[2])
      self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
      self:assert_true(tostring(err):find(case[3], 1, true) ~= nil, tostring(err))
    end
  end)
end

function T:test_listen_failures_name_the_endpoint_and_keep_the_errno()
  reactor.run(function()
    local first <close> = net.listen(LOOPBACK, 0)
    local port = first:local_address().port
    local err = self:assert_error(function() net.listen(LOOPBACK, port) end)
    self:assert_true(core.is_instance_of(err, reactor.TransportError), tostring(err))
    -- Windows may report a bound address as EACCES instead (exclusive address use); a documented difference.
    if not (IS_WINDOWS and err.context.errno == "EACCES") then
      self:assert_equal("EADDRINUSE", err.context.errno)
      self:assert_equal(("listen on %s:%d failed: EADDRINUSE address already in use"):format(LOOPBACK, port), err.message)
    end
    self:assert_true(tostring(err.message):find(("listen on %s:%d failed: "):format(LOOPBACK, port), 1, true) == 1)
    self:assert_equal(port, err.context.port)
    self:assert_true(core.is_instance_of(err.cause, reactor.TransportError))
  end)
end

function T:test_a_resolution_failure_carries_the_host_name()
  local before = reactor.Reactor.open_handles()
  reactor.run(function()
    for _, call in ipairs({
      function() net.resolve("no-such-host.invalid") end,
      function() net.connect("no-such-host.invalid", 80) end,
      function() net.listen("no-such-host.invalid", 80) end,
    }) do
      local err = self:assert_error(call)
      self:assert_true(core.is_instance_of(err, reactor.TransportError), tostring(err))
      self:assert_equal("no-such-host.invalid", err.context.host)
      self:assert_true(tostring(err.message):find("no-such-host.invalid", 1, true) ~= nil, tostring(err))
    end
  end)
  self:assert_equal(before, reactor.Reactor.open_handles())
end

--- Runs `fn(attempted)` with `reactor.resolve` answering `addresses` and `reactor.connect_tcp`
--- replaced by `connect(ip, port, options)`, which may delegate to `real`. Restores both after.
local function stubbing(addresses, connect, fn)
  local resolve, connect_tcp = reactor.resolve, reactor.connect_tcp
  local attempted = {}
  reactor.resolve = function(host)
    attempted.resolved = host
    return addresses
  end
  reactor.connect_tcp = function(ip, port, options)
    attempted[#attempted + 1] = ip
    return connect(ip, port, options, connect_tcp)
  end
  local ok, err = pcall(fn, attempted)
  reactor.resolve, reactor.connect_tcp = resolve, connect_tcp
  if not ok then error(err, 0) end
end

local function refused(ip)
  error(reactor.TransportError({
    message = ("connect %s: ECONNREFUSED"):format(ip),
    context = { operation = "connect " .. ip, errno = "ECONNREFUSED" },
  }), 0)
end

function T:test_connect_tries_the_next_address_when_the_first_refuses()
  with_listener(self, function(listener, port)
    reactor.fork(function() local peer <close> = listener:accept(); peer:write("second") end)
    stubbing({ { ip = "192.0.2.1", family = "inet" }, { ip = LOOPBACK, family = "inet" } },
      function(ip, p, options, real)
        if ip == "192.0.2.1" then refused(ip) end
        return real(ip, p, options)
      end,
      function(attempted)
        local client <close> = net.connect("multi.example", port)
        self:assert_equal("multi.example", attempted.resolved)
        self:assert_equal("192.0.2.1,127.0.0.1", table.concat(attempted, ","))
        self:assert_equal("second", client:read())
      end)
  end)
end

function T:test_connect_reports_every_attempt_in_order_when_all_refuse()
  reactor.run(function()
    stubbing({ { ip = "192.0.2.1", family = "inet" }, { ip = "192.0.2.2", family = "inet" } },
      function(ip) refused(ip) end,
      function(attempted)
        local err = self:assert_error(function() net.connect("multi.example", 5432) end)
        self:assert_equal(2, #err.context.attempts)
        self:assert_equal("192.0.2.1", err.context.attempts[1].address)
        self:assert_equal("192.0.2.2", err.context.attempts[2].address)
        self:assert_equal("ECONNREFUSED", err.context.attempts[2].errno)
        self:assert_equal("connect to multi.example:5432 failed: ECONNREFUSED connection refused"
          .. " (tried 192.0.2.1, 192.0.2.2)", err.message)
        self:assert_equal("ECONNREFUSED", err.context.errno)
        self:assert_true(core.is_instance_of(err.cause, reactor.TransportError))
        self:assert_equal(2, #attempted)
      end)
  end)
end

function T:test_cancellation_stops_connect_instead_of_trying_the_next_address()
  reactor.run(function()
    stubbing({ { ip = "192.0.2.1", family = "inet" }, { ip = "192.0.2.2", family = "inet" } },
      function() reactor.sleep(30) end, -- the first address never answers
      function(attempted)
        local ok, err = pcall(reactor.deadline, 0.02, net.connect, "multi.example", 80)
        self:assert_false(ok)
        self:assert_true(core.is_instance_of(err, core.DeadlineExceededError), tostring(err))
        self:assert_equal("192.0.2.1", table.concat(attempted, ","))
      end)
    -- A cancellation (not only a deadline) behaves the same.
    stubbing({ { ip = "192.0.2.1", family = "inet" }, { ip = "192.0.2.2", family = "inet" } },
      function() reactor.sleep(30) end,
      function(attempted)
        local future = reactor.fork(net.connect, "multi.example", 80)
        reactor.sleep(0)
        future:cancel()
        self:assert_error(function() future:value() end)
        self:assert_equal(1, #attempted)
      end)
  end)
end

function T:test_a_deadline_during_resolution_cancels_without_connecting()
  local before = reactor.Reactor.open_handles()
  reactor.run(function()
    local resolve, connect_tcp = reactor.resolve, reactor.connect_tcp
    local connected = false
    reactor.resolve = function() reactor.sleep(30) end
    reactor.connect_tcp = function() connected = true end
    local ok, err = pcall(reactor.deadline, 0.02, net.connect, "slow.example", 80)
    reactor.resolve, reactor.connect_tcp = resolve, connect_tcp
    self:assert_false(ok)
    self:assert_true(core.is_instance_of(err, core.DeadlineExceededError), tostring(err))
    self:assert_false(connected)
  end)
  self:assert_equal(before, reactor.Reactor.open_handles())
end

function T:test_a_cancelled_connect_leaves_no_handle()
  local before = reactor.Reactor.open_handles()
  reactor.run(function()
    local listener <close> = net.listen(LOOPBACK, 0)
    local port = listener:local_address().port
    local future = reactor.fork(net.connect, LOOPBACK, port)
    future:cancel()
    local ok, result = pcall(future.value, future)
    if ok then result:close() end -- the connect won the race: a stream, which must close cleanly
  end)
  self:assert_equal(before, reactor.Reactor.open_handles())
end

function T:test_listen_on_a_name_binds_the_first_resolved_address_only()
  reactor.run(function()
    local first = net.resolve("localhost")[1]
    local listener <close> = net.listen("localhost", 0)
    self:assert_equal(first.ip, listener:local_address().ip)
    self:assert_equal(first.family, listener:local_address().family)
  end)
end

-- The peer resets the connection (a socket closed while it holds unread data answers with RST) while
-- this side is reading: a clean end of stream or a transport error are both what platforms do, never
-- data. The accepted set below is the documented one per platform.
function T:test_a_reset_peer_on_the_read_side_ends_the_stream_or_raises_but_never_returns_data()
  with_listener(self, function(listener, port)
    local sent, closed = reactor.Channel(1), reactor.Channel(1)
    reactor.fork(function()
      local peer = listener:accept()
      sent:receive() -- the client's bytes are in this socket's receive queue: closing now resets
      peer:close()
      closed:send(true)
    end)
    local client <close> = net.connect(LOOPBACK, port)
    client:write("unread by the peer")
    sent:send(true)
    closed:receive()
    local ok, result = pcall(client.read, client)
    if ok then
      self:assert_nil(result, "a reset must not deliver data")
    else
      self:assert_true(core.is_instance_of(result, reactor.TransportError), tostring(result))
      local errno = (result --[[@as hecate.core.Error]]).context.errno
      self:assert_true(errno == "ECONNRESET" or errno == "EPIPE" or errno == "ECONNABORTED", tostring(errno))
    end
    client:close()
    self:assert_true(client:is_closed())
  end)
end

-- Back-pressure through the buffered layer: a peer that never reads fills the socket buffers, the
-- flush suspends, and a deadline cancels it. A write cancelled midway closes the TCP stream (bytes
-- sent are unknown) and poisons the writer (OQ-28, OQ-30).
function T:test_a_flush_cancelled_by_back_pressure_poisons_the_writer_and_closes_the_stream()
  with_listener(self, function(listener, port)
    local release = reactor.Channel(1)
    local server = reactor.fork(function()
      local peer <close> = listener:accept()
      release:receive() -- never reads
    end)
    local client <close> = net.connect(LOOPBACK, port)
    local writer = client:writer({ capacity = 1 << 20 })
    local payload = string.rep("x", 1 << 20)
    local ok, err = pcall(reactor.deadline, 0.1, function()
      for _ = 1, 256 do writer:write(payload) end -- 256 MiB: far more than the kernel buffers hold
      writer:flush()
    end)
    self:assert_false(ok)
    self:assert_true(core.is_instance_of(err, core.DeadlineExceededError), tostring(err))
    self:assert_true(client:is_closed())
    local later = self:assert_error(function() writer:write("y") end)
    self:assert_true(core.is_instance_of(later, core.NetworkError))
    self:assert_not_nil(later.cause)
    release:send(true)
    server:value()
  end)
end

return T
