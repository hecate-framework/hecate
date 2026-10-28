-- TlsStream behaviour over loopback: sending discipline (cancellation, concurrent writers, a reader
-- next to a blocked writer), framing robustness (byte-at-a-time chunking, truncated and corrupted
-- records, plaintext sent to a TLS server), half-close, the closed-stream contract and the native
-- session itself. Skips with a message when the native module is not built.
local test = require("harness.test")
local core = require("hecate.core")
local reactor = require("hecate.reactor")
local net = require("hecate.net")
local T = test.Case("NetTlsStreamTest")

local available, reason = net.tls.available()
if not available then
  function T:test_skipped_native_module_not_built()
    if os.getenv("HECATE_REQUIRE_TLS") == "1" then
      self:fail("hecate.net TLS tests cannot run: " .. tostring(reason))
    end
    print("# SKIP hecate.net TLS stream tests: " .. tostring(reason))
  end
  return T
end

local function fixture(name)
  local path = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):gsub("/[^/]*$", "") .. "/../fixtures/" .. name
  local f = assert(io.open(path, "rb"), "missing fixture " .. path)
  local s = f:read("a")
  f:close()
  return s
end

local CA, SERVER_CERT, SERVER_KEY = fixture("ca.pem"), fixture("server.pem"), fixture("server.key")

--- Runs `fn` on a reactor and checks that no libuv handle is left open afterwards.
local function run(self, fn)
  local before = reactor.Reactor.open_handles()
  reactor.run(fn)
  self:assert_equal(before, reactor.Reactor.open_handles())
end

local function server_config(extra)
  local options = { cert_pem = SERVER_CERT, key_pem = SERVER_KEY }
  for k, v in pairs(extra or {}) do options[k] = v end
  return net.tls.server_config(options)
end

local function client_config()
  return net.tls.client_config({ system_roots = false, ca_pem = CA })
end

--- A server coroutine: accepts one connection, wraps it (`options.wrap`), runs the handshake and
--- `options.serve(tls, stream)`. The outcome holds `ok` and `value` once `future` is done.
local function serve(listener, options)
  local outcome = {}
  outcome.future = reactor.fork(function()
    local raw = listener:accept()
    local ok, result = pcall(function()
      local stream = options.wrap and options.wrap(raw) or raw
      local tls <close> = net.tls.accept(stream, options.config or server_config())
      return options.serve(tls, stream)
    end)
    outcome.ok, outcome.value = ok, result
  end)
  return outcome
end

--- Connects and handshakes as a client; returns the TLS stream and the (possibly wrapped) stream under it.
local function dial(port, wrap)
  local raw = net.connect("127.0.0.1", port)
  local stream = wrap and wrap(raw) or raw
  return net.tls.connect(stream, "localhost", client_config()), stream
end

