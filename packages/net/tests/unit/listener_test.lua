---@diagnostic disable: undefined-field, param-type-mismatch  -- scripted fake sockets and streams
-- `TcpListener` over several scripted reactor sockets, and `net.listen` over a scripted `reactor.listen_tcp`:
-- no live socket, so the interleavings are deterministic.
local test = require("harness.test")
local core = require("hecate.core")
local reactor = require("hecate.reactor")
local net = require("hecate.net")
local T = test.Case("ListenerTest")

local function failure(errno)
  return reactor.TransportError({
    message = errno .. ": scripted", context = { operation = "accept", errno = errno },
  })
end

--- A reactor-listener stand-in. `script.accept()` returns the stream or raises; `script.port` the bound port.
local function fake_socket(script)
  local socket = { closed = false, accepted = {} }
  function socket:accept()
    local result = script.accept(self)
    self.accepted[#self.accepted + 1] = result
    return result
  end
  function socket:close() self.closed = true end
  function socket:is_closed() return self.closed end
  function socket:local_address() return { ip = "127.0.0.1", port = script.port or 1 } end
  return socket
end

local function fake_stream()
  local stream = { closed = false }
  function stream:close() self.closed = true end
  return stream
end

function T:test_a_close_during_a_multi_socket_accept_closes_every_taken_stream()
  local first, second = fake_stream(), fake_stream()
  local listener
  local one = fake_socket({ accept = function() return first end })
  local two = fake_socket({ accept = function() listener:close(); return second end })
  listener = net.TcpListener({ one, two })
  reactor.run(function()
    local err = self:assert_error(function() listener:accept() end)
    self:assert_true(core.is_instance_of(err, reactor.TransportError), tostring(err))
  end)
  self:assert_true(first.closed, "the stream accepted first is closed")
  self:assert_true(second.closed, "the extra stream is closed, not queued")
  self:assert_equal(0, #listener._ready)
end

function T:test_a_failure_next_to_a_taken_connection_is_kept_for_the_next_accept()
  local stream = fake_stream()
  local one = fake_socket({ accept = function() return stream end })
  local two = fake_socket({ accept = function() error(failure("EMFILE"), 0) end })
  local listener = net.TcpListener({ one, two })
  reactor.run(function()
    local accepted = listener:accept()
    self:assert_equal(stream, accepted._inner)
    local err = self:assert_error(function() listener:accept() end)
    self:assert_equal("EMFILE", err.context.errno)
  end)
end

function T:test_a_kept_failure_is_dropped_when_the_listener_closes()
  local one = fake_socket({ accept = function() return fake_stream() end })
  local two = fake_socket({ accept = function() error(failure("ECONNABORTED"), 0) end })
  local listener = net.TcpListener({ one, two })
  reactor.run(function()
    listener:accept():close()
    listener:close()
    local err = self:assert_error(function() listener:accept() end)
    self:assert_equal("EBADF", err.context.errno)
    self:assert_equal("accept", err.context.operation)
    self:assert_true(tostring(err):find("listener is closed", 1, true) ~= nil, tostring(err))
  end)
end

--- Runs `fn` with `reactor.listen_tcp` scripted: `script(ip, port, attempt)` returns a fake socket or raises.
local function scripted_listen(addresses, script, fn)
  local resolve, listen_tcp = reactor.resolve, reactor.listen_tcp
  local calls = {}
  reactor.resolve = function() return addresses end
  reactor.listen_tcp = function(ip, port, options)
    calls[#calls + 1] = { ip = ip, port = port }
    return script(ip, port, #calls)
  end
  local ok, result = pcall(function() return reactor.run(function() return fn(calls) end) end)
  reactor.resolve, reactor.listen_tcp = resolve, listen_tcp
  if not ok then error(result, 0) end
  return result
end

local TWO = { { ip = "127.0.0.1", family = "inet" }, { ip = "::1", family = "inet6" } }

local function addr_in_use()
  return reactor.TransportError({ message = "EADDRINUSE", context = { operation = "listen", errno = "EADDRINUSE" } })
end

function T:test_listen_retries_the_whole_bind_set_when_the_chosen_port_is_busy_on_a_later_address()
  local bound = {}
  scripted_listen(TWO, function(ip, port)
    if ip == "::1" and port == 1111 then error(addr_in_use(), 0) end
    local socket = fake_socket({ port = port == 0 and (#bound < 1 and 1111 or 2222) or port })
    bound[#bound + 1] = socket
    return socket
  end, function(calls)
    local listener = net.listen("localhost", 0)
    self:assert_equal(4, #calls) -- 127.0.0.1:0, ::1:1111 (busy), then both again
    self:assert_equal(0, calls[3].port)
    self:assert_equal(2222, calls[4].port)
    self:assert_true(bound[1].closed, "the socket of the failed set is closed")
    self:assert_false(bound[2].closed)
    self:assert_false(bound[3].closed)
    self:assert_equal(2, #listener._sockets)
  end)
end

function T:test_listen_gives_up_after_five_attempts_and_closes_every_socket()
  local bound = {}
  scripted_listen(TWO, function(ip, port)
    if ip == "::1" then error(addr_in_use(), 0) end
    local socket = fake_socket({ port = 4000 + #bound })
    bound[#bound + 1] = socket
    return socket
  end, function(calls)
    local err = self:assert_error(function() net.listen("localhost", 0) end)
    self:assert_equal("EADDRINUSE", err.context.errno)
    self:assert_equal(10, #calls)
    self:assert_equal(5, #bound)
    for _, socket in ipairs(bound) do self:assert_true(socket.closed) end
  end)
end

function T:test_listen_does_not_retry_for_a_fixed_port()
  scripted_listen(TWO, function(ip)
    if ip == "::1" then error(addr_in_use(), 0) end
    return fake_socket({})
  end, function(calls)
    local err = self:assert_error(function() net.listen("localhost", 8080) end)
    self:assert_equal("EADDRINUSE", err.context.errno)
    self:assert_equal(2, #calls)
  end)
end

function T:test_listen_closes_the_sockets_bound_when_local_address_raises()
  local socket = fake_socket({})
  socket.local_address = function() error(failure("EBADF"), 0) end
  scripted_listen(TWO, function() return socket end, function()
    self:assert_error(function() net.listen("localhost", 0) end)
    self:assert_true(socket.closed)
  end)
end

return T
