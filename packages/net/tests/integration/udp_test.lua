---@diagnostic disable: param-type-mismatch  -- the tests pass invalid arguments on purpose
local test = require("harness.test")
local core = require("hecate.core")
local reactor = require("hecate.reactor")
local net = require("hecate.net")
local T = test.Case("NetUdpTest")

function T:test_bind_udp_resolves_and_round_trips()
  local before = reactor.Reactor.open_handles()
  local result = reactor.run(function()
    local server <close> = net.bind_udp("localhost", 0)
    local client <close> = net.bind_udp("127.0.0.1", 0)
    local port = server:local_address().port
    client:send_to("hello", server:local_address().ip, port)
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

return T