--- Reads a TLS stream until its clean end and returns everything.
local function read_all(tls)
  local parts = {}
  while true do
    local chunk = tls:read()
    if chunk == nil then break end
    parts[#parts + 1] = chunk
  end
  return table.concat(parts)
end

--- A stream decorator whose writes can be held back: while `blocked`, a write announces itself on
--- `parked` and waits on `release`. It lets a test hold a writer inside the inner write without
--- relying on kernel buffer sizes or timing.
local Gate = {}
Gate.__index = Gate
local function new_gate(inner)
  return setmetatable({ inner = inner, blocked = false, parked = reactor.Channel(8), release = reactor.Channel(8) }, Gate)
end
function Gate:read(max) return self.inner:read(max) end
function Gate:write(data)
  if self.blocked then
    self.parked:send(true)
    self.release:receive()
  end
  return self.inner:write(data)
end
function Gate:shutdown() return self.inner:shutdown() end
function Gate:close() self.inner:close() end
function Gate:is_closed() return self.inner:is_closed() end

--- Starts `fn` in a coroutine and returns a table that holds its outcome once its future is done.
local function fork_job(fn)
  local job = {}
  job.future = reactor.fork(function()
    job.ok, job.value = pcall(fn)
  end)
  return job
end

--- Decorates a server stream: once `mode` is set, the next write is cut in half and the stream
--- closed ("truncate"), or one byte of it is flipped ("corrupt").
local function tamper(inner)
  local stream = { mode = nil }
  function stream:read(max) return inner:read(max) end
  function stream:write(data)
    if self.mode == "truncate" then
      inner:write(data:sub(1, math.max(1, #data // 2)))
      inner:close()
    elseif self.mode == "corrupt" then
      local at = #data - 3
      inner:write(data:sub(1, at - 1) .. string.char(data:byte(at) ~ 0xff) .. data:sub(at + 1))
    else
      inner:write(data)
    end
  end
  function stream:shutdown() return inner:shutdown() end
  function stream:close() inner:close() end
  function stream:is_closed() return inner:is_closed() end
  return stream
end

function T:test_a_write_cancelled_midway_closes_the_stream()
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local outcome = serve(listener, { serve = function(tls) tls:read() end })
    local gate
    local client = dial(listener:local_address().port, function(raw) gate = new_gate(raw) return gate end)
    gate.blocked = true
    local writer = fork_job(function() client:write("hello") end)
    gate.parked:receive() -- the writer is inside the inner write: the session holds its bytes
    writer.future:cancel()
    writer.future:value()
    self:assert_false(writer.ok)
    self:assert_true(core.is_instance_of(writer.value, core.CancellationError), tostring(writer.value))
    self:assert_true(client:is_closed())
    self:assert_true(gate.inner:is_closed()) -- the inner stream is closed too: the bytes sent are unknown
    local err = self:assert_error(function() client:write("again") end)
    self:assert_true(core.is_instance_of(err, reactor.TransportError), tostring(err))
    self:assert_equal("EBADF", err.context.errno)
    outcome.future:value()
  end)
end

function T:test_a_write_cancelled_while_waiting_for_its_turn_changes_nothing()
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local outcome = serve(listener, { serve = read_all })
    local gate
    local client = dial(listener:local_address().port, function(raw) gate = new_gate(raw) return gate end)
    gate.blocked = true
    local first = fork_job(function() client:write("first;") end)
    gate.parked:receive() -- the first write holds the send mutex, blocked in the inner write
    local started = reactor.Channel(1)
    local second = fork_job(function()
      started:send(true)
      client:write("second;")
    end)
    started:receive() -- the second write was started and queued behind the first
    second.future:cancel()
    second.future:value()
    self:assert_false(second.ok)
    self:assert_true(core.is_instance_of(second.value, core.CancellationError), tostring(second.value))
    self:assert_false(client:is_closed()) -- it never handed a byte to the session
    gate.blocked = false
    gate.release:send(true)
    first.future:value()
    self:assert_true(first.ok, tostring(first.value))
    client:write("third;")
    client:shutdown()
    outcome.future:value()
    -- Nothing of the cancelled write reached the peer, neither now nor with a later write.
    self:assert_true(outcome.ok, tostring(outcome.value))
    self:assert_equal("first;third;", outcome.value)
    client:close()
  end)
end

function T:test_concurrent_large_writes_arrive_intact_and_unmixed()
  run(self, function()
    local size = 400000
    local listener <close> = net.listen("127.0.0.1", 0)
    local outcome = serve(listener, {
      serve = function(tls)
        local data = tls:reader():read_exact(2 * size)
        tls:shutdown()
        return data
      end,
    })
    local client <close> = dial(listener:local_address().port)
    local a = fork_job(function() client:write(("a"):rep(size)) end)
    local b = fork_job(function() client:write(("b"):rep(size)) end)
    reactor.join(a.future, b.future)
    self:assert_true(a.ok and b.ok, tostring(a.value) .. tostring(b.value))
    outcome.future:value()
    self:assert_true(outcome.ok, tostring(outcome.value))
    local data = outcome.value
    local first = data:sub(1, 1)
    local second = first == "a" and "b" or "a"
    self:assert_true(data == first:rep(size) .. second:rep(size), "the two writes were interleaved on the wire")
  end)
end

function T:test_a_reader_is_not_held_up_by_a_writer_blocked_in_back_pressure()
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local release = reactor.Channel(1)
    local outcome = serve(listener, {
      serve = function(tls)
        tls:write("hello")
        release:receive()
        tls:read()
      end,
    })
    local gate
    local client = dial(listener:local_address().port, function(raw) gate = new_gate(raw) return gate end)
    gate.blocked = true
    local writer = fork_job(function() client:write("blocked") end)
    gate.parked:receive() -- the writer holds the send mutex and cannot finish
    local reader = fork_job(function() return client:read() end)
    -- The guard turns a regression (the reader queued behind the writer) into a failure, not a hang.
    local ok, failure = pcall(reactor.deadline, 5, function() return reader.future:value() end)
    self:assert_true(ok, tostring(failure))
    self:assert_true(reader.ok, tostring(reader.value))
    self:assert_equal("hello", reader.value)
    gate.blocked = false
    gate.release:send(true)
    writer.future:value()
    self:assert_true(writer.ok, tostring(writer.value))
    release:send(true)
    client:close()
    outcome.future:value()
  end)
end

function T:test_one_reader_and_one_writer_share_a_stream_with_a_peer_that_reads_after_writing()
  run(self, function()
    local size = 12 * 1024 * 1024 -- well beyond what the socket buffers hold in either direction
    local listener <close> = net.listen("127.0.0.1", 0)
    local outcome = serve(listener, {
      serve = function(tls)
        -- The peer first writes everything it has, and only then reads: it drains the client
        -- only after the client has drained it.
        tls:write(("s"):rep(size))
        local got = 0
        while got < size do got = got + #assert(tls:read()) end
        tls:shutdown()
      end,
    })
    local client <close> = dial(listener:local_address().port)
    local writer = fork_job(function() client:write(("c"):rep(size)) end)
    local reader = fork_job(function()
      local got = 0
      while got < size do got = got + #assert(client:read()) end
      return got
    end)
    local ok, failure = pcall(reactor.deadline, 60, function() reactor.join(writer.future, reader.future) end)
    self:assert_true(ok, "deadlock between the reader and the writer: " .. tostring(failure))
    self:assert_true(writer.ok, tostring(writer.value))
    self:assert_equal(size, reader.value)
    outcome.future:value()
    self:assert_true(outcome.ok, tostring(outcome.value))
  end)
end

function T:test_a_cancellation_while_sending_an_alert_is_not_turned_into_a_tls_error()
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local outcome = serve(listener, {
      wrap = tamper,
      serve = function(tls, stream)
        stream.mode = "corrupt"
        tls:write("a record the client cannot decrypt")
        read_all(tls)
      end,
    })
    local gate
    local client = dial(listener:local_address().port, function(raw) gate = new_gate(raw) return gate end)
    gate.blocked = true
    local reader = fork_job(function() return client:read() end)
    gate.parked:receive() -- the record failed to decrypt: its alert is being sent and cannot finish
    reader.future:cancel()
    reader.future:value()
    -- The cancellation reaches the caller (it used to be swallowed and replaced by a TlsError); the
    -- stream is closed all the same, because the session failed.
    self:assert_false(reader.ok)
    self:assert_true(core.is_instance_of(reader.value, core.CancellationError), tostring(reader.value))
    self:assert_true(client:is_closed())
    outcome.future:value()
  end)
