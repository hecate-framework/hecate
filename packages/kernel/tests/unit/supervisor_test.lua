-- `Supervisor:local_address` without worker processes: a fake strategy whose `prepare` suspends shows what a caller
-- sees while the primary's socket is not bound yet.
---@diagnostic disable: need-check-nil
local test = require("harness.test")
local core = require("hecate.core")
local reactor = require("hecate.reactor")
local log = require("hecate.log")
local kernel = require("hecate.kernel")
local T = test.Case("SupervisorUnitTest")

--- Waits (at most 10 s) until `predicate()` holds.
local function wait_until(predicate)
  reactor.deadline(10, function()
    while not predicate() do reactor.sleep(0.005) end
  end)
end

--- A strategy whose `prepare` tells `entered` that it runs, waits on `gate`, then reports `address`; workers are never
--- started (the command fails).
local function gated_strategy(entered, gate, address)
  return {
    name = "gated",
    prepare = function(_, _) entered:send(true); gate:receive(); return address end,
    run = function() reactor.sleep(60) end,
    close = function() end,
  }
end

--- Runs a supervisor with `endpoint`; `observe(sup, open)` runs beside it once `prepare` is running, `open()` lets
--- `prepare` return.
local function with_gated_supervisor(endpoint, address, observe)
  local entered, gate = reactor.Channel(1), reactor.Channel(1)
  local sup = kernel.supervisor.Supervisor({
    command = { "hecate-no-such-program" }, count = 1, endpoint = endpoint, strategy = gated_strategy(entered, gate, address),
  })
  reactor.run(function()
    reactor.fork(function()
      entered:receive()
      observe(sup, function() gate:send(true) end)
    end)
    pcall(reactor.deadline, 10, sup.run, sup) -- ends with start_failed: no worker program
  end)
end

function T:test_an_ephemeral_port_is_unknown_until_the_socket_is_bound()
  local before, after
  with_gated_supervisor({ host = "127.0.0.1", port = 0 }, { ip = "127.0.0.1", port = 41234, family = "inet" },
    function(sup, open)
      before = sup:local_address() or false
      open()
      wait_until(function() return sup:local_address() ~= nil end)
      after = sup:local_address()
    end)
  self:assert_false(before) -- not `{ port = 0 }`, which a caller cannot connect to
  self:assert_equal(41234, after.port)
end

function T:test_a_fixed_port_is_reported_while_preparing()
  local seen
  with_gated_supervisor({ host = "127.0.0.1", port = 8123 }, nil, function(sup, open)
    seen = sup:local_address()
    open()
  end)
  self:assert_equal(8123, seen.port)
end

--- A strategy that binds nothing and serves nothing.
local function idle_strategy()
  return {
    name = "round_robin",
    prepare = function() return { ip = "127.0.0.1", port = 41235, family = "inet" } end,
    run = function() reactor.sleep(60) end,
    close = function() end,
  }
end

--- Runs `body` with `reactor.spawn` replaced by `spawn`, restored afterwards.
local function with_spawn(spawn, body)
  local real = reactor.spawn
  reactor.spawn = spawn
  local ok, err = pcall(body)
  reactor.spawn = real
  if not ok then error(err, 0) end
end

function T:test_a_stream_received_from_a_worker_is_closed()
  local closed = 0
  local stream = { close = function() closed = closed + 1 end }
  local gate = reactor.Channel(0)
  local sent = false
  local peer = {
    receive = function()
      if not sent then
        sent = true
        return "ready", stream
      end
      gate:receive() -- raises once `stop` closes the gate
      return nil
    end,
    send = function(_, message) if message:find("^stop") then gate:close() end end,
    close = function() end,
  }
  local process = {
    ipc = peer, pid = 1, wait = function() return { code = 0 } end, is_running = function() return false end,
    kill = function() end,
  }
  with_spawn(function() return process end, function()
    local sup = kernel.supervisor.Supervisor({
      command = { "worker" }, count = 1, endpoint = { host = "127.0.0.1", port = 0 }, strategy = idle_strategy(),
    })
    reactor.run(function()
      reactor.scope(function(scope)
        local running = scope:fork(sup.run, sup)
        wait_until(function() return closed > 0 end)
        sup:stop(0.1)
        running:value()
      end)
    end)
  end)
  self:assert_equal(1, closed)
end

--- A worker handed `handed` connections by a strategy, which reports `final` (a `counters` message, or nil) as its last
--- message once told to stop. Returns the log records of the supervisor.
local function run_accounting(handed, final)
  local memory = log.MemorySink()
  local gate = reactor.Channel(0)
  local state = "ready"
  local peer = {
    receive = function()
      if state == "ready" then state = "serving" return "ready" end
      if state == "serving" then pcall(gate.receive, gate); state = "final" end -- `stop` closes the gate
      if state == "final" then state = "ended" if final ~= nil then return final end end
      return nil
    end,
    send = function(_, message, stream) if message:find("^stop") then gate:close() end end,
    close = function() end,
  }
  local process = {
    ipc = peer, pid = 7, wait = function() return { code = 0 } end, is_running = function() return false end,
    kill = function() end,
  }
  local strategy = idle_strategy()
  local delivered = 0
  strategy.run = function(_, ring)
    local worker = ring:next()
    for _ = 1, handed do worker:hand_over({}); delivered = delivered + 1 end
    reactor.sleep(60)
  end
  with_spawn(function() return process end, function()
    local sup = kernel.supervisor.Supervisor({
      command = { "worker" }, count = 1, endpoint = { host = "127.0.0.1", port = 0 }, strategy = strategy,
      logger = log.Logger({ sinks = { memory } }),
    })
    reactor.run(function()
      reactor.scope(function(scope)
        local running = scope:fork(sup.run, sup)
        wait_until(function() return delivered == handed end)
        sup:stop(0.1)
        running:value()
      end)
    end)
  end)
  local found
  for _, record in ipairs(memory:records()) do
    if record.fields and record.fields.code == "hand_over_unaccounted" then found = record end
  end
  return found
