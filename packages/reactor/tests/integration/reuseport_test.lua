local test = require("harness.test")
local core = require("hecate.core")
local uv = require("luv")
local reactor = require("hecate.reactor")
local tcp = require("hecate.reactor.tcp")
local T = test.Case("ReuseportTest")

local LOOPBACK = "127.0.0.1"

function T:tear_down()
  tcp.reset_reuseport_probe() -- never leave a probe made under a stub behind
end

local function errno_of(self, fn)
  local err = self:assert_error(fn)
  self:assert_true(core.is_instance_of(err, reactor.TransportError), tostring(err))
  return err.context.errno
end

--- Makes `bind` of TCP handles fail when it is given flags (the `reuseport` request), then runs `fn`.
local function without_reuseport_support(fn)
  local probe = uv.new_tcp()
  local methods = getmetatable(probe).__index
  probe:close()
  local original = methods.bind
  methods.bind = function(handle, host, port, flags)
    if flags ~= nil then return nil, "ENOTSUP: operation not supported" end
    return original(handle, host, port, flags)
  end
  local ok, err = pcall(fn)
  methods.bind = original
  if not ok then error(err, 0) end
end

function T:test_the_probe_is_cached_and_leaves_no_handle()
  tcp.reset_reuseport_probe()
  local before = reactor.Reactor.open_handles()
  local created = 0
  local original = uv.new_tcp
  uv.new_tcp = function(...) created = created + 1; return original(...) end
  local ok, first, second = pcall(function() return reactor.supports_reuseport(), reactor.supports_reuseport() end)
  local calls_after_first = created
  pcall(reactor.supports_reuseport)
  local calls_after_third = created
  uv.new_tcp = original
  self:assert_true(ok, tostring(first))
  self:assert_equal("boolean", type(first))
  self:assert_equal(first, second)
  self:assert_equal(2, calls_after_first, "one probe, two sockets")
  self:assert_equal(calls_after_first, calls_after_third, "the answer is cached")
  self:assert_equal(before, reactor.Reactor.open_handles())
end

--- Replaces `bind` of TCP handles by `stub(original, handle, host, port, flags)` while `fn` runs.
local function with_bind(stub, fn)
  local probe = uv.new_tcp()
  local methods = getmetatable(probe).__index
  probe:close()
  local original = methods.bind
  methods.bind = function(handle, host, port, flags) return stub(original, handle, host, port, flags) end
  local ok, err = pcall(fn)
  methods.bind = original
  if not ok then error(err, 0) end
end

function T:test_a_port_refused_to_the_second_socket_is_a_definite_answer_and_cached()
  tcp.reset_reuseport_probe()
  local before = reactor.Reactor.open_handles()
  local binds = 0
  with_bind(function(original, handle, host, port, flags)
    binds = binds + 1
    if flags ~= nil and port ~= 0 then return nil, "EADDRINUSE: address already in use" end
    return original(handle, host, port, flags)
  end, function()
    self:assert_false(reactor.supports_reuseport())
    local after_first = binds
    self:assert_false(reactor.supports_reuseport())
    self:assert_equal(after_first, binds, "the definite answer is cached")
  end)
  self:assert_equal(before, reactor.Reactor.open_handles())
end

function T:test_a_failed_probe_answers_false_without_caching()
  tcp.reset_reuseport_probe()
  local before = reactor.Reactor.open_handles()
  local binds = 0
  with_bind(function(original, handle, host, port, flags)
    binds = binds + 1
    if flags ~= nil then return nil, "EMFILE: too many open files" end
    return original(handle, host, port, flags)
  end, function()
    self:assert_false(reactor.supports_reuseport())
    local after_first = binds
    self:assert_false(reactor.supports_reuseport())
    self:assert_true(binds > after_first, "a failed probe is not cached")
  end)
  self:assert_equal(before, reactor.Reactor.open_handles())
  -- Once the failure is gone the real answer comes, and agrees with a fresh probe.
  local answer = reactor.supports_reuseport()
  tcp.reset_reuseport_probe()
  self:assert_equal(reactor.supports_reuseport(), answer)
end