end

function T:test_a_shutdown_cancelled_midway_closes_the_stream()
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local outcome = serve(listener, { serve = function(tls) tls:read() end })
    local gate
    local client = dial(listener:local_address().port, function(raw) gate = new_gate(raw) return gate end)
    gate.blocked = true
    local closing = fork_job(function() client:shutdown() end)
    gate.parked:receive() -- close_notify is queued and being sent
    closing.future:cancel()
    closing.future:value()
    self:assert_false(closing.ok)
    self:assert_true(core.is_instance_of(closing.value, core.CancellationError), tostring(closing.value))
    self:assert_true(client:is_closed())
    self:assert_true(gate.inner:is_closed())
    outcome.future:value()
  end)
end

function T:test_write_after_shutdown_raises_and_the_stream_stays_readable()
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local outcome = serve(listener, {
      serve = function(tls)
        local request = read_all(tls) -- the client's half-close ends this
        tls:write("answer to " .. request)
        tls:shutdown()
      end,
    })
    local client <close> = dial(listener:local_address().port)
    client:write("request")
    client:shutdown()
    client:shutdown() -- idempotent
    local err = self:assert_error(function() client:write("late") end)
    self:assert_true(core.is_instance_of(err, reactor.TransportError), tostring(err))
    self:assert_equal("EPIPE", err.context.errno)
    self:assert_equal("write", err.context.operation)
    self:assert_false(client:is_closed())
    self:assert_equal("answer to request", read_all(client)) -- TLS half-close keeps the other direction
    outcome.future:value()
    self:assert_true(outcome.ok, tostring(outcome.value))
  end)
