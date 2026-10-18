---@diagnostic disable: param-type-mismatch  -- the tests pass invalid arguments on purpose
local test = require("harness.test")
local core = require("hecate.core")
local reactor = require("hecate.reactor")
local T = test.Case("UdpTest")

local LOOPBACK = "127.0.0.1"

--- Runs `fn` on a reactor and checks that no libuv handle is left open.
local function run(self, fn)
  local before = reactor.Reactor.open_handles()
  local result = reactor.run(fn)
  self:assert_equal(before, reactor.Reactor.open_handles())
  return result
end

function T:test_datagram_round_trip_with_sender_address()
  local result = run(self, function()
    local server <close> = reactor.udp_bind(LOOPBACK, 0)
    local client <close> = reactor.udp_bind(LOOPBACK, 0)
    client:send_to(LOOPBACK, server:local_address().port, "ping")
    local data, from = server:receive_from()
    server:send_to(from.ip, from.port, data:upper())
    local reply, back = client:receive_from()
    return { data = data, from = from, reply = reply, back = back, client_port = client:local_address().port,
      server_port = server:local_address().port }
  end)
  self:assert_equal("ping", result.data)
  self:assert_equal("PING", result.reply)
  self:assert_equal(LOOPBACK, result.from.ip)
  self:assert_equal("inet", result.from.family)
  self:assert_equal(result.client_port, result.from.port)
  self:assert_equal(result.server_port, result.back.port)
end

function T:test_receive_suspends_until_a_datagram_arrives()
  local data = run(self, function()
    local server <close> = reactor.udp_bind(LOOPBACK, 0)
    local port = server:local_address().port
    reactor.fork(function()
      local client <close> = reactor.udp_bind(LOOPBACK, 0)
      -- Send only once the receiver is parked (bounded poll, no fixed delay).
      for _ = 1, 5000 do
        if server._receiving then break end ---@diagnostic disable-line: invisible
        reactor.sleep(0.001)
      end
      client:send_to(LOOPBACK, port, "late")
    end)
    return (server:receive_from())
  end)
  self:assert_equal("late", data)
end

function T:test_cancelled_receive_keeps_socket_and_loses_nothing()
  local data = run(self, function()
    local server <close> = reactor.udp_bind(LOOPBACK, 0)
    local port = server:local_address().port
    local ok = pcall(reactor.deadline, 0.02, function() server:receive_from() end)
    local client <close> = reactor.udp_bind(LOOPBACK, 0)
    client:send_to(LOOPBACK, port, "after")
    return { ok = ok, data = (server:receive_from()), closed = server:is_closed() }
  end)
  self:assert_false(data.ok)
  self:assert_false(data.closed)
  self:assert_equal("after", data.data)
end

function T:test_close_wakes_a_waiting_receiver_with_transport_error()
  local err = run(self, function()
    local server = reactor.udp_bind(LOOPBACK, 0)
    local waiter = reactor.fork(function() return pcall(server.receive_from, server) end)
    for _ = 1, 5000 do -- let the receiver park (bounded poll)
      if server._receiving then break end ---@diagnostic disable-line: invisible
      reactor.sleep(0.001)
    end
    self:assert_true(server._receiving, "the receiver parked") ---@diagnostic disable-line: invisible
    server:close()
    server:close() -- idempotent
    local ok, e = waiter:value()
    return ok and nil or e
  end)
  self:assert_true(core.is_instance_of(err, reactor.TransportError), tostring(err))
  self:assert_equal("ECANCELED", err.context.errno)
end

function T:test_closed_socket_raises_ebadf()
  run(self, function()
    local socket = reactor.udp_bind(LOOPBACK, 0)
    socket:close()
    local err = self:assert_error(function() socket:send_to(LOOPBACK, 9, "x") end)
    self:assert_equal("EBADF", err.context.errno)
  end)
end

function T:test_invalid_arguments_and_bind_failure()
  run(self, function()
    local taken <close> = reactor.udp_bind(LOOPBACK, 0)
    local err = self:assert_error(function() reactor.udp_bind(LOOPBACK, taken:local_address().port) end)
    self:assert_true(core.is_instance_of(err, reactor.TransportError), tostring(err))
    err = self:assert_error(function() reactor.udp_bind("not-an-address", 0) end)
    self:assert_equal("EINVAL", err.context.errno)
    self:assert_true(core.is_instance_of(self:assert_error(function() reactor.udp_bind(LOOPBACK, -1) end), core.ArgumentError))
    self:assert_true(core.is_instance_of(self:assert_error(function() taken:send_to(LOOPBACK, 9, 1) end), core.ArgumentError))
  end)
end

return T