end

function T:test_connections_handed_to_a_worker_and_never_accepted_are_logged_at_its_exit()
  local record = run_accounting(3, "counters - 1")
  self:assert_not_nil(record, "hand_over_unaccounted is logged")
  self:assert_equal(3, record.fields.handed)
  self:assert_equal(1, record.fields.accepted)
  self:assert_equal(1, record.fields.worker)
end

function T:test_no_accounting_warning_when_every_connection_was_accepted_or_no_count_was_reported()
  self:assert_nil(run_accounting(2, "counters - 2"))
  self:assert_nil(run_accounting(2, nil)) -- a worker that reports nothing (reuseport, or an older worker) is not judged
end

local function closable()
  local stream = { closed = 0 }
  function stream:close() self.closed = self.closed + 1 end
  return stream
end

--- A worker the strategy hands `count` streams to (the n-th write fails when `failing` is n). `replies` are the messages
--- the worker sends after the hand-over; then `ending` decides how the worker goes away: `"pipe"` (its message pipe ends),
--- or `"killed"` (the supervisor kills it). Returns the
--- streams, the writes `{ message, stream, options }` the peer got and the number of streams closed when the replies
--- were read, before the worker went away (`snapshot`).
local function run_held(count, replies, ending, failing)
  local streams, writes, snapshot = {}, {}, nil
  for index = 1, count do streams[index] = closable() end
  local gate = reactor.Channel(0)
  local delivered, stage, reply = 0, "ready", 0
  local function closed_count()
    local closed = 0
    for _, stream in ipairs(streams) do closed = closed + stream.closed end
    return closed
  end
  local peer = {
    receive = function()
      if stage == "ready" then stage = "replies" return "ready" end
      if stage == "replies" then
        wait_until(function() return delivered == count end)
        reply = reply + 1
        if replies[reply] ~= nil then return replies[reply] end
        snapshot = closed_count()
        stage = "gone"
        if ending == "pipe" then return nil end
      end
      pcall(gate.receive, gate) -- `stop` or a kill closes the gate
      return nil
    end,
    send = function(_, message, stream, options)
      if message:find("^stop") then gate:close() return end
      writes[#writes + 1] = { message, stream, options }
      if failing ~= nil and #writes == failing then error("broken pipe", 0) end
    end,
    close = function() end,
  }
  local running = true
  local process = {
    ipc = peer, pid = 7, wait = function() return { code = 0 } end, is_running = function() return running end,
    kill = function() running = false gate:close() end,
  }
  local strategy = idle_strategy()
  strategy.run = function(_, ring)
    local worker = ring:next()
    for index = 1, count do
      pcall(worker.hand_over, worker, streams[index])
      delivered = delivered + 1
    end
    reactor.sleep(60)
  end
  with_spawn(function() return process end, function()
    local sup = kernel.supervisor.Supervisor({
      command = { "worker" }, count = 1, endpoint = { host = "127.0.0.1", port = 0 }, strategy = strategy,
    })
    reactor.run(function()
      reactor.scope(function(scope)
        local run = scope:fork(sup.run, sup)
        wait_until(function() return delivered == count and snapshot ~= nil end)
        if ending == "killed" then sup:force() else sup:stop(0.1) end
        run:value()
      end)
    end)
  end)
  return streams, writes, snapshot
end

function T:test_the_primary_keeps_each_stream_open_until_the_worker_answers_received()
  local streams, writes, snapshot = run_held(3, { "received", "received" }, "pipe")
  self:assert_equal(3, #writes)
  for index, write in ipairs(writes) do
    self:assert_equal("connection", write[1])
    self:assert_true(write[2] == streams[index])
    self:assert_true(write[3].keep_open, "the write leaves the stream open")
  end
  self:assert_equal(2, snapshot, "one stream is closed per received, the oldest first")
  self:assert_equal(1, streams[1].closed)
  self:assert_equal(1, streams[2].closed)
  self:assert_equal(1, streams[3].closed, "the one never acknowledged is closed when the pipe ends")
end

function T:test_the_oldest_held_stream_is_closed_first()
  local streams, _, snapshot = run_held(3, { "received" }, "pipe")
  self:assert_equal(1, snapshot)
  self:assert_equal(1, streams[1].closed)
  self:assert_equal(1, streams[2].closed) -- all closed at the end, each once
  self:assert_equal(1, streams[3].closed)
end

function T:test_streams_still_held_are_closed_when_the_worker_is_killed()
  local streams, _, snapshot = run_held(2, {}, "killed")
  self:assert_equal(0, snapshot, "nothing was acknowledged")
  for index, stream in ipairs(streams) do self:assert_equal(1, stream.closed, "stream " .. index) end
end

function T:test_a_received_with_nothing_held_is_ignored()
  local streams, _, snapshot = run_held(0, { "received", "received" }, "pipe")
  self:assert_equal(0, #streams)
  self:assert_equal(0, snapshot)
  local one, _, after = run_held(1, { "received", "received", "received" }, "pipe")
  self:assert_equal(1, after)
  self:assert_equal(1, one[1].closed, "a surplus received closes nothing twice")
end

function T:test_a_stream_whose_write_failed_is_not_held_and_does_not_shift_the_acknowledgements()
  local streams, writes, snapshot = run_held(3, { "received", "received" }, "pipe", 2)
  self:assert_equal(3, #writes)
  self:assert_equal(2, snapshot)
  self:assert_equal(1, streams[1].closed)
  self:assert_equal(0, streams[2].closed, "the strategy closes a stream the write failed on, not the supervisor")
  self:assert_equal(1, streams[3].closed, "the second received acknowledges the third stream")
end

function T:test_on_crash_loop_is_validated()
  local function build(value)
    return kernel.supervisor.Supervisor({
      command = { "worker" }, count = 1, endpoint = { host = "127.0.0.1", port = 0 }, on_crash_loop = value,
    })
  end
  for _, bad in ipairs({ "restart", 1, true }) do
    local err = self:assert_error(function() build(bad) end)
    self:assert_equal("hecate.core.ArgumentError", err.code)
    self:assert_not_nil(string.find(tostring(err), "on_crash_loop", 1, true))
  end
  build("stop")
  build("degrade")
end

--- A worker that exits as soon as it starts.
local function crashing_process()
  local peer = { receive = function() return nil end, send = function() end, close = function() end }
  return {
    ipc = peer, pid = 2, wait = function() return { code = 1 } end, is_running = function() return false end,
    kill = function() end,
  }
end

function T:test_degrade_keeps_the_supervisor_running_and_logs_the_crash_loop_once()
  local seen = {}
  local logger = { log = function(_, severity, message, fields) seen[#seen + 1] = { severity, message, fields } end }
  local result, ended = nil, false
  with_spawn(crashing_process, function()
    local sup = kernel.supervisor.Supervisor({
      command = { "worker" }, count = 1, endpoint = { host = "127.0.0.1", port = 0 }, strategy = idle_strategy(),
      restart_delay = 0.001, crash_limit = 2, on_crash_loop = "degrade", logger = logger,
    })
    reactor.run(function()
      reactor.scope(function(scope)
        local running = scope:fork(function()
          local ok, err = pcall(sup.run, sup)
          result, ended = { ok, err }, true
        end)
        wait_until(function()
          for _, entry in ipairs(seen) do if entry[3] and entry[3].code == "crash_loop" then return true end end
          return false
        end)
        self:assert_false(ended, "the crash loop does not end run")
        sup:stop(0.1)
        running:value()
      end)
    end)
  end)
  local loops = 0
  for _, entry in ipairs(seen) do
    if entry[3] and entry[3].code == "crash_loop" then
      loops = loops + 1
      self:assert_equal("error", entry[1])
    end
  end
  self:assert_equal(1, loops)
  self:assert_true(ended)
  self:assert_true(result[1], tostring(result[2]))
end

--- The `HECATE_WORKER_*` environment of a worker, with `extra` replacing entries (false removes one).
local function worker_environment(extra)
  local env = { HECATE_WORKER_INDEX = "1", HECATE_WORKER_STRATEGY = "round_robin", HECATE_WORKER_HOST = "127.0.0.1",
    HECATE_WORKER_PORT = "8080" }
  for key, value in pairs(extra or {}) do env[key] = value or nil end
  return env
end

function T:test_the_worker_role_validates_host_and_backlog()
  local function role(extra) return kernel.supervisor.WorkerRole({}, worker_environment(extra)) end
  for _, host in ipairs({ "127.0.0.1", "::1", "2001:db8::1", "localhost", "my-host.example.org" }) do
    self:assert_equal(host, role({ HECATE_WORKER_HOST = host }).endpoint.host)
  end
  for _, host in ipairs({ "", "bad host", "a;b", "-x", "::1 ", "host/name", ("a"):rep(254) }) do
    local err = self:assert_error(function() role({ HECATE_WORKER_HOST = host }) end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError), host)
  end
  self:assert_nil(role().endpoint.backlog)
  self:assert_equal(511, role({ HECATE_WORKER_BACKLOG = "511" }).endpoint.backlog)
  self:assert_equal(1, role({ HECATE_WORKER_BACKLOG = "0" }).endpoint.backlog)
  self:assert_equal(1, role({ HECATE_WORKER_BACKLOG = "-5" }).endpoint.backlog)
  self:assert_equal(65535, role({ HECATE_WORKER_BACKLOG = "1000000" }).endpoint.backlog)
  for _, backlog in ipairs({ "many", "1.5", "" }) do
    local err = self:assert_error(function() role({ HECATE_WORKER_BACKLOG = backlog }) end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError), backlog)
  end
end

-- The supervisor with fake processes, on a virtual clock ---------------------------------------------------------------

--- Runs `fn` on a reactor with a virtual clock: a restart delay costs no real time and every time is exact.
local function virtual(fn)
  return reactor.Reactor({ clock = "virtual" }):run(fn)
end

--- A strategy that binds nothing, hands nothing over and runs until it is cancelled.
local function quiet_strategy()
  return {
    name = "round_robin",
    prepare = function() return { ip = "127.0.0.1", port = 41236, family = "inet" } end,
    run = function() reactor.Channel(0):receive() end,
    close = function() end,
  }
end

--- Fake worker processes. `plan(n)` describes the n-th process started: `uptime` (seconds from its start, after `ready`,
--- until its message pipe ends; default: it runs until `stop` or a kill), `ready` (default true), `on_stop` (`"exit"`,
--- default, or `"ignore"`), `spawn_error` (the start fails with it), `messages` (sent after `ready`, one per read). `world.spawned` lists the processes, `world.times`
--- the clock reading of each start.
local function new_world(plan)
  local world = { spawned = {}, times = {} }
  function world.spawn(_, _, options)
    local n = #world.spawned + 1
    local spec = plan and plan(n) or {}
    if spec.spawn_error ~= nil then error(spec.spawn_error, 0) end
    local gate = reactor.Channel(0)
    local process = { pid = 1000 + n, running = true, kills = 0, sent = {}, env = options.env }
    local function finish()
      process.running = false
      gate:close()
    end
    local reported = false
    local peer = {}
    function peer.receive()
      if spec.ready ~= false and not reported then
        reported = true
        return "ready"
      end
      if spec.messages ~= nil and spec.messages[1] ~= nil then return table.remove(spec.messages, 1) end
      if spec.uptime ~= nil then
        if spec.uptime > 0 then reactor.sleep(spec.uptime) end
        finish()
        return nil
      end
      gate:receive() -- raises once the process has ended
      return nil
    end
    function peer.send(_, message)
      process.sent[#process.sent + 1] = message
      if message:find("^stop") and spec.on_stop ~= "ignore" then finish() end
    end
    function peer.close() end
    process.ipc = peer
    function process.wait() return { code = spec.code or 1 } end
    function process.is_running() return process.running end
    function process.kill() process.kills = process.kills + 1; finish() end
    world.spawned[n] = process
    world.times[n] = reactor.now()
    return process
  end
  return world
end

--- A logger that keeps the `code` of each record it receives.
local function recording_logger()
  local codes = {}
  return { log = function(_, _, _, fields) if fields and fields.code then codes[#codes + 1] = fields.code end end }, codes
end

local function supervisor_for(extra)
  local options = { command = { "worker" }, count = 1, endpoint = { host = "127.0.0.1", port = 0 }, strategy = quiet_strategy() }
  for key, value in pairs(extra or {}) do options[key] = value end
  return kernel.supervisor.Supervisor(options)
end

--- Waits on the virtual clock until `predicate()` holds, at most 100 s.
local function virtual_wait(predicate)
  reactor.deadline(100, function()
    while not predicate() do reactor.sleep(0.001) end
  end)
end

local function times_of(world)
  local list = {}
  for index, time in ipairs(world.times) do list[index] = ("%g"):format(time) end
  return table.concat(list, ",")
end

function T:test_the_restart_delay_doubles_at_each_crash_and_is_capped_at_ten_seconds()
  local world = new_world(function() return { ready = false, uptime = 0 } end)
  with_spawn(world.spawn, function()
    virtual(function()
      local sup = supervisor_for({ restart_delay = 1, crash_limit = 100, crash_window = 1000 })
      reactor.scope(function(scope)
        local running = scope:fork(sup.run, sup)
        reactor.sleep(36)
        sup:stop(0)
        running:value()
      end)
    end)
  end)
  -- Delays 1, 2, 4, 8, then 16 and 32 capped at 10.
  self:assert_equal("0,1,3,7,15,25,35", times_of(world))
end

function T:test_the_restart_delay_defaults_to_a_tenth_of_a_second()
  local world = new_world(function() return { ready = false, uptime = 0 } end)
  with_spawn(world.spawn, function()
    virtual(function()
      local sup = supervisor_for({ crash_limit = 100 })
      reactor.scope(function(scope)
        local running = scope:fork(sup.run, sup)
        reactor.sleep(0.35)
        sup:stop(0)
        running:value()
      end)
    end)
  end)
  self:assert_equal(3, #world.times)
  for index, expected in ipairs({ 0, 0.1, 0.3 }) do self:assert_true(math.abs(world.times[index] - expected) < 1e-9, index) end
end

function T:test_a_crash_outside_the_window_is_forgotten_and_does_not_count_towards_the_limit()
  -- Worker 3 lives 10 s, longer than the window of 5 s: the two crashes before it are forgotten when it ends.
  local world = new_world(function(n) return { ready = false, uptime = n == 3 and 10 or 0 } end)
  local logger, codes = recording_logger()
  local failure
  with_spawn(world.spawn, function()
    virtual(function()
      local sup = supervisor_for({ restart_delay = 1, crash_limit = 3, crash_window = 5, logger = logger })
      local ok, err = pcall(sup.run, sup)
      failure = not ok and err or nil
    end)
  end)
  -- Crashes at 0 (delay 1), 1 (delay 2), 13 (alone in the window: delay 1), 14 (delay 2) and 16: the third in the window.
  self:assert_equal("0,1,3,14,16", times_of(world))
  self:assert_true(core.is_instance_of(failure, kernel.SupervisorError), tostring(failure))
  self:assert_equal("crash_loop", failure.context.reason)
  local exits = 0
  for _, code in ipairs(codes) do if code == "worker_exited" then exits = exits + 1 end end
  self:assert_equal(5, exits)
  self:assert_equal("crash_loop", codes[#codes])
end

function T:test_the_crash_limit_counts_the_crashes_inside_the_window()
  for limit, started in pairs({ [1] = 1, [2] = 2, [4] = 4 }) do
    local world = new_world(function() return { ready = false, uptime = 0 } end)
    local failure
    with_spawn(world.spawn, function()
      virtual(function()
        local sup = supervisor_for({ restart_delay = 1, crash_limit = limit, crash_window = 1000 })
        local ok, err = pcall(sup.run, sup)
        failure = not ok and err or nil
        self:assert_equal(started, sup:started_count())
      end)
    end)
    self:assert_equal("crash_loop", failure.context.reason, "limit " .. limit)
    self:assert_equal(started, #world.spawned)
  end
end

function T:test_stop_before_run_does_nothing_and_checks_its_argument()
  virtual(function()
    local sup = supervisor_for()
    sup:stop() -- not running: returns at once
    sup:stop(5)
    for _, bad in ipairs({ -1, 0 / 0, math.huge, "5" }) do
      local err = self:assert_error(function() sup:stop(bad) end)
      self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(bad))
    end
    self:assert_equal(0, sup:started_count())
    self:assert_nil(sup:local_address()) -- not started: nothing is known (an ephemeral port)
  end)
end

function T:test_stop_is_idempotent_and_only_the_first_grace_period_counts()
  local world = new_world()
  with_spawn(world.spawn, function()
    virtual(function()
      local sup = supervisor_for()
      reactor.scope(function(scope)
        local running = scope:fork(sup.run, sup)
        virtual_wait(function() return sup:ready_count() == 1 end)
        local first = scope:fork(sup.stop, sup, 3)
        local second = scope:fork(sup.stop, sup, 9) -- waits for the first, asks for nothing more
        first:value()
        second:value()
        running:value()
      end)
      sup:stop(1) -- after the end: nothing
      self:assert_equal(0, sup:ready_count())
    end)
  end)
  self:assert_equal(1, #world.spawned)
  self:assert_equal("stop 3", table.concat(world.spawned[1].sent, ","))
end

function T:test_run_twice_raises_already_run_while_running_and_after_the_end()
  local world = new_world()
  with_spawn(world.spawn, function()
    virtual(function()
      local sup = supervisor_for()
      reactor.scope(function(scope)
        local running = scope:fork(sup.run, sup)
        virtual_wait(function() return sup:ready_count() == 1 end)
        local err = self:assert_error(function() sup:run() end)
        self:assert_true(core.is_instance_of(err, kernel.SupervisorError), tostring(err))
        self:assert_equal("already_run", err.context.reason)
        sup:stop(1)
        running:value()
      end)
      local after = self:assert_error(function() sup:run() end)
      self:assert_equal("already_run", after.context.reason)
      self:assert_equal(1, sup:started_count()) -- nothing was started by the refused calls
    end)
  end)
end

function T:test_force_before_run_is_a_no_op_and_the_supervisor_still_runs()
  local world = new_world()
  with_spawn(world.spawn, function()
    virtual(function()
      local sup = supervisor_for()
      sup:force()
      reactor.scope(function(scope)
        local running = scope:fork(sup.run, sup)
        virtual_wait(function() return sup:ready_count() == 1 end)
        sup:stop(1)
        running:value()
      end)
    end)
  end)
  self:assert_equal(1, #world.spawned)
  self:assert_equal(0, world.spawned[1].kills)
end

function T:test_force_kills_a_worker_that_ignores_stop_and_ends_run()
  local world = new_world(function() return { on_stop = "ignore" } end)
  local logger, codes = recording_logger()
  with_spawn(world.spawn, function()
    virtual(function()
      local sup = supervisor_for({ logger = logger })
      reactor.scope(function(scope)
        local running = scope:fork(sup.run, sup)
        virtual_wait(function() return sup:ready_count() == 1 end)
        sup:force()
        running:value()
      end)
      sup:force() -- after the end: nothing
      self:assert_equal(0, sup:ready_count())
    end)
  end)
  self:assert_equal(1, world.spawned[1].kills)
  self:assert_equal("worker_killed", codes[#codes])
  self:assert_equal(1, #world.spawned) -- no restart after a forced stop
end

function T:test_a_replacement_that_cannot_be_started_fails_the_reload_and_keeps_the_worker()
  local world = new_world(function(n) return n == 2 and { spawn_error = "no such program" } or {} end)
  local logger, codes = recording_logger()
  with_spawn(world.spawn, function()
    virtual(function()
      local sup = supervisor_for({ logger = logger })
      reactor.scope(function(scope)
        local running = scope:fork(sup.run, sup)
        virtual_wait(function() return sup:ready_count() == 1 end)
        local err = self:assert_error(function() sup:reload({ grace_timeout = 1 }) end)
        self:assert_true(core.is_instance_of(err, kernel.SupervisorError), tostring(err))
        self:assert_equal("reload_failed", err.context.reason)
        self:assert_equal("start_failed", err.context.cause)
        self:assert_equal(1, err.context.worker)
        self:assert_equal(1, sup:ready_count()) -- the old worker is still in service
        self:assert_equal(1, sup:started_count())
        self:assert_true(world.spawned[1].running)
        sup:stop(1)
        running:value()
      end)
    end)
  end)
  local failed = false
  for _, code in ipairs(codes) do failed = failed or code == "reload_slot_failed" end
  self:assert_true(failed)
end

function T:test_on_accepted_is_called_for_an_accepted_reload_only()
  local world = new_world(function(n) return n == 2 and { ready = false } or {} end) -- the replacement keeps the reload busy
  with_spawn(world.spawn, function()
    virtual(function()
      local sup = supervisor_for({})
      local accepted = 0
      local function count() accepted = accepted + 1 end
      self:assert_error(function() sup:reload({ on_accepted = count }) end) -- not running: refused
      self:assert_equal(0, accepted)
      self:assert_error(function() sup:reload({ on_accepted = {} --[[@as any]] }) end)
      reactor.scope(function(scope)
        local running = scope:fork(sup.run, sup)
        virtual_wait(function() return sup:ready_count() == 1 end)
        local reloading = scope:fork(function() pcall(sup.reload, sup, { grace_timeout = 1, ready_timeout = 5, on_accepted = count }) end)
        virtual_wait(function() return accepted == 1 end)
        local err = self:assert_error(function() sup:reload({ on_accepted = count }) end) -- another reload runs
        self:assert_equal("reload_in_progress", err.context.reason)
        reloading:value()
        self:assert_equal(1, accepted)
        sup:stop(1)
        running:value()
      end)
    end)
  end)
end

-- The ready timeout outside a reload ------------------------------------------------------------------------------------

function T:test_ready_timeout_is_validated()
  for _, bad in ipairs({ -1, 0 / 0, math.huge, "5", true }) do
    local err = self:assert_error(function() supervisor_for({ ready_timeout = bad }) end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(bad))
    self:assert_not_nil(string.find(tostring(err), "ready_timeout", 1, true))
  end
  supervisor_for({ ready_timeout = 0 })
  supervisor_for({ ready_timeout = 2.5 })
end

function T:test_a_worker_that_is_not_ready_in_time_is_killed_logged_and_restarted_with_backoff()
  -- The first process never says `ready`; the second does.
  local world = new_world(function(n) return { ready = n ~= 1 } end)
  local logger, codes = recording_logger()
  with_spawn(world.spawn, function()
    virtual(function()
      local sup = supervisor_for({ ready_timeout = 5, restart_delay = 1, logger = logger })
      reactor.scope(function(scope)
        local running = scope:fork(sup.run, sup)
        virtual_wait(function() return sup:ready_count() == 1 end)
        sup:stop(1)
        running:value()
      end)
    end)
  end)
  self:assert_equal(1, world.spawned[1].kills)
  self:assert_equal(0, world.spawned[2].kills)
  self:assert_equal("0,6", times_of(world)) -- killed at 5 s, restart delay 1 s
  self:assert_equal("worker_not_ready,worker_exited", table.concat(codes, ",", 1, 2))
end

function T:test_the_not_ready_log_is_an_error_with_the_worker_and_the_timeout()
  local world = new_world(function() return { ready = false } end)
  local seen
  local logger = { log = function(_, severity, _, fields)
    if fields and fields.code == "worker_not_ready" then seen = seen or { severity, fields } end
  end }
  with_spawn(world.spawn, function()
    virtual(function()
      local sup = supervisor_for({ ready_timeout = 2, logger = logger })
      reactor.scope(function(scope)
        local running = scope:fork(sup.run, sup)
        virtual_wait(function() return seen ~= nil end)
        sup:stop(0)
        running:value()
      end)
    end)
  end)
  self:assert_equal("error", seen[1])
  self:assert_equal(1, seen[2].worker)
  self:assert_equal(1001, seen[2].pid)
  self:assert_equal(2, seen[2].ready_timeout)
end

function T:test_workers_that_are_never_ready_count_as_crashes_and_end_in_a_crash_loop()
  local world = new_world(function() return { ready = false } end)
  local failure
  with_spawn(world.spawn, function()
    virtual(function()
      local sup = supervisor_for({ ready_timeout = 3, restart_delay = 1, crash_limit = 3, crash_window = 1000 })
      local ok, err = pcall(sup.run, sup)
      failure = not ok and err or nil
    end)
  end)
  self:assert_equal("crash_loop", failure.context.reason)
  self:assert_equal("0,4,9", times_of(world)) -- 3 s, then delays of 1 and 2 s
end

function T:test_a_ready_worker_is_never_killed_by_the_ready_timeout()
  local world = new_world()
  with_spawn(world.spawn, function()
    virtual(function()
      local sup = supervisor_for({ ready_timeout = 1 })
      reactor.scope(function(scope)
        local running = scope:fork(sup.run, sup)
        virtual_wait(function() return sup:ready_count() == 1 end)
        reactor.sleep(5)
        self:assert_equal(1, sup:ready_count())
        sup:stop(1)
        running:value()
      end)
    end)
  end)
  self:assert_equal(0, world.spawned[1].kills)
  self:assert_equal(1, #world.spawned)
end

function T:test_a_stop_before_the_ready_timeout_is_not_a_not_ready_failure()
  local world = new_world(function() return { ready = false } end)
  local logger, codes = recording_logger()
  with_spawn(world.spawn, function()
    virtual(function()
      local sup = supervisor_for({ ready_timeout = 5, logger = logger })
      reactor.scope(function(scope)
        local running = scope:fork(sup.run, sup)
        virtual_wait(function() return sup:started_count() == 1 end)
        sup:stop(1)
        running:value()
        reactor.sleep(10)
      end)
    end)
  end)
  for _, code in ipairs(codes) do self:assert_true(code ~= "worker_not_ready", code) end
end

-- The counters ---------------------------------------------------------------------------------------------------------

function T:test_counters_lists_the_latest_values_of_each_worker()
  local world = new_world(function(n)
    if n == 1 then return { messages = { "counters 5 3", "counters 7 4" } } end
    return { messages = { "counters - 9" } }
  end)
  local listed, before
  with_spawn(world.spawn, function()
    virtual(function()
      local sup = supervisor_for({ count = 2 })
      before = sup:counters()
      reactor.scope(function(scope)
        local running = scope:fork(sup.run, sup)
        virtual_wait(function()
          local list = sup:counters()
          return #list == 2 and list[1].requests == 7
        end)
        listed = sup:counters()
        sup:stop(1)
        running:value()
      end)
    end)
  end)
  self:assert_equal(0, #before)
  self:assert_equal(2, #listed)
  self:assert_equal(1, listed[1].worker)
  self:assert_equal(1001, listed[1].pid)
  self:assert_equal(7, listed[1].requests)
  self:assert_equal(4, listed[1].connections)
  self:assert_equal(2, listed[2].worker)
  self:assert_nil(listed[2].requests) -- unknown
  self:assert_equal(9, listed[2].connections)
end

function T:test_a_malformed_counters_message_is_ignored_and_keeps_the_last_good_values()
  local bad = { "counters", "counters 1", "counters a b", "counters 1 2 3", "counters -1 2", "counters 1.5 2", "counters 1 -",
    "counters  1 2", "counters 99999999999999999999 1", "counters 1 2 " }
  local messages = { "counters 2 3" }
  for _, text in ipairs(bad) do messages[#messages + 1] = text end
  messages[#messages + 1] = "ready" -- a second `ready` is harmless
  messages[#messages + 1] = "counters 4 5"
  local world = new_world(function() return { messages = messages } end)
  local seen = {}
  with_spawn(world.spawn, function()
    virtual(function()
      local sup = supervisor_for()
      reactor.scope(function(scope)
        local running = scope:fork(sup.run, sup)
        virtual_wait(function() local c = sup:counters()[1]; return c ~= nil and c.requests == 4 end)
        seen = sup:counters()
        sup:stop(1)
        running:value()
      end)
    end)
  end)
  self:assert_equal(1, #seen)
  self:assert_equal(5, seen[1].connections)
end

function T:test_counters_do_not_keep_stop_from_being_handled()
  local flood = {}
  for i = 1, 500 do flood[i] = "counters " .. i .. " " .. i end
  local world = new_world(function() return { messages = flood } end)
  with_spawn(world.spawn, function()
    virtual(function()
      local sup = supervisor_for()
      reactor.scope(function(scope)
        local running = scope:fork(sup.run, sup)
        virtual_wait(function() return sup:counters()[1] ~= nil end)
        sup:stop(1)
        running:value()
      end)
    end)
  end)
  self:assert_equal("stop 1", world.spawned[1].sent[1])
end

function T:test_a_restarted_worker_starts_with_no_counters()
  local world = new_world(function(n)
    if n == 1 then return { messages = { "counters 1 1" }, uptime = 1 } end
    return {}
  end)
  with_spawn(world.spawn, function()
    virtual(function()
      local sup = supervisor_for({ restart_delay = 0.5 })
      reactor.scope(function(scope)
        local running = scope:fork(sup.run, sup)
        virtual_wait(function() return #world.spawned == 2 and sup:ready_count() == 1 end)
        self:assert_equal(0, #sup:counters())
        sup:stop(1)
        running:value()
      end)
    end)
  end)
end

-- The counters of the worker role ------------------------------------------------------------------------------------

function T:test_a_worker_reports_its_counters_at_most_once_per_second_and_only_when_they_changed()
  local sent = {}
  local peer = { close = function() end }
  function peer.send(_, message) sent[#sent + 1] = { reactor.now(), message } end
  local role = kernel.supervisor.WorkerRole(peer, worker_environment())
  local accepted = 0
  role._hand_over.accepted = function() return accepted end
  local texts
  virtual(function()
    reactor.scope(function(scope)
      local reporter = scope:fork(role.report_counters, role, 1)
      reactor.sleep(0.5)
      accepted = 2 -- changes within a period: one report at the next tick
      accepted = 3
      reactor.sleep(1) -- 1.5
      reactor.sleep(2) -- 3.5: nothing changed since the tick at 3
      accepted = 4
      reactor.sleep(1) -- 4.5
      reporter:cancel()
    end)
  end)
  texts = {}
  for i, entry in ipairs(sent) do texts[i] = ("%g %s"):format(entry[1], entry[2]) end
  self:assert_equal("1 counters - 3,4 counters - 4", table.concat(texts, ","))
end

function T:test_the_reporter_survives_a_failing_pipe()
  local peer = { close = function() end }
  function peer.send() error("closed") end
  local role = kernel.supervisor.WorkerRole(peer, worker_environment())
  local accepted = 1
  role._hand_over.accepted = function() return accepted end
  virtual(function()
    reactor.scope(function(scope)
      local reporter = scope:fork(role.report_counters, role, 1)
      reactor.sleep(2.5)
      reporter:cancel()
    end)
  end)
end

-- The worker role with a fake peer -------------------------------------------------------------------------------------

--- A peer that returns the scripted `{ message, stream }` entries, then reports the end of its pipe (nil). An entry that
--- is a function is called instead (it may raise). `peer.consumed` counts the entries read.
local function scripted_peer(script)
  local peer = { consumed = 0, sent = {} }
  function peer.receive()
    peer.consumed = peer.consumed + 1
    local entry = script[peer.consumed]
    if entry == nil then return nil end
    if type(entry) == "function" then return entry() end
    return entry[1], entry[2]
  end
  function peer.send(_, message) peer.sent[#peer.sent + 1] = message end
  function peer.close() end
  return peer
end

--- Runs `control` of a role fed by `script` and returns the grace period `on_stop` got (nil: it was not called) and the peer.
local function run_control(script, default_grace, extra_environment)
  local peer = scripted_peer(script)
  local role = kernel.supervisor.WorkerRole(peer, worker_environment(extra_environment))
  local grace
  virtual(function()
    role:control(function(seconds) grace = seconds end, default_grace)
  end)
  return grace, peer, role
end

function T:test_control_stops_with_the_grace_period_of_the_stop_message()
  self:assert_equal(3, (run_control({ { "stop 3" } }, 30)))
  self:assert_equal(0, (run_control({ { "stop 0" } }, 30)))
  self:assert_equal(2.5, (run_control({ { "stop 2.5" } }, 30)))
end

function T:test_control_keeps_the_default_grace_for_a_malformed_stop_and_still_ends()
  for _, text in ipairs({ "stop abc", "stop -1", "stop 1e999", "stop nan", "stop 5 6", "stop  " }) do
    local grace, peer = run_control({ { text }, { "connection", closable() } }, 7)
    self:assert_equal(7, grace, text)
    self:assert_equal(1, peer.consumed, text .. ": the loop ended at the stop message")
  end
end

function T:test_control_ignores_unknown_messages_and_closes_the_stream_they_carry()
  local carried = closable()
  local grace, peer = run_control({ { "reload" }, { "future_message", carried }, { "stop" }, { "stop 4" } }, 30)
  self:assert_equal(4, grace)
  self:assert_equal(4, peer.consumed)
  self:assert_equal(1, carried.closed)
end

function T:test_control_treats_a_connection_without_a_stream_as_unknown()
  local grace, peer = run_control({ { "connection" }, { "stop 1" } }, 30)
  self:assert_equal(1, grace)
  self:assert_equal(2, peer.consumed)
end

function T:test_control_closes_the_hand_over_listener_and_the_connections_still_queued_when_it_ends()
  local queued = closable()
  local grace, _, role = run_control({ { "connection", queued }, { "stop 2" } }, 30)
  self:assert_equal(2, grace)
  self:assert_true(role:listener():is_closed())
  self:assert_equal(1, queued.closed)
end

function T:test_control_keeps_the_queued_connections_open_while_on_stop_runs()
  -- The connections handed over before the `stop` message must reach the server (a rolling reload resets none): the
  -- queue is closed after `on_stop`, not before.
  local queued = closable()
  local open_during_stop, listener_open_during_stop
  local peer = scripted_peer({ { "connection", queued }, { "stop 2" } })
  local role = kernel.supervisor.WorkerRole(peer, worker_environment())
  virtual(function()
    role:control(function()
      open_during_stop = queued.closed == 0
      listener_open_during_stop = not role:listener():is_closed()
    end, 30)
  end)
  self:assert_true(open_during_stop, "a queued connection is still open when on_stop runs")
  self:assert_true(listener_open_during_stop, "the hand-over listener is still open when on_stop runs")
  self:assert_equal(1, queued.closed, "what is still queued afterwards is closed")
  self:assert_true(role:listener():is_closed())
end

function T:test_control_calls_on_stop_with_the_default_grace_when_the_pipe_closes()
  local grace, peer = run_control({}, 12)
  self:assert_equal(12, grace)
  self:assert_equal(1, peer.consumed)
end

function T:test_control_ends_on_a_failure_of_the_pipe_but_lets_a_cancellation_through()
  local grace = run_control({ function() error("broken pipe") end }, 9)
  self:assert_equal(9, grace)
  local called = false
  local peer = scripted_peer({ function() error(core.CancellationError("scope cancelled")) end })
  local role = kernel.supervisor.WorkerRole(peer, worker_environment())
  local err
  virtual(function()
    local ok, failure = pcall(role.control, role, function() called = true end, 9)
    err = not ok and failure or nil
  end)
  self:assert_true(core.is_instance_of(err, core.CancellationError), tostring(err))
  self:assert_false(called, "a cancelled worker does not report a stop")
end

function T:test_control_closes_a_connection_the_full_queue_cannot_take_and_logs_it()
  local memory = log.MemorySink()
  local saved = log.default()
  log.set_default(log.Logger({ sinks = { memory } }))
  local first, second = closable(), closable()
  local grace = run_control({ { "connection", first }, { "connection", second }, { "stop 1" } }, 30, { HECATE_WORKER_BACKLOG = "1" })
  log.set_default(saved)
  self:assert_equal(1, grace)
  self:assert_equal(1, second.closed)
  self:assert_equal(1, first.closed) -- the queued one is closed when the listener is
  local record = memory:records()[1]
  self:assert_equal("hand_over_queue_full", record.fields.code)
  self:assert_equal(1, record.fields.capacity)
  local discarded = memory:records()[2]
  self:assert_equal("hand_over_discarded", discarded.fields.code, "a queued connection closed unserved is logged")
  self:assert_equal(1, discarded.fields.count)
end

function T:test_control_answers_each_connection_with_received_whether_it_was_queued_or_refused()
  local first, second, third = closable(), closable(), closable()
  local _, peer = run_control({ { "connection", first }, { "connection", second }, { "connection", third }, { "stop 1" } }, 30,
    { HECATE_WORKER_BACKLOG = "1" }) -- a queue of one: the second and the third are refused as full
  self:assert_equal(3, #peer.sent)
  for _, message in ipairs(peer.sent) do self:assert_equal("received", message) end
end

function T:test_control_does_not_answer_what_is_not_a_connection_with_a_stream()
  local _, peer = run_control({ { "connection" }, { "future_message", closable() }, { "stop 1" } }, 30)
  self:assert_equal(0, #peer.sent)
end

function T:test_control_reads_stop_without_waiting_for_the_answers_to_be_written()
  -- A write that takes 5 s (a full pipe) must not delay the `stop` that follows the connections.
  local peer = scripted_peer({ { "connection", closable() }, { "connection", closable() }, { "stop 3" } })
  local written = {}
  function peer.send(_, message)
    reactor.sleep(5)
    written[#written + 1] = message
  end
  local role = kernel.supervisor.WorkerRole(peer, worker_environment())
  local stopped_at, grace
  virtual(function()
    local started = reactor.now()
    role:control(function(seconds)
      stopped_at, grace = reactor.now() - started, seconds
    end, 30)
  end)
  self:assert_equal(0, stopped_at, "on_stop ran at once")
  self:assert_equal(3, grace)
  self:assert_equal(2, #written, "the answers are flushed afterwards")
end

function T:test_control_logs_a_failure_of_the_pipe()
  local memory = log.MemorySink()
  local saved = log.default()
  log.set_default(log.Logger({ sinks = { memory } }))
  run_control({ function() error("broken pipe") end }, 9)
  log.set_default(saved)
  local record = memory:records()[1]
  self:assert_not_nil(record, "the failure is logged")
  self:assert_equal("control_failed", record.fields.code)
  self:assert_true(tostring(record.fields.reason):find("broken pipe", 1, true) ~= nil, tostring(record.fields.reason))
end

function T:test_the_worker_role_refuses_an_unknown_strategy_and_a_malformed_port()
  local function refused(extra)
    local err = self:assert_error(function() kernel.supervisor.WorkerRole({}, worker_environment(extra)) end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
    return err
  end
  for _, strategy in ipairs({ "shared", "", "Round_Robin" }) do refused({ HECATE_WORKER_STRATEGY = strategy }) end
  self:assert_true(tostring(refused({ HECATE_WORKER_STRATEGY = false })):find("unknown strategy", 1, true) ~= nil)
  for _, port in ipairs({ "abc", "", "80.5", "-1", "65536", "70000" }) do refused({ HECATE_WORKER_PORT = port }) end
  self:assert_true(tostring(refused({ HECATE_WORKER_PORT = false })):find("malformed port", 1, true) ~= nil)
  for _, port in ipairs({ "0", "1", "65535" }) do
    self:assert_equal(tonumber(port), kernel.supervisor.WorkerRole({}, worker_environment({ HECATE_WORKER_PORT = port })).endpoint.port)
  end
  self:assert_equal("reuseport", kernel.supervisor.WorkerRole({}, worker_environment({ HECATE_WORKER_STRATEGY = "reuseport" })).strategy)
end

function T:test_the_worker_role_index_defaults_to_zero()
  local function index(value) return kernel.supervisor.WorkerRole({}, worker_environment({ HECATE_WORKER_INDEX = value })).index end
  self:assert_equal(0, index(false)) -- missing
  self:assert_equal(0, index("abc"))
  self:assert_equal(0, index("1.5"))
  self:assert_equal(3, index("3"))
end

function T:test_the_worker_role_detects_an_ipv6_host_for_its_listener()
  local function address(host)
    local environment = worker_environment({ HECATE_WORKER_HOST = host })
    return kernel.supervisor.WorkerRole({}, environment):listener():local_address()
  end
  local v6 = address("::1")
  self:assert_equal("inet6", v6.family)
  self:assert_equal("::1", v6.ip)
  self:assert_equal("inet6", address("2001:db8::1").family)
  self:assert_equal("inet", address("127.0.0.1").family)
  self:assert_equal("inet", address("localhost").family)
  local default = address(false) -- no host: loopback
  self:assert_equal("127.0.0.1", default.ip)
  self:assert_equal(8080, default.port)
end

return T