end

function T:test_two_readers_on_one_stream_are_refused()
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local release = reactor.Channel(1)
    local outcome = serve(listener, {
      serve = function(tls)
        release:receive()
        tls:write("x")
        tls:shutdown()
      end,
    })
    local client <close> = dial(listener:local_address().port)
    local started = reactor.Channel(2)
    local function reader()
      started:send(true)
      return client:read()
    end
    local first, second = fork_job(reader), fork_job(reader)
    started:receive()
    started:receive() -- both are at their read; the data is only sent now
    release:send(true)
    reactor.join(first.future, second.future)
    local refused, served = first, second
    if first.ok then refused, served = second, first end
    self:assert_true(served.ok, tostring(served.value))
    self:assert_equal("x", served.value)
    self:assert_false(refused.ok)
    self:assert_true(core.is_instance_of(refused.value, core.Error), tostring(refused.value))
    self:assert_true(tostring(refused.value):find("already reading", 1, true) ~= nil, tostring(refused.value))
    outcome.future:value()
  end)
end

function T:test_a_closed_stream_raises_a_transport_error_for_every_operation()
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local outcome = serve(listener, { serve = function(tls) tls:read() end })
    local client, stream = dial(listener:local_address().port)
    do
      local scoped <close> = client
      self:assert_false(scoped:is_closed())
    end
    self:assert_true(client:is_closed())
    self:assert_true(stream:is_closed()) -- the inner stream went with it
    for _, operation in ipairs({ "read", "write", "shutdown" }) do
      local err = self:assert_error(function()
        if operation == "read" then client:read() elseif operation == "write" then client:write("x") else client:shutdown() end
      end)
      self:assert_true(core.is_instance_of(err, reactor.TransportError), tostring(err))
      self:assert_equal("EBADF", err.context.errno)
      self:assert_equal(operation, err.context.operation)
    end
    self:assert_nil(client:alpn()) -- the session state is dropped
    outcome.future:value()
  end)
end

function T:test_read_validates_its_argument_like_a_tcp_stream()
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local outcome = serve(listener, { serve = function(tls) tls:read() end })
    local client <close> = dial(listener:local_address().port)
    local tcp = net.connect("127.0.0.1", listener:local_address().port)
    for _, bad in ipairs({ 0, -1, 1.5, "x" }) do
      local err = self:assert_error(function() client:read(bad) end)
      self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
      local expected = self:assert_error(function() tcp:read(bad) end)
      -- Same message prefix as the TCP stream.
      self:assert_true(tostring(err):find("read: expects a positive integer", 1, true) ~= nil, tostring(err))
      self:assert_true(tostring(expected):find("read: expects a positive integer", 1, true) ~= nil, tostring(expected))
    end
    tcp:close()
    client:close()
    outcome.future:value()
  end)
end

function T:test_write_rejects_a_non_string_argument()
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local outcome = serve(listener, { serve = function(tls) tls:read() end })
    local client <close> = dial(listener:local_address().port)
    for _, bad in ipairs({ 42, true, {} }) do
      local err = self:assert_error(function() client:write(bad) end)
      self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
      self:assert_true(tostring(err):find("net.TlsStream.write: expects a string", 1, true) ~= nil, tostring(err))
    end
    self:assert_false(client:is_closed()) -- a bad argument does not poison the stream
    client:close()
    outcome.future:value()
  end)
end

function T:test_addresses_and_the_requested_server_name_are_exposed()
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local port = listener:local_address().port
    local seen, captured = {}, reactor.Channel(1)
    local outcome = serve(listener, {
      serve = function(tls)
        seen.requested = tls:requested_server_name()
        seen.peer = tls:peer_address()
        seen.here = tls:local_address()
        captured:send(true)
        pcall(tls.read, tls) -- the client closes without close_notify
      end,
    })
    local client <close> = dial(port)
    self:assert_nil(client:requested_server_name()) -- a client stream has none
    self:assert_equal(port, client:peer_address().port)
    self:assert_equal("127.0.0.1", client:peer_address().ip)
    self:assert_equal(client:local_address().port, client:local_address().port)
    client:set_nodelay(true)
    captured:receive() -- the server looked at its side while the connection was up
    client:close()
    outcome.future:value()
    self:assert_true(outcome.ok, tostring(outcome.value))
    self:assert_equal("localhost", seen.requested)
    self:assert_equal(port, seen.here.port)
  end)
