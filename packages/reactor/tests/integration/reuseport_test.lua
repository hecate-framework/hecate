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

function T:test_an_unsupported_platform_raises_enotsup_instead_of_ignoring_the_option()
  without_reuseport_support(function()
    tcp.reset_reuseport_probe()
    self:assert_false(reactor.supports_reuseport())
    reactor.run(function()
      local before = reactor.Reactor.open_handles()
      local err = self:assert_error(function() reactor.tcp_listen(LOOPBACK, 0, { reuseport = true }) end)
      self:assert_true(core.is_instance_of(err, reactor.TransportError), tostring(err))
      self:assert_equal("ENOTSUP", err.context.errno)
      self:assert_equal(before, reactor.Reactor.open_handles())
      -- Without the option nothing changes.
      reactor.tcp_listen(LOOPBACK, 0):close()
    end)
  end)
end

function T:test_the_option_is_validated()
  reactor.run(function()
    ---@diagnostic disable-next-line: assign-type-mismatch  -- the point is to pass a wrong type
    local err = self:assert_error(function() reactor.tcp_listen(LOOPBACK, 0, { reuseport = "yes" }) end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError))
  end)
end

function T:test_a_port_in_use_is_refused_without_reuseport_and_when_mixing_modes()
  reactor.run(function()
    local plain <close> = reactor.tcp_listen(LOOPBACK, 0)
    local port = plain:local_address().port
    self:assert_equal("EADDRINUSE", errno_of(self, function() reactor.tcp_listen(LOOPBACK, port) end))
    if not reactor.supports_reuseport() then return end
    -- A reuseport socket cannot join a plain one, nor the other way round.
    self:assert_equal("EADDRINUSE",
      errno_of(self, function() reactor.tcp_listen(LOOPBACK, port, { reuseport = true }) end))
    local shared <close> = reactor.tcp_listen(LOOPBACK, 0, { reuseport = true })
    self:assert_equal("EADDRINUSE",
      errno_of(self, function() reactor.tcp_listen(LOOPBACK, shared:local_address().port) end))
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
    local a <close> = reactor.tcp_listen(LOOPBACK, 0, { reuseport = true })
    local port = a:local_address().port
    local b <close> = reactor.tcp_listen(LOOPBACK, port, { reuseport = true })
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
    for index = 1, total do clients[index] = reactor.tcp_connect(LOOPBACK, port) end
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