function T:test_the_probe_tries_the_ipv6_loopback_when_the_ipv4_one_fails()
  tcp.reset_reuseport_probe()
  local before = reactor.Reactor.open_handles()
  local hosts = {}
  with_bind(function(original, handle, host, port, flags)
    hosts[host] = true
    if host == "127.0.0.1" then return nil, "EADDRNOTAVAIL: address not available" end
    return original(handle, host, port, flags)
  end, function()
    self:assert_equal("boolean", type(reactor.supports_reuseport()))
  end)
  self:assert_true(hosts["::1"], "the IPv6 loopback was tried")
  self:assert_equal(before, reactor.Reactor.open_handles())
end

function T:test_an_unsupported_platform_raises_enotsup_instead_of_ignoring_the_option()
  without_reuseport_support(function()
    tcp.reset_reuseport_probe()
    self:assert_false(reactor.supports_reuseport())
    reactor.run(function()
      local before = reactor.Reactor.open_handles()
      local err = self:assert_error(function() reactor.listen_tcp(LOOPBACK, 0, { reuseport = true }) end)
      self:assert_true(core.is_instance_of(err, reactor.TransportError), tostring(err))
      self:assert_equal("ENOTSUP", err.context.errno)
      self:assert_equal(before, reactor.Reactor.open_handles())
      -- Without the option nothing changes.
      reactor.listen_tcp(LOOPBACK, 0):close()
    end)
  end)
end

function T:test_the_option_is_validated()
  reactor.run(function()
    ---@diagnostic disable-next-line: assign-type-mismatch  -- the point is to pass a wrong type
    local err = self:assert_error(function() reactor.listen_tcp(LOOPBACK, 0, { reuseport = "yes" }) end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError))
  end)
end

function T:test_a_port_in_use_is_refused_without_reuseport_and_when_mixing_modes()
  reactor.run(function()
    local plain <close> = reactor.listen_tcp(LOOPBACK, 0)
    local port = plain:local_address().port
    self:assert_equal("EADDRINUSE", errno_of(self, function() reactor.listen_tcp(LOOPBACK, port) end))
    if not reactor.supports_reuseport() then return end
    -- A reuseport socket cannot join a plain one, nor the other way round.
    self:assert_equal("EADDRINUSE",
      errno_of(self, function() reactor.listen_tcp(LOOPBACK, port, { reuseport = true }) end))
    local shared <close> = reactor.listen_tcp(LOOPBACK, 0, { reuseport = true })
    self:assert_equal("EADDRINUSE",
      errno_of(self, function() reactor.listen_tcp(LOOPBACK, shared:local_address().port) end))
  end)
end

function T:test_both_sockets_of_a_shared_port_accept_connections()
  if not reactor.supports_reuseport() then
    print("SKIP " .. self.name .. ": this platform or luv has no TCP reuseport")
    return
  end
  if uv.os_uname().sysname == "Darwin" then
    print("SKIP " .. self.name .. ": macOS accepts the flag but gives every connection to one socket")
    return
  end
  local before = reactor.Reactor.open_handles()
  local seen = reactor.run(function()
    local a <close> = reactor.listen_tcp(LOOPBACK, 0, { reuseport = true })
    local port = a:local_address().port
    local b <close> = reactor.listen_tcp(LOOPBACK, port, { reuseport = true })
    local counts = { a = 0, b = 0 }
    local accepted = reactor.Channel(256)
    for name, listener in pairs({ a = a, b = b }) do
      reactor.fork(function()
        while true do
          local ok, stream = pcall(listener.accept, listener)
          if not ok then return end
          stream:close()
          counts[name] = counts[name] + 1
          accepted:send(true)
        end
      end)
    end
    local clients = {}
    local total = 100 -- the kernel hashes each connection: all on one socket has probability 2^-99
    for index = 1, total do clients[index] = reactor.connect_tcp(LOOPBACK, port) end
    for _ = 1, total do accepted:receive() end
    for _, client in ipairs(clients) do client:close() end
    a:close()
    b:close()
    return counts
  end)
  self:assert_true(seen.a > 0 and seen.b > 0, ("a accepted %d, b accepted %d"):format(seen.a, seen.b))
  self:assert_equal(100, seen.a + seen.b)
  self:assert_equal(before, reactor.Reactor.open_handles())
end

return T
