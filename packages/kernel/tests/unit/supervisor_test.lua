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
--- default, or `"ignore"`), `spawn_error` (the start fails with it). `world.spawned` lists the processes, `world.times`
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

-- The worker role with a fake peer -------------------------------------------------------------------------------------

--- A peer that returns the scripted `{ message, stream }` entries, then reports the end of its pipe (nil). An entry that
--- is a function is called instead (it may raise). `peer.consumed` counts the entries read.
local function scripted_peer(script)
  local peer = { consumed = 0 }
  function peer.receive()
    peer.consumed = peer.consumed + 1
    local entry = script[peer.consumed]
    if entry == nil then return nil end
    if type(entry) == "function" then return entry() end
    return entry[1], entry[2]
  end
  function peer.send() end
  function peer.close() end
  return peer
end

local function closable()
  local stream = { closed = 0 }
  function stream:close() self.closed = self.closed + 1 end
  return stream
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
