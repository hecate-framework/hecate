---@diagnostic disable: need-check-nil, param-type-mismatch, missing-fields, undefined-field, inject-field
local test = require("harness.test")
local core = require("hecate.core")
local net = require("hecate.net")
local reactor = require("hecate.reactor")
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
  reactor.run(function()
    local ring = listening.WorkerRing()
    reactor.fork(function()
      reactor.sleep(0.01)
      ring:add({ id = "late" })
    end)
    got = ring:next().id
    ring:remove(ring:next())
    reactor.fork(function()
      reactor.sleep(0.01)
      ring:close()
    end)
    after_close = ring:next()
  end)
  self:assert_equal("late", got)
  self:assert_nil(after_close)
end

function T:test_the_handoff_listener_queues_wraps_and_closes()
  local accepted, queued_after_close, failure, closed_stream
  reactor.run(function()
    local server = net.listen("127.0.0.1", 0)
    local port = server:local_address().port
    local handoff = listening.HandoffListener({ ip = "127.0.0.1", port = port, family = "inet" })
    self:assert_equal(port, handoff:local_address().port)
    reactor.fork(function() local s = net.connect("127.0.0.1", port); s:write("hi"); s:close() end)
    local stream = server:accept()
    handoff:push(stream._inner) -- a reactor stream, as received through `reactor.ipc`
    accepted = handoff:accept()
    self:assert_true(core.is_instance_of(accepted, net.TcpStream))
    self:assert_equal("hi", accepted:reader():read_exact(2))
    accepted:close()
    reactor.fork(function() local s = net.connect("127.0.0.1", port); s:close() end)
    local second = server:accept()
    handoff:close()
    queued_after_close = handoff:push(second._inner)
    closed_stream = second:is_closed()
    local ok, err = pcall(handoff.accept, handoff)
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

function T:test_the_handoff_listener_is_bounded_and_closes_what_it_cannot_queue()
  reactor.run(function()
    local handoff = listening.HandoffListener(nil, 2)
    self:assert_equal(2, handoff:capacity())
    local a, b, c = fake_stream(), fake_stream(), fake_stream()
    self:assert_true((handoff:push(a)))
    self:assert_true((handoff:push(b)))
    local queued, reason = handoff:push(c)
    self:assert_false(queued)
    self:assert_equal("full", reason)
    self:assert_true(c.closed)
    self:assert_false(a.closed)
    handoff:close()
    local after, why = handoff:push(fake_stream())
    self:assert_false(after)
    self:assert_equal("closed", why)
    self:assert_true(a.closed and b.closed)
  end)
end

function T:test_the_handoff_listener_capacity_defaults_to_the_server_backlog_and_is_checked()
  local http = require("hecate.http")
  self:assert_equal(http.Server.DEFAULTS.backlog, listening.HandoffListener():capacity())
  for _, bad in ipairs({ 0, -1, 1.5, "8" }) do
    local ok, err = pcall(listening.HandoffListener, nil, bad)
    self:assert_false(ok)
    self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
  end
end

--- A worker of the test: takes a connection into its own handoff listener, as a real worker's control loop does.
local function fake_worker(name, fail)
  local worker = { name = name, handoff = listening.HandoffListener(), taken = 0 }
  function worker:hand_over(stream)
    if fail then error("worker " .. name .. " is gone") end
    self.taken = self.taken + 1
    self.handoff:push(stream)
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
          local listener = strategy:worker_listener({ endpoint = { host = "127.0.0.1", port = 0 }, handoff = worker.handoff })
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
        local stream = healthy.handoff:accept()
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
      local client = net.connect("127.0.0.1", address.port) -- accepted, then waits for a worker
      reactor.sleep(0.02)
      ring:close()
      self:assert_equal("", read_all(client)) -- the connection is closed, not left hanging
      client:close()
    end)
    strategy:close()
  end)
  self:assert_true(returned)
end

function T:test_round_robin_needs_prepare_and_a_handoff_context()
  local strategy = listening.RoundRobinStrategy()
  self:assert_false((pcall(strategy.worker_listener, strategy, {})))
  local ok = pcall(reactor.run, function() strategy:run(listening.WorkerRing()) end)
  self:assert_false(ok)
end

return T