end

function T:test_forwarding_needs_an_inner_stream_that_has_the_method()
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local outcome = serve(listener, { serve = function(tls) tls:read() end })
    local client <close> = dial(listener:local_address().port, new_gate)
    for _, method in ipairs({ "peer_address", "local_address", "set_nodelay" }) do
      local err = self:assert_error(function() client[method](client, true) end)
      self:assert_true(core.is_instance_of(err, core.Error), tostring(err))
    end
    client:close()
    outcome.future:value()
  end)
end

-- Byte-at-a-time and random chunking ------------------------------------------------------------

--- xorshift64*: a reproducible generator that leaves the global one alone.
local function generator(seed)
  local state = seed ~ 0x2545F4914F6CDD1D
  if state == 0 then state = 1 end
  return function(n)
    state = state ~ (state >> 12)
    state = state ~ (state << 25)
    state = state ~ (state >> 27)
    return ((state * 0x2545F4914F6CDD1D) >> 33) % n + 1 -- 1..n
  end
end

--- A stream decorator that hands out at most `k` bytes per read and writes in random pieces of
--- 1 to `k` bytes: TLS records are then split at arbitrary points in both directions.
local function chunked(inner, k, random)
  local buffer = ""
  local stream = {}
  function stream:read(max)
    if buffer == "" then
      buffer = inner:read()
      if buffer == nil then buffer = "" return nil end
    end
    local n = math.min(k, #buffer, max or k)
    local piece = buffer:sub(1, n)
    buffer = buffer:sub(n + 1)
    return piece
  end
  function stream:write(data)
    local at = 1
    while at <= #data do
      local n = random(k)
      inner:write(data:sub(at, at + n - 1))
      at = at + n
    end
  end
  function stream:shutdown() return inner:shutdown() end
  function stream:close() inner:close() end
  function stream:is_closed() return inner:is_closed() end
  return stream
end

function T:test_records_survive_any_chunking_of_the_transport()
  local seed = tonumber(os.getenv("HECATE_TEST_SEED")) or os.time()
  for _, k in ipairs({ 1, 2, 5, 17, 1024 }) do
    local random = generator(seed + k)
    local bytes = {}
    for i = 1, 6000 do bytes[i] = string.char(random(256) - 1) end
    local payload = table.concat(bytes)
    local label = ("chunk size %d, seed %d (set HECATE_TEST_SEED to replay)"):format(k, seed)
    run(self, function()
      local listener <close> = net.listen("127.0.0.1", 0)
      local outcome = serve(listener, {
        wrap = function(raw) return chunked(raw, k, random) end,
        serve = function(tls)
          local data = tls:reader():read_exact(#payload)
          tls:write(data) -- echoed in one write
          tls:shutdown()
        end,
      })
      local client <close> = net.tls.connect(chunked(net.connect("127.0.0.1", listener:local_address().port), k, random),
        "localhost", client_config())
      local at = 1
      while at <= #payload do -- written in pieces of random length, so records have random sizes
        local n = random(2500)
        client:write(payload:sub(at, at + n - 1))
        at = at + n
      end
      local echoed = client:reader():read_exact(#payload)
      self:assert_true(echoed == payload, "payload corrupted with " .. label)
      self:assert_nil(client:read(), label)
      outcome.future:value()
      self:assert_true(outcome.ok, tostring(outcome.value) .. " with " .. label)
    end)
  end
end

-- Damaged streams --------------------------------------------------------------------------------

function T:test_a_stream_cut_in_the_middle_of_a_record_is_a_tls_error()
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local outcome = serve(listener, {
      wrap = tamper,
      serve = function(tls, stream)
        stream.mode = "truncate"
        tls:write(("x"):rep(2000))
      end,
    })
    local client <close> = dial(listener:local_address().port)
    local err = self:assert_error(function() client:read() end)
    self:assert_true(core.is_instance_of(err, net.TlsError), tostring(err))
    outcome.future:value()
  end)
end

function T:test_a_corrupted_record_is_a_tls_error()
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local outcome = serve(listener, {
      wrap = tamper,
      serve = function(tls, stream)
        stream.mode = "corrupt"
        tls:write("a record the client cannot decrypt")
        tls:read()
      end,
    })
    local client <close> = dial(listener:local_address().port)
    local err = self:assert_error(function() client:read() end)
    self:assert_true(core.is_instance_of(err, net.TlsError), tostring(err))
    self:assert_true(client:is_closed()) -- a protocol failure ends the stream
    outcome.future:value()
  end)
end

function T:test_plaintext_sent_to_a_tls_server_fails_the_handshake_without_hanging()
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local outcome = serve(listener, { serve = function() end })
    local raw <close> = net.connect("127.0.0.1", listener:local_address().port)
    raw:write("GET / HTTP/1.1\r\nHost: localhost\r\n\r\n")
    local ok, failure = pcall(reactor.deadline, 10, function()
      outcome.future:value()
      while raw:read() do end -- the server's alert, then its end
    end)
    self:assert_true(ok, "the server hung on plaintext: " .. tostring(failure))
    self:assert_false(outcome.ok)
    self:assert_true(core.is_instance_of(outcome.value, net.TlsError), tostring(outcome.value))
  end)
