---@diagnostic disable: param-type-mismatch  -- the tests pass invalid arguments on purpose
local test = require("harness.test")
local core = require("hecate.core")
local reactor = require("hecate.reactor")
local net = require("hecate.net")
local T = test.Case("NetUdpTest")

function T:test_bind_udp_resolves_and_round_trips()
  local before = reactor.Reactor.open_handles()
  local result = reactor.run(function()
    -- "localhost" is pinned to IPv4: it may resolve to ::1 first, and the client must use the server's family.
    local server <close> = net.bind_udp("localhost", 0, { family = "inet" })
    local client <close> = net.bind_udp(server:local_address().ip, 0)
    local port = server:local_address().port
    client:send_to(server:local_address().ip, port, "hello")
    local data, from = server:receive_from()
    return { data = data, ip = from.ip, closed = server:is_closed() }
  end)
  self:assert_equal(before, reactor.Reactor.open_handles())
  self:assert_equal("hello", result.data)
  self:assert_false(result.closed)
end

function T:test_bind_udp_validates_arguments()
  reactor.run(function()
    self:assert_true(core.is_instance_of(self:assert_error(function() net.bind_udp("", 0) end), core.ArgumentError))
    self:assert_true(core.is_instance_of(self:assert_error(function() net.bind_udp("127.0.0.1", 70000) end), core.ArgumentError))
  end)
end

function T:test_resolve_numeric_and_invalid()
  reactor.run(function()
    local addresses = net.resolve("127.0.0.1", { family = "inet" })
    self:assert_equal("127.0.0.1", addresses[1].ip)
    self:assert_true(core.is_instance_of(self:assert_error(function() net.resolve("") end), core.ArgumentError))
  end)
end

function T:test_bind_udp_takes_a_family_and_rejects_other_options()
  reactor.run(function()
    local socket <close> = net.bind_udp("localhost", 0, { family = "inet" })
    self:assert_equal("127.0.0.1", socket:local_address().ip)
    for _, options in ipairs({ { reuseport = true }, 42 }) do
      local err = self:assert_error(function() net.bind_udp("127.0.0.1", 0, options) end)
      self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
    end
  end)
end

function T:test_a_cancelled_receive_keeps_the_socket_open_and_loses_no_datagram()
  local before = reactor.Reactor.open_handles()
  reactor.run(function()
    local server <close> = net.bind_udp("127.0.0.1", 0)
    local client <close> = net.bind_udp("127.0.0.1", 0)
    local port = server:local_address().port
    local ok, err = pcall(reactor.deadline, 0.02, function() return server:receive_from() end)
    self:assert_false(ok)
    self:assert_true(core.is_instance_of(err, core.DeadlineExceededError), tostring(err))
    self:assert_false(server:is_closed())
    client:send_to("127.0.0.1", port, "after")
    local data = server:receive_from()
    self:assert_equal("after", data)
  end)
  self:assert_equal(before, reactor.Reactor.open_handles())
end

function T:test_closing_wakes_a_pending_receive_with_ecanceled()
  reactor.run(function()
    local server <close> = net.bind_udp("127.0.0.1", 0)
    local parked = reactor.Channel(1)
    local receiver = reactor.fork(function()
      -- Cooperative scheduling: the closer below runs only after this coroutine parked in `receive_from`.
      parked:send(true)
      return pcall(server.receive_from, server)
    end)
    parked:receive()
    server:close()
    server:close()
    self:assert_true(server:is_closed())
    local ok, err = receiver:value()
    self:assert_false(ok)
    self:assert_true(core.is_instance_of(err, reactor.TransportError), tostring(err))
    self:assert_equal("ECANCELED", err.context.errno)
  end)
end

function T:test_an_empty_datagram_is_delivered_as_an_empty_string()
  reactor.run(function()
    local server <close> = net.bind_udp("127.0.0.1", 0)
    local client <close> = net.bind_udp("127.0.0.1", 0)
    local port = server:local_address().port
    client:send_to("127.0.0.1", port, "")
    local data, from = server:receive_from()
    self:assert_equal("", data)
    self:assert_equal(client:local_address().port, from.port)
  end)
end

function T:test_datagram_boundaries_are_kept()
  reactor.run(function()
    local server <close> = net.bind_udp("127.0.0.1", 0)
    local client <close> = net.bind_udp("127.0.0.1", 0)
    local port = server:local_address().port
    local sent = { "one", "", string.rep("x", 1200), "four" }
    for _, payload in ipairs(sent) do client:send_to("127.0.0.1", port, payload) end
    for _, payload in ipairs(sent) do
      local data = server:receive_from()
      self:assert_equal(#payload, #data) -- never merged with, or split from, its neighbours
      self:assert_true(data == payload)
    end
  end)
end

function T:test_send_to_refuses_names_and_malformed_arguments_pointing_to_resolve()
  reactor.run(function()
    local socket <close> = net.bind_udp("127.0.0.1", 0)
    local err = self:assert_error(function() socket:send_to("localhost", 9, "x") end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
    self:assert_true(tostring(err):find("net.resolve", 1, true) ~= nil, tostring(err))
    for _, case in ipairs({
      { 42, 9, "x" }, { "", 9, "x" }, { "example.org", 9, "x" }, { "999.1.1.1", 9, "x" }, { "1.2.3", 9, "x" },
      { "127.0.0.1", 0, "x" }, { "127.0.0.1", 70000, "x" }, { "127.0.0.1", 1.5, "x" }, { "127.0.0.1", "9", "x" },
      { "127.0.0.1", 9, 42 }, { "127.0.0.1", 9, nil },
    }) do
      local failure = self:assert_error(function() socket:send_to(case[1], case[2], case[3]) end)
      self:assert_true(core.is_instance_of(failure, core.ArgumentError), tostring(failure))
    end
    -- Numeric addresses of both families are accepted by the validation (IPv6 may not be routable here).
    local server <close> = net.bind_udp("127.0.0.1", 0)
    socket:send_to("127.0.0.1", server:local_address().port, "ok")
    self:assert_equal("ok", (server:receive_from()))
  end)
end

function T:test_send_to_raises_a_transport_error_for_an_oversized_datagram()
  reactor.run(function()
    local server <close> = net.bind_udp("127.0.0.1", 0)
    local client <close> = net.bind_udp("127.0.0.1", 0)
    local port = server:local_address().port
    local err = self:assert_error(function() client:send_to("127.0.0.1", port, string.rep("x", 70000)) end)
    self:assert_true(core.is_instance_of(err, reactor.TransportError), tostring(err))
    self:assert_equal("EMSGSIZE", err.context.errno)
    self:assert_false(client:is_closed()) -- a refused send is not a cancelled one
  end)
end

function T:test_a_closed_socket_raises_ebadf()
  reactor.run(function()
    local socket = net.bind_udp("127.0.0.1", 0)
    socket:close()
    for _, call in ipairs({
      function() socket:receive_from() end,
      function() socket:send_to("127.0.0.1", 9, "x") end,
    }) do
      local err = self:assert_error(call)
      self:assert_true(core.is_instance_of(err, reactor.TransportError), tostring(err))
      self:assert_equal("EBADF", err.context.errno)
    end
  end)
end

function T:test_the_socket_is_closed_by_its_scope()
  local before = reactor.Reactor.open_handles()
  local kept = reactor.run(function()
    local socket
    do
      local scoped <close> = net.bind_udp("127.0.0.1", 0)
      socket = scoped
      self:assert_false(socket:is_closed())
    end
    return socket:is_closed()
  end)
  self:assert_true(kept)
  self:assert_equal(before, reactor.Reactor.open_handles())
end

return T
