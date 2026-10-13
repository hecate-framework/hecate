---@diagnostic disable: param-type-mismatch, assign-type-mismatch  -- the tests pass invalid arguments on purpose
local test = require("harness.test")
local core = require("hecate.core")
local reactor = require("hecate.reactor")
local T = test.Case("DnsTest")

function T:test_a_numeric_address_resolves_to_itself()
  local answer = reactor.run(function() return reactor.resolve("127.0.0.1") end)
  self:assert_equal(1, #answer)
  self:assert_equal("127.0.0.1", answer[1].ip)
  self:assert_equal("inet", answer[1].family)
end

function T:test_localhost_resolves_to_loopback_addresses()
  local answer = reactor.run(function() return reactor.resolve("localhost") end)
  self:assert_true(#answer >= 1)
  for _, entry in ipairs(answer) do
    self:assert_true(entry.ip == "127.0.0.1" or entry.ip == "::1", entry.ip)
  end
  local v4 = reactor.run(function() return reactor.resolve("localhost", { family = "inet" }) end)
  for _, entry in ipairs(v4) do self:assert_equal("inet", entry.family) end
end

function T:test_an_unknown_name_raises_a_network_error()
  local err = self:assert_error(function()
    reactor.run(function() reactor.resolve("no-such-host.invalid") end)
  end)
  self:assert_true(core.is_instance_of(err, reactor.TransportError), tostring(err))
  self:assert_true(core.is_instance_of(err, core.NetworkError), tostring(err))
  self:assert_false(core.is_instance_of(err, reactor.IoError), tostring(err))
  self:assert_equal("resolve", err.context.operation:match("^resolve"))
end

function T:test_arguments_are_validated()
  for _, fn in ipairs({
    function() reactor.resolve(42) end,
    function() reactor.resolve("") end,
    function() reactor.resolve("localhost", { family = "ipx" }) end,
    function() reactor.resolve("localhost", { famly = "inet" }) end,
  }) do
    local err = self:assert_error(function() reactor.run(fn) end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError))
  end
end

function T:test_a_cancelled_resolution_releases_the_caller_and_leaks_nothing()
  local before = reactor.Reactor.open_handles()
  reactor.run(function()
    local resolver = reactor.fork(function() return reactor.resolve("localhost") end)
    reactor.fork(function() resolver:cancel() end)
    self:assert_error(function() resolver:value() end)
    self:assert_equal("cancelled", resolver:state())
    reactor.sleep(0.05) -- lets the late result arrive and be discarded
    local again = reactor.resolve("127.0.0.1") -- the reactor is still healthy
    self:assert_equal("127.0.0.1", again[1].ip)
  end)
  self:assert_equal(before, reactor.Reactor.open_handles())
end

function T:test_a_deadline_bounds_a_resolution()
  reactor.run(function()
    local ok, err = pcall(reactor.deadline, 5, function() return reactor.resolve("localhost") end)
    self:assert_true(ok, tostring(err))
  end)
end

function T:test_resolution_requires_a_managed_coroutine()
  local err = self:assert_error(function() reactor.resolve("localhost") end)
  self:assert_true(core.is_instance_of(err, core.NonYieldableContextError))
end

return T