end

-- Certificates -----------------------------------------------------------------------------------

function T:test_a_certificate_that_is_not_valid_yet_is_rejected()
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local config = net.tls.server_config({ cert_pem = fixture("not_yet_valid.pem"), key_pem = fixture("not_yet_valid.key") })
    local outcome = serve(listener, { config = config, serve = function() end })
    local err = self:assert_error(function()
      net.connect_tls("127.0.0.1", listener:local_address().port,
        { system_roots = false, ca_pem = fixture("variant_ca.pem"), server_name = "localhost" })
    end)
    self:assert_true(core.is_instance_of(err, net.TlsError), tostring(err))
    self:assert_equal("not_yet_valid", err.context.reason)
    outcome.future:value()
  end)
end

function T:test_the_default_server_name_is_the_host_and_a_certificate_without_it_is_rejected()
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    -- Valid for "localhost" only: connecting to the address 127.0.0.1 must not accept it.
    local config = net.tls.server_config({ cert_pem = fixture("localhost_only.pem"), key_pem = fixture("localhost_only.key") })
    local outcome = serve(listener, { config = config, serve = function() end })
    local err = self:assert_error(function()
      net.connect_tls("127.0.0.1", listener:local_address().port, { system_roots = false, ca_pem = fixture("variant_ca.pem") })
    end)
    self:assert_true(core.is_instance_of(err, net.TlsError), tostring(err))
    self:assert_equal("name_mismatch", err.context.reason)
    outcome.future:value()
    -- With the name the certificate has, the same server is accepted.
    local again = serve(listener, {
      config = config,
      serve = function(tls)
        tls:write("ok")
        tls:shutdown()
      end,
    })
    local client <close> = net.connect_tls("127.0.0.1", listener:local_address().port,
      { system_roots = false, ca_pem = fixture("variant_ca.pem"), server_name = "localhost" })
    self:assert_equal("ok", client:read())
    again.future:value()
  end)
end

function T:test_a_leaf_certificate_is_not_accepted_as_an_anchor_for_itself()
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local outcome = serve(listener, { serve = function() end })
    -- The server's own certificate as the only anchor: the chain is not rooted in a CA that signed it.
    local err = self:assert_error(function()
      net.connect_tls("127.0.0.1", listener:local_address().port,
        { system_roots = false, ca_pem = SERVER_CERT, server_name = "localhost" })
    end)
    self:assert_true(core.is_instance_of(err, net.TlsError), tostring(err))
    self:assert_equal("untrusted_issuer", err.context.reason)
    outcome.future:value()
  end)
end

-- The native session -----------------------------------------------------------------------------

local native_loaded, native = pcall(require, "hecate.net.tls_native")

--- Moves what `from` queued to `to`; returns what `to` did not take yet.
local function move(from, to, carry)
  local wire = carry .. from:drain()
  local at = 1
  while at <= #wire do
    local taken = to:feed(wire:sub(at))
    if taken == 0 then break end
    at = at + taken
  end
  return wire:sub(at)
end

