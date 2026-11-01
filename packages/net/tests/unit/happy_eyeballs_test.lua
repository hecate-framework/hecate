-- Happy Eyeballs (RFC 8305) in `net.connect`: attempts start 250 ms apart, or at once after a
-- failure; the first success wins and the others are cancelled. Deterministic: a virtual clock and
-- scripted `reactor.resolve` and `reactor.connect_tcp`.
local test = require("harness.test")
local core = require("hecate.core")
local reactor = require("hecate.reactor")
local net = require("hecate.net")
local T = test.Case("HappyEyeballsTest")

local ADDRESSES = {
  { ip = "192.0.2.1", family = "inet" },
  { ip = "192.0.2.2", family = "inet" },
  { ip = "192.0.2.3", family = "inet" },
}

local function refused(ip)
  return reactor.TransportError({
    message = ("connect %s: ECONNREFUSED"):format(ip),
    context = { operation = "connect " .. ip, errno = "ECONNREFUSED" },
  })
end

--- Runs `fn(state)` on a virtual-clock reactor. `script[ip]` is `{ after = seconds, fail = true? }`: the stub
--- connect sleeps `after` seconds, then fails or returns a fake stream. `state` records, per address, when the
--- attempt started, whether it was cancelled, and the fake streams (to check that they are closed).
local function run(script, fn, addresses)
  local resolve, connect_tcp = reactor.resolve, reactor.connect_tcp
  local state = { started = {}, cancelled = {}, streams = {} }
  reactor.resolve = function() return addresses or ADDRESSES end
  reactor.connect_tcp = function(ip)
    state.started[ip] = reactor.now()
    local step = script[ip]
    local slept, err = pcall(reactor.sleep, step.after)
    if not slept then
      state.cancelled[ip] = true
      error(err, 0)
    end
    if step.argument_error then error(core.ArgumentError("bad"), 0) end
    if step.fail then error(refused(ip), 0) end
    local stream = { ip = ip, closed = false }
    function stream:close() self.closed = true end
    state.streams[#state.streams + 1] = stream
    return stream
  end
  local ok, result = pcall(function()
    return reactor.Reactor({ clock = "virtual" }):run(function() return fn(state) end)
  end)
  reactor.resolve, reactor.connect_tcp = resolve, connect_tcp
  if not ok then error(result, 0) end
  return result, state
end

local function approx(self, expected, actual)
  self:assert_true(math.abs(expected - actual) < 1e-9, ("expected %s, got %s"):format(expected, actual))
end

function T:test_a_fast_first_address_wins_and_the_others_are_never_started()
  local ip, state = run({ ["192.0.2.1"] = { after = 0.1 } }, function()
    local stream = net.connect("example.test", 80)
    return stream._inner.ip
  end)
  self:assert_equal("192.0.2.1", ip)
  self:assert_nil(state.started["192.0.2.2"])
end

function T:test_a_silent_first_address_gives_way_to_the_second_after_250_ms()
  local result, state = run({
    ["192.0.2.1"] = { after = 100 }, ["192.0.2.2"] = { after = 0 },
  }, function()
    local stream = net.connect("example.test", 80)
    return { ip = stream._inner.ip, at = reactor.now() }
  end)
  self:assert_equal("192.0.2.2", result.ip)
  approx(self, 0.25, result.at)
  approx(self, 0.25, state.started["192.0.2.2"])
  self:assert_true(state.cancelled["192.0.2.1"], "the slow attempt is cancelled")
  self:assert_nil(state.started["192.0.2.3"])
end

function T:test_a_failure_starts_the_next_attempt_at_once()
  local result, state = run({
    ["192.0.2.1"] = { after = 0.1, fail = true }, ["192.0.2.2"] = { after = 0.05 },
  }, function()
    local stream = net.connect("example.test", 80)
    return { ip = stream._inner.ip, at = reactor.now() }
  end)
  self:assert_equal("192.0.2.2", result.ip)
  approx(self, 0.1, state.started["192.0.2.2"])
  approx(self, 0.15, result.at)
end

function T:test_the_first_attempt_may_still_win_after_the_second_started()
  local result, state = run({
    ["192.0.2.1"] = { after = 0.3 }, ["192.0.2.2"] = { after = 100 },
  }, function()
    local stream = net.connect("example.test", 80)
    return { ip = stream._inner.ip, at = reactor.now() }
  end)
  self:assert_equal("192.0.2.1", result.ip)
  approx(self, 0.3, result.at)
  self:assert_true(state.cancelled["192.0.2.2"])
end

function T:test_a_connection_that_loses_the_race_is_closed()
  local result, state = run({
    -- Binary-exact durations: the second attempt starts at 0.25 and, like the first, completes at 0.5.
    ["192.0.2.1"] = { after = 0.5 }, ["192.0.2.2"] = { after = 0.25 },
  }, function()
    local stream = net.connect("example.test", 80)
    return stream._inner.ip
  end)
  self:assert_true(result == "192.0.2.1" or result == "192.0.2.2")
  self:assert_equal(2, #state.streams)
  local open = 0
  for _, stream in ipairs(state.streams) do
    if not stream.closed then open = open + 1 end
  end
  self:assert_equal(1, open) -- only the winner stays open
end

function T:test_when_every_attempt_fails_the_last_address_is_reported_with_all_attempts()
  local _, state = run({
    ["192.0.2.1"] = { after = 0.1, fail = true }, ["192.0.2.2"] = { after = 0.1, fail = true },
    ["192.0.2.3"] = { after = 0.1, fail = true },
  }, function()
    local err = self:assert_error(function() net.connect("example.test", 80) end)
    self:assert_true(core.is_instance_of(err, reactor.TransportError), tostring(err))
    self:assert_equal("ECONNREFUSED", err.context.errno)
    self:assert_equal(3, #err.context.attempts)
    self:assert_equal("192.0.2.1", err.context.attempts[1].address)
    self:assert_equal("192.0.2.3", err.context.attempts[3].address)
    self:assert_true(tostring(err):find("192.0.2.1, 192.0.2.2, 192.0.2.3", 1, true) ~= nil, tostring(err))
  end)
  self:assert_equal(3, (function() local n = 0 for _ in pairs(state.started) do n = n + 1 end return n end)())
end

function T:test_a_misuse_error_propagates_and_cancels_the_other_attempts()
  local _, state = run({
    ["192.0.2.1"] = { after = 100 }, ["192.0.2.2"] = { after = 0, argument_error = true },
  }, function()
    local err = self:assert_error(function() net.connect("example.test", 80) end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
  end)
  self:assert_true(state.cancelled["192.0.2.1"])
end

function T:test_a_deadline_cancels_every_attempt()
  local _, state = run({
    ["192.0.2.1"] = { after = 100 }, ["192.0.2.2"] = { after = 100 }, ["192.0.2.3"] = { after = 100 },
  }, function()
    local err = self:assert_error(function() reactor.deadline(1, net.connect, "example.test", 80) end)
    self:assert_true(core.is_instance_of(err, core.DeadlineExceededError), tostring(err))
    approx(self, 1, reactor.now())
  end)
  for _, ip in ipairs({ "192.0.2.1", "192.0.2.2", "192.0.2.3" }) do
    self:assert_true(state.cancelled[ip], ip)
  end
end

function T:test_a_single_address_is_a_plain_attempt()
  local result = run({ ["192.0.2.1"] = { after = 1 } }, function()
    local stream = net.connect("example.test", 80)
    return { ip = stream._inner.ip, at = reactor.now() }
  end, { ADDRESSES[1] })
  approx(self, 1, result.at)
end

return T
