---@diagnostic disable: need-check-nil, missing-fields, undefined-field, param-type-mismatch
local test = require("harness.test")
local core = require("hecate.core")
local net = require("hecate.net")
local reactor = require("hecate.reactor")
local log = require("hecate.log")
local listening = require("hecate.kernel.listening")
local T = test.Case("ListeningTest")

--- Reads a stream to its end.
local function read_all(stream)
  local parts = {}
  while true do
    local chunk = stream:read(4096)
    if chunk == nil or chunk == "" then return table.concat(parts) end
    parts[#parts + 1] = chunk
  end
end

--- Runs `fn` on a reactor with a virtual clock: no I/O, and `sleep` or a deadline costs no real time.
local function virtual(fn)
  return reactor.Reactor({ clock = "virtual" }):run(fn)
end

function T:test_auto_is_reuseport_on_linux_with_reuseport()
  local strategy, reason = listening.select("auto", { system = "Linux", reuseport = true })
  self:assert_equal("reuseport", strategy.name)
  self:assert_nil(reason)
end

function T:test_auto_is_round_robin_elsewhere_and_without_reuseport_silently()
  for _, case in ipairs({ { "Darwin", true }, { "Windows_NT", false }, { "Linux", false } }) do
    local strategy, reason = listening.select("auto", { system = case[1], reuseport = case[2] })
    self:assert_equal("round_robin", strategy.name)
    self:assert_nil(reason)
  end
end

function T:test_an_unsupported_named_strategy_falls_back_with_a_reason()
  local strategy, reason = listening.select("reuseport", { system = "Darwin", reuseport = true })
  self:assert_equal("round_robin", strategy.name)
  self:assert_true(reason:find("only on Linux", 1, true) ~= nil)
  strategy, reason = listening.select("reuseport", { system = "Linux", reuseport = false })
  self:assert_equal("round_robin", strategy.name)
  self:assert_true(reason:find("OQ-43", 1, true) ~= nil)
  self:assert_equal("round_robin", (listening.select("round_robin")).name)
end

function T:test_an_unknown_strategy_is_refused()
  local ok, err = pcall(listening.select, "shared")
  self:assert_false(ok)
  self:assert_true(core.is_instance_of(err, core.ArgumentError))
end

function T:test_reuseport_refuses_port_zero_and_a_malformed_endpoint()
  local strategy = listening.ReuseportStrategy({ system = "Linux", reuseport = true })
  local ok, err = pcall(strategy.prepare, strategy, { host = "127.0.0.1", port = 0 })
  self:assert_false(ok)
  self:assert_true(tostring(err):find("port 0", 1, true) ~= nil)
  ok = pcall(strategy.prepare, strategy, { host = "127.0.0.1", port = 70000 })
  self:assert_false(ok)
  self:assert_nil(strategy:prepare({ host = "127.0.0.1", port = 8080 }))
end

function T:test_the_ring_rotates_and_skips_removed_workers()
  local a, b, c = { id = "a" }, { id = "b" }, { id = "c" }
  local seen = {}
  reactor.run(function()
    local ring = listening.WorkerRing()
    ring:add(a); ring:add(b); ring:add(c); ring:add(a)
    self:assert_equal(3, ring:size())
    for _ = 1, 4 do seen[#seen + 1] = ring:next().id end
    ring:remove(b)
    for _ = 1, 3 do seen[#seen + 1] = ring:next().id end
  end)
  self:assert_equal("a,b,c,a,c,a,c", table.concat(seen, ","))
end

function T:test_the_ring_waits_for_a_worker_and_returns_nil_once_closed()
  local got, after_close
  virtual(function()
    local ring = listening.WorkerRing()
    reactor.scope(function(scope)
      local waiting = scope:fork(function() return ring:next().id end)
      reactor.sleep(0) -- the waiter is parked in `next`
      ring:add({ id = "late" })
      got = waiting:value()
      ring:remove(ring:next())
      local closing = scope:fork(function() return ring:next() end)
      reactor.sleep(0)
      ring:close()
      after_close = closing:value()
    end)
  end)
  self:assert_equal("late", got)
  self:assert_nil(after_close)
end

function T:test_closing_the_ring_wakes_a_waiting_next_with_nil_and_it_stays_closed()
  virtual(function()
    local ring = listening.WorkerRing()
    reactor.scope(function(scope)
      local first = scope:fork(function() return ring:next() end)
      reactor.sleep(0)
      ring:close()
      self:assert_nil(first:value())
    end)
    ring:add({ id = "after" }) -- a closed ring still takes members, but no longer hands any out
    self:assert_nil(ring:next())
    ring:close() -- idempotent
    self:assert_nil(ring:next())
  end)
end

function T:test_cancelling_a_waiting_next_raises_the_cancellation()
  virtual(function()
    local ring = listening.WorkerRing()
    reactor.scope(function(scope)
      local waiting = scope:fork(function() return ring:next() end)
      reactor.sleep(0)
      waiting:cancel()
      local ok, err = pcall(waiting.value, waiting)
      self:assert_false(ok)
      self:assert_true(core.is_instance_of(err, core.CancellationError), tostring(err))
    end)
  end)
end

function T:test_removing_a_worker_that_is_not_in_the_ring_changes_nothing()
  virtual(function()
    local a, b, stranger = { id = "a" }, { id = "b" }, { id = "x" }
    local ring = listening.WorkerRing()
    ring:remove(stranger) -- empty ring
    ring:add(a); ring:add(b)
    self:assert_equal("a", ring:next().id)
    ring:remove(stranger)
    self:assert_equal(2, ring:size())
    self:assert_equal("b", ring:next().id) -- the rotation went on where it was
    ring:remove(b); ring:remove(b) -- twice: the second is a no-op
    self:assert_equal(1, ring:size())
    self:assert_equal("a", ring:next().id)
  end)
end

function T:test_removing_a_worker_before_the_rotation_point_keeps_the_next_one()
  virtual(function()
    local a, b, c, d = { id = "a" }, { id = "b" }, { id = "c" }, { id = "d" }
    local ring = listening.WorkerRing()
    for _, worker in ipairs({ a, b, c, d }) do ring:add(worker) end
    self:assert_equal("a", ring:next().id)
    self:assert_equal("b", ring:next().id)
    ring:remove(a) -- served already, before the point: the next is still c
    self:assert_equal("c", ring:next().id)
    ring:remove(c) -- the one served last: the next is d
    self:assert_equal("d", ring:next().id)
    self:assert_equal("b", ring:next().id)
  end)
end

function T:test_the_ring_emptied_while_waiting_goes_on_waiting()
  virtual(function()
    local ring = listening.WorkerRing()
    local only = { id = "only" }
    ring:add(only)
    ring:remove(only)
    reactor.scope(function(scope)
      local waiting = scope:fork(function() return ring:next().id end)
      reactor.sleep(0)
      ring:add({ id = "new" })
      self:assert_equal("new", waiting:value())
    end)
  end)
end

function T:test_the_hand_over_listener_queues_wraps_and_closes()
  local accepted, queued_after_close, failure, closed_stream
  reactor.run(function()
    local server = net.listen("127.0.0.1", 0)
    local port = server:local_address().port
    local hand_over = listening.HandOverListener({ ip = "127.0.0.1", port = port, family = "inet" })
    self:assert_equal(port, hand_over:local_address().port)
    reactor.fork(function() local s = net.connect("127.0.0.1", port); s:write("hi"); s:close() end)
    local stream = server:accept()
    hand_over:push(stream._inner) -- a reactor stream, as received through `reactor.ipc`
    accepted = hand_over:accept()
    self:assert_true(core.is_instance_of(accepted, net.TcpStream))
    self:assert_equal("hi", accepted:reader():read_exact(2))
    accepted:close()
    reactor.fork(function() local s = net.connect("127.0.0.1", port); s:close() end)
    local second = server:accept()
    hand_over:close()
    queued_after_close = hand_over:push(second._inner)
    closed_stream = second:is_closed()
    local ok, err = pcall(hand_over.accept, hand_over)
    failure = not ok and err or nil
    server:close()
  end)
  self:assert_false(queued_after_close)
  self:assert_true(closed_stream)
  self:assert_true(core.is_instance_of(failure, reactor.TransportError))
  self:assert_equal("EBADF", failure.context.errno)
end

--- A stand-in for a received stream: only `close` matters to the listener when it refuses one.
local function fake_stream()
  local stream = { closed = false }
  function stream:close() self.closed = true end
  return stream
end

function T:test_the_hand_over_listener_is_bounded_and_closes_what_it_cannot_queue()
  reactor.run(function()
    local hand_over = listening.HandOverListener(nil, 2)
    self:assert_equal(2, hand_over:capacity())
    local a, b, c = fake_stream(), fake_stream(), fake_stream()
    self:assert_true((hand_over:push(a)))
    self:assert_true((hand_over:push(b)))
    local queued, reason = hand_over:push(c)
    self:assert_false(queued)
    self:assert_equal("full", reason)
    self:assert_true(c.closed)
    self:assert_false(a.closed)
    hand_over:close()
    local after, why = hand_over:push(fake_stream())
    self:assert_false(after)
    self:assert_equal("closed", why)
    self:assert_true(a.closed and b.closed)
  end)
end

function T:test_the_hand_over_listener_capacity_defaults_to_the_server_backlog_and_is_checked()
  local http = require("hecate.http")
  self:assert_equal(http.Server.DEFAULTS.backlog, listening.HandOverListener():capacity())
  for _, bad in ipairs({ 0, -1, 1.5, "8" }) do
    local ok, err = pcall(listening.HandOverListener, nil, bad)
    self:assert_false(ok)
    self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
  end
end

--- A worker of the test: takes a connection into its own hand-over listener, as a real worker's control loop does.
local function fake_worker(name, fail)
  local worker = { name = name, listener = listening.HandOverListener(), taken = 0 }
  function worker:hand_over(stream)
    if fail then error("worker " .. name .. " is gone") end
    self.taken = self.taken + 1
    self.listener:push(stream)
  end
  return worker
end

function T:test_round_robin_spreads_connections_evenly_and_workers_serve_them()
  local workers = { fake_worker("one"), fake_worker("two") }
  local answers = {}
  reactor.run(function()
    local strategy = listening.select("round_robin")
    local address = strategy:prepare({ host = "127.0.0.1", port = 0 })
    self:assert_true(address.port > 0)
    self:assert_equal(address.port, strategy:local_address().port)
    local ring = listening.WorkerRing()
    for _, worker in ipairs(workers) do ring:add(worker) end
    reactor.scope(function(scope)
      scope:fork(strategy.run, strategy, ring)
      for _, worker in ipairs(workers) do
        scope:fork(function()
          local listener = strategy:worker_listener({ endpoint = { host = "127.0.0.1", port = 0 }, hand_over = worker.listener })
          for _ = 1, 2 do
            local stream = listener:accept()
            stream:write(worker.name)
            stream:close()
          end
        end)
      end
      for i = 1, 4 do
        local client = net.connect("127.0.0.1", address.port)
        answers[i] = read_all(client)
        client:close()
      end
      strategy:close()
    end)
  end)
  self:assert_equal(2, workers[1].taken)
  self:assert_equal(2, workers[2].taken)
  self:assert_equal("one,two,one,two", table.concat(answers, ","))
end

function T:test_round_robin_tries_the_next_worker_when_one_fails()
  local broken, healthy = fake_worker("broken", true), fake_worker("healthy")
  local answer
  reactor.run(function()
    local strategy = listening.RoundRobinStrategy()
    local address = strategy:prepare({ host = "127.0.0.1", port = 0 })
    local ring = listening.WorkerRing()
    ring:add(broken); ring:add(healthy)
    reactor.scope(function(scope)
      scope:fork(strategy.run, strategy, ring)
      scope:fork(function()
        local stream = healthy.listener:accept()
        stream:write("ok")
        stream:close()
      end)
      local client = net.connect("127.0.0.1", address.port)
      answer = read_all(client)
      client:close()
      strategy:close()
    end)
  end)
  self:assert_equal("ok", answer)
  self:assert_equal(1, healthy.taken)
end

function T:test_round_robin_returns_when_the_ring_closes()
  local returned = false
  reactor.run(function()
    local strategy = listening.RoundRobinStrategy()
    local address = strategy:prepare({ host = "127.0.0.1", port = 0 })
    local ring = listening.WorkerRing()
    reactor.scope(function(scope)
      scope:fork(function()
        strategy:run(ring)
        returned = true
      end)
      local client = net.connect("127.0.0.1", address.port) -- accepted, then waits for a worker (or finds the ring closed)
      ring:close()
      self:assert_equal("", read_all(client)) -- the connection is closed, not left hanging
      client:close()
    end)
    strategy:close()
  end)
  self:assert_true(returned)
end

function T:test_the_hand_over_listener_serves_connections_in_the_order_they_were_pushed()
  virtual(function()
    local listener = listening.HandOverListener()
    local streams = { fake_stream(), fake_stream(), fake_stream() }
    for _, stream in ipairs(streams) do self:assert_true((listener:push(stream))) end
    for index = 1, 3 do
      local accepted = listener:accept()
      self:assert_true(accepted:transport() == streams[index], "connection " .. index .. " is out of order")
    end
  end)
end

function T:test_a_waiting_accept_receives_the_next_pushed_connection()
  virtual(function()
    local listener = listening.HandOverListener()
    local stream = fake_stream()
    reactor.scope(function(scope)
      local waiting = scope:fork(function() return listener:accept() end)
      reactor.sleep(0)
      listener:push(stream)
      self:assert_true(waiting:value():transport() == stream)
    end)
  end)
end

function T:test_closing_the_hand_over_listener_wakes_a_waiting_accept_with_ebadf()
  virtual(function()
    local listener = listening.HandOverListener()
    reactor.scope(function(scope)
      local waiting = scope:fork(function() return { pcall(listener.accept, listener) } end)
      reactor.sleep(0)
      listener:close()
      local ok, err = table.unpack(waiting:value())
      self:assert_false(ok)
      self:assert_true(core.is_instance_of(err, reactor.TransportError), tostring(err))
      self:assert_equal("EBADF", err.context.errno)
      self:assert_equal("accept", err.context.operation)
    end)
    self:assert_true(listener:is_closed())
    listener:close() -- idempotent
  end)
end

function T:test_cancelling_a_waiting_accept_is_a_cancellation_not_a_closed_listener()
  virtual(function()
    local listener = listening.HandOverListener()
    reactor.scope(function(scope)
      local waiting = scope:fork(function() return listener:accept() end)
      reactor.sleep(0)
      waiting:cancel()
      local ok, err = pcall(waiting.value, waiting)
      self:assert_false(ok)
      self:assert_true(core.is_instance_of(err, core.CancellationError), tostring(err))
    end)
    self:assert_false(listener:is_closed())
  end)
end

function T:test_a_hand_over_listener_drains_once_its_queue_is_taken()
  virtual(function()
    local listener = listening.HandOverListener()
    self:assert_true(listener:drain(1)) -- nothing queued: at once
    listener:push(fake_stream())
    listener:push(fake_stream())
    reactor.scope(function(scope)
      scope:fork(function()
        reactor.sleep(0.05)
        listener:accept()
        reactor.sleep(0.05)
        listener:accept()
      end)
      local began = reactor.now()
      self:assert_true(listener:drain(10))
      local waited = reactor.now() - began
      self:assert_true(waited >= 0.1 and waited < 0.2, "drain returned when the queue was empty, not at its timeout: " .. waited)
    end)
  end)
end

function T:test_a_hand_over_listener_that_is_not_taken_drains_to_false_after_its_timeout()
  virtual(function()
    local listener = listening.HandOverListener()
    listener:push(fake_stream())
    local began = reactor.now()
    self:assert_false(listener:drain(0.5))
    self:assert_true(reactor.now() - began >= 0.5)
    began = reactor.now()
    self:assert_false(listener:drain()) -- the default timeout is one second
    self:assert_true(reactor.now() - began >= 1)
    self:assert_false(listener:drain(0)) -- no waiting at all
  end)
end

function T:test_closing_the_hand_over_listener_ends_a_drain_and_closes_what_was_queued()
  virtual(function()
    local listener = listening.HandOverListener()
    local queued = fake_stream()
    listener:push(queued)
    reactor.scope(function(scope)
      scope:fork(function() reactor.sleep(0.1); listener:close() end)
      local began = reactor.now()
      self:assert_true(listener:drain(10)) -- nothing left once closed
      self:assert_true(reactor.now() - began < 1)
    end)
    self:assert_true(queued.closed)
  end)
end

function T:test_round_robin_closes_the_connection_when_every_worker_fails_and_goes_on()
  local first, second, third
  local memory = log.MemorySink()
  reactor.run(function()
    local strategy = listening.RoundRobinStrategy({ logger = log.Logger({ sinks = { memory } }) })
    local address = strategy:prepare({ host = "127.0.0.1", port = 0 })
    local ring = listening.WorkerRing()
    local broken_a, broken_b = fake_worker("a", true), fake_worker("b", true)
    ring:add(broken_a); ring:add(broken_b)
    local running = false
    reactor.scope(function(scope)
      scope:fork(function() running = true; strategy:run(ring) end)
      local function connection()
        local client = net.connect("127.0.0.1", address.port)
        local answer = read_all(client) -- empty: the connection was closed, not left hanging
        client:close()
        return answer
      end
      first, second = connection(), connection()
      local healthy = fake_worker("healthy")
      ring:remove(broken_a); ring:remove(broken_b)
      ring:add(healthy)
      scope:fork(function()
        local stream = healthy.listener:accept()
        stream:write("served")
        stream:close()
      end)
      third = connection()
      self:assert_true(running)
      strategy:close()
    end)
  end)
  self:assert_equal("", first)
  self:assert_equal("", second)
  self:assert_equal("served", third)
  local failures = 0
  for _, record in ipairs(memory:records()) do
    if record.fields and record.fields.code == "hand_over_failed" then failures = failures + 1 end
  end
  self:assert_equal(4, failures) -- two workers tried for each of the two connections
end

function T:test_round_robin_needs_prepare_and_a_hand_over_context()
  local strategy = listening.RoundRobinStrategy()
  self:assert_false((pcall(strategy.worker_listener, strategy, {})))
  local ok = pcall(reactor.run, function() strategy:run(listening.WorkerRing()) end)
  self:assert_false(ok)
end

return T