local function native_pair()
  local client = native.client(native.client_config({ system_roots = false, ca_pem = CA }), "localhost")
  local server = native.server(native.server_config({ cert_pem = SERVER_CERT, key_pem = SERVER_KEY }))
  local to_server, to_client = "", ""
  for _ = 1, 20 do
    to_server = move(client, server, to_server)
    to_client = move(server, client, to_client)
    if not client:is_handshaking() and not server:is_handshaking() then return client, server end
  end
  error("the native handshake did not finish")
end

function T:test_the_end_of_the_transport_waits_for_plaintext_above_the_buffer_limit()
  self:assert_true(native_loaded, tostring(native))
  local client, server = native_pair()
  -- One full record followed by small ones: a single feed ends up with more plaintext than rustls
  -- buffers; recording the end of the transport then must not fail (it used to).
  local lengths, pieces, flights = { 16384 }, {}, {}
  for _ = 1, 10 do lengths[#lengths + 1] = 100 end
  for i, length in ipairs(lengths) do
    local piece = string.char(64 + i):rep(length)
    pieces[#pieces + 1] = piece
    self:assert_equal(length, server:write(piece))
    flights[#flights + 1] = server:drain()
  end
  local payload, wire = table.concat(pieces), table.concat(flights)
  local at = 1
  while client:wants_read() and at <= #wire do at = at + client:feed(wire:sub(at)) end
  client:feed_eof()
  local got = {}
  while true do
    local data, state = client:read()
    if data then
      got[#got + 1] = data
    elseif state == "want_read" and at <= #wire then
      at = at + client:feed(wire:sub(at))
    else
      self:assert_equal("eof", state) -- no close_notify: the end is a truncation, reported last
      break
    end
  end
  self:assert_true(table.concat(got) == payload)
end

function T:test_a_native_session_and_configuration_close_idempotently()
  self:assert_true(native_loaded, tostring(native))
  local client, server = native_pair()
  client:write("x")
  client:close()
  client:close()
  self:assert_false(pcall(client.drain, client))
  self:assert_false(pcall(client.write, client, "y"))
  self:assert_false(client:wants_write())
  self:assert_nil(client:alpn())
  do
    local scoped <close> = server
    self:assert_not_nil(scoped)
  end
  self:assert_false(pcall(server.drain, server))
  local config = native.client_config({ system_roots = false, ca_pem = CA })
  do
    local scoped <close> = config
    self:assert_not_nil(scoped)
  end
  config:close()
  local ok, failure = pcall(native.client, config, "localhost")
  self:assert_false(ok)
  self:assert_true(tostring(failure):find("closed", 1, true) ~= nil, tostring(failure))
end

function T:test_native_alpn_names_are_validated_and_the_error_names_the_option()
  self:assert_true(native_loaded, tostring(native))
  for _, bad in ipairs({ { "" }, { ("a"):rep(256) }, "h2", { 1 } }) do
    local ok, failure = pcall(native.server_config, { cert_pem = SERVER_CERT, key_pem = SERVER_KEY, alpn = bad })
    self:assert_false(ok)
    self:assert_true(tostring(failure):find("alpn", 1, true) ~= nil, tostring(failure))
    ok, failure = pcall(native.client_config, { system_roots = false, ca_pem = CA, alpn = bad })
    self:assert_false(ok)
    self:assert_true(tostring(failure):find("alpn", 1, true) ~= nil, tostring(failure))
  end
  self:assert_not_nil(native.server_config({ cert_pem = SERVER_CERT, key_pem = SERVER_KEY, alpn = { ("a"):rep(255) } }))
end

function T:test_a_native_failure_carries_its_kind_taken_from_the_error_variant()
  self:assert_true(native_loaded, tostring(native))
  local client = native.client(native.client_config({ system_roots = false, ca_pem = fixture("other_ca.pem") }), "localhost")
  local server = native.server(native.server_config({ cert_pem = SERVER_CERT, key_pem = SERVER_KEY }))
  local to_server, to_client = "", ""
  local ok, failure
  for _ = 1, 20 do
    ok, failure = pcall(function()
      to_server = move(client, server, to_server)
      to_client = move(server, client, to_client)
    end)
    if not ok then break end
  end
  self:assert_false(ok)
  self:assert_true(tostring(failure):find("[untrusted_issuer] ", 1, true) ~= nil, tostring(failure))
end

return T
