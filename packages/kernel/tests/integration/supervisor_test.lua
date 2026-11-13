-- The supervisor of the workers (ADR 0023) with real worker processes (tests/fixtures/worker_app.lua), on every
-- platform: connections spread over the workers, a worker that exits is restarted, a crash loop stops the
-- supervisor, `stop` ends every worker, a worker that ignores `stop` is killed, cancelling `run` leaves no worker.
-- Where workers cannot be started (no spawn or no handle passing) the tests that need them are skipped.
local test = require("harness.test")
local uv = require("luv")
local core = require("hecate.core")
local reactor = require("hecate.reactor")
local log = require("hecate.log")
local kernel = require("hecate.kernel")
local T = test.Case("SupervisorTest")

local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]integration[/\\][^/\\]+$") or "."
local workers = dofile(here .. "/helpers/workers.lua")
local can_run_workers, wait_until, get, alive = workers.can_run_workers, workers.wait_until, workers.get, workers.alive

local flag_path = uv.os_tmpdir() .. "/hecate-supervisor-flag-" .. uv.os_getpid()

local function new_supervisor(options)
  options.command = { uv.exepath(), workers.fixture("worker_app.lua") }
  options.endpoint = options.endpoint or { host = "127.0.0.1", port = 0 }
  options.strategy = options.strategy or kernel.listening.select("round_robin")
  options.env = workers.lua_env(options.env)
  return kernel.supervisor.Supervisor(options)
end

--- Gives the next worker process that starts a mode (see the fixture); nil removes the flag.
local function set_flag(mode)
  if mode == nil then os.remove(flag_path) return end
  local handle = assert(io.open(flag_path, "w"))
  handle:write(mode)
  handle:close()
end

function T:set_up() set_flag(nil) end
function T:tear_down() set_flag(nil) end

function T:test_connections_are_spread_over_the_workers_and_stop_ends_them()
  if not can_run_workers() then return end
  reactor.run(function()
    local sup = new_supervisor({ count = 2 })
    reactor.scope(function(scope)
      local running = scope:fork(sup.run, sup)
      wait_until(function() return sup:ready_count() == 2 end)
      local port = sup:local_address().port
      local seen = {}
      for _ = 1, 6 do
        local content = get(port)
        self:assert_not_nil(content)
        local index = content:match("^(%d+):")
        seen[index] = (seen[index] or 0) + 1
      end
      self:assert_equal(3, seen["1"])
      self:assert_equal(3, seen["2"])
      sup:stop(5)
      running:value()
    end)
    self:assert_equal(2, sup:started_count())
    self:assert_equal(0, sup:ready_count())
  end)
end

function T:test_a_worker_that_exits_is_restarted()
  if not can_run_workers() then return end
  reactor.run(function()
    local sup = new_supervisor({ count = 1, restart_delay = 0.01 })
    reactor.scope(function(scope)
      local running = scope:fork(sup.run, sup)
      wait_until(function() return sup:ready_count() == 1 end)
      local port = sup:local_address().port
      local first = get(port)
      self:assert_nil(get(port, "/crash")) -- the worker exits (code 4, which the supervisor does not interpret)
      wait_until(function() return sup:started_count() == 2 and sup:ready_count() == 1 end)
      local second = get(port)
      self:assert_not_nil(second)
      self:assert_true(first ~= second, "a new process serves after the restart")
      self:assert_equal(2, sup:started_count())
      sup:stop(5)
      running:value()
    end)
  end)
end

function T:test_a_crash_loop_stops_the_supervisor()
  if not can_run_workers() then return end
  reactor.run(function()
    local sup = new_supervisor({ count = 2, restart_delay = 0.01, crash_limit = 3, env = { HECATE_TEST_MODE = "exit" } })
    local err = self:assert_error(function() sup:run() end)
    self:assert_true(core.is_instance_of(err, kernel.SupervisorError), tostring(err))
    self:assert_equal("crash_loop", err.context.reason)
    self:assert_equal(0, sup:ready_count())
  end)
end

function T:test_a_worker_that_exits_after_ready_is_restarted_and_logged()
  if not can_run_workers() then return end
  set_flag("exit_after_ready") -- the first process reports ready, then exits
  local memory = log.MemorySink()
  reactor.run(function()
    local sup = new_supervisor({ count = 1, restart_delay = 0.01, logger = log.Logger({ sinks = { memory } }),
      env = { HECATE_TEST_FLAG = flag_path } })
    reactor.scope(function(scope)
      local running = scope:fork(sup.run, sup)
      wait_until(function() return workers.find_event(memory, "worker_exited") ~= nil and sup:ready_count() == 1 end)
      self:assert_equal(2, sup:started_count())
      self:assert_not_nil(get(sup:local_address().port))
      sup:stop(5)
      running:value()
    end)
  end)
  local exited = workers.find_event(memory, "worker_exited")
  self:assert_equal(1, exited.worker)
  for _, record in ipairs(memory:records()) do
    if record.fields and record.fields.code == "worker_exited" then self:assert_equal(3, record.fields.exit_code) end
  end
end

function T:test_a_worker_that_never_reports_ready_is_killed_and_replaced()
  if not can_run_workers() then return end
  set_flag("hang") -- the first process never reports ready and ignores `stop`
  local memory = log.MemorySink()
  reactor.run(function()
    local sup = new_supervisor({ count = 1, restart_delay = 0.01, ready_timeout = 0.3, logger = log.Logger({ sinks = { memory } }),
      env = { HECATE_TEST_FLAG = flag_path } })
    reactor.scope(function(scope)
      local running = scope:fork(sup.run, sup)
      wait_until(function() return sup:ready_count() == 1 end)
      self:assert_equal(2, sup:started_count())
      self:assert_not_nil(get(sup:local_address().port))
      sup:stop(5)
      running:value()
    end)
  end)
  local event = workers.find_event(memory, "worker_not_ready")
  self:assert_not_nil(event)
  self:assert_equal(1, event.worker)
  self:assert_false(alive(event.pid), "the hung worker is gone")
  self:assert_equal("worker_not_ready,worker_exited", workers.codes(memory, "worker_"))
end

function T:test_the_primary_collects_the_counters_the_workers_send()
  if not can_run_workers() then return end
  reactor.run(function()
    local sup = new_supervisor({ count = 1 })
    reactor.scope(function(scope)
      local running = scope:fork(sup.run, sup)
      wait_until(function() return sup:ready_count() == 1 end)
      local port = sup:local_address().port
      for _ = 1, 3 do self:assert_not_nil(get(port)) end
      wait_until(function()
        local entry = sup:counters()[1]
        return entry ~= nil and entry.connections == 3
      end)
      local entry = sup:counters()[1]
      self:assert_equal(1, entry.worker)
      self:assert_not_nil(entry.pid)
      self:assert_nil(entry.requests) -- http.Server keeps no request counter yet
      sup:stop(5)
      running:value()
    end)
  end)
end

function T:test_a_deaf_worker_is_killed_after_the_grace_period_and_a_margin()
  if not can_run_workers() then return end
  set_flag("deaf") -- the first process ignores `stop`
  local memory = log.MemorySink()
  reactor.run(function()
    local sup = new_supervisor({ count = 1, logger = log.Logger({ sinks = { memory } }), env = { HECATE_TEST_FLAG = flag_path } })
    reactor.scope(function(scope)
      local running = scope:fork(sup.run, sup)
      wait_until(function() return sup:ready_count() == 1 end)
      local began = uv.hrtime()
      sup:stop(0.2)
      running:value()
      -- Grace period plus the margin of one second: it cannot have been killed earlier.
      self:assert_true((uv.hrtime() - began) / 1e9 >= 1.2 - 0.05)
    end)
    local killed = workers.find_event(memory, "worker_killed")
    self:assert_not_nil(killed)
    self:assert_equal(1, killed.worker)
    self:assert_false(alive(killed.pid), "the deaf worker is gone")
    self:assert_equal(0, sup:ready_count())
  end)
end

function T:test_a_worker_that_stops_reading_its_message_pipe_does_not_stall_the_others()
  if not can_run_workers() then return end
  set_flag("mute") -- the first process reports ready, then never reads its message pipe again
  local memory = log.MemorySink()
  local answered, unanswered = 0, 0
  reactor.run(function()
    local sup = new_supervisor({ count = 2, endpoint = { host = "127.0.0.1", port = 0, backlog = 3 },
      logger = log.Logger({ sinks = { memory } }), env = { HECATE_TEST_FLAG = flag_path } })
    reactor.scope(function(scope)
      local running = scope:fork(sup.run, sup)
      wait_until(function() return sup:ready_count() == 2 end)
      local port = sup:local_address().port
      local function request(seconds)
        local ok, content = pcall(reactor.deadline, seconds, get, port)
        return ok and type(content) == "string"
      end
      -- The rotation alternates until the mute worker holds its backlog (3) of connections it never acknowledged;
      -- those clients get no answer.
      for _ = 1, 6 do
        if request(0.5) then answered = answered + 1 else unanswered = unanswered + 1 end
      end
      -- From then on it is skipped: every connection goes to the other worker, and is served.
      for i = 1, 10 do self:assert_true(request(5), "request " .. i .. " is answered") end
      sup:stop(0.2)
      running:value()
    end)
  end)
  self:assert_equal(3, answered)
  self:assert_equal(3, unanswered)
end

--- Counts the records of `code` in `memory`.
local function count_events(memory, code)
  local count = 0
  for _, event in ipairs(workers.events(memory)) do if event.code == code then count = count + 1 end end
  return count
end

function T:test_the_primary_pauses_accepting_while_every_worker_is_saturated_and_resumes_when_one_frees_up()
  if not can_run_workers() then return end
  set_flag("mute") -- the only worker reports ready, then never reads its message pipe: it never acknowledges
  local memory = log.MemorySink()
  local first, second, third, fourth, why
  reactor.run(function()
    local sup = new_supervisor({ count = 1, restart_delay = 0.01, endpoint = { host = "127.0.0.1", port = 0, backlog = 2 },
      logger = log.Logger({ sinks = { memory } }), strategy = kernel.listening.select("round_robin", { logger = log.Logger({ sinks = { memory } }) }),
      env = { HECATE_TEST_FLAG = flag_path } })
    reactor.scope(function(scope)
      local running = scope:fork(sup.run, sup)
      wait_until(function() return sup:ready_count() == 1 end)
      local port = sup:local_address().port
      -- Two connections fill the backlog (2) of the mute worker: handed over, never acknowledged.
      first = scope:fork(get, port)
      second = scope:fork(get, port)
      -- The third finds every worker saturated: the primary keeps it and stops accepting; the fourth waits in the
      -- listen backlog. Neither is closed.
      third = scope:fork(get, port)
      wait_until(function() return workers.find_event(memory, "hand_over_saturated") ~= nil end)
      fourth = scope:fork(get, port)
      reactor.sleep(0.3)
      self:assert_equal("pending", third:state(), "a connection kept during the pause is not closed")
      self:assert_equal("pending", fourth:state())
      -- The mute worker is killed (the test reaches the process the supervisor holds); its replacement serves, and
      -- the primary resumes: the kept connection and the one in the listen backlog are both answered.
      local mute = sup._slots[1].gen.process
      mute:kill("sigkill")
      local content
      content, why = third:value()
      self:assert_not_nil(content, "the connection kept by the primary: " .. tostring(why))
      self:assert_true(content:match("^1:%d+$") ~= nil, content)
      content, why = fourth:value()
      if package.config:sub(1, 1) == "\\" then
        -- Windows answers a connection that finds the listen backlog full with a reset (RST), where Linux and macOS
        -- let it wait: in the listen backlog it is either served or refused, never left hanging.
        self:assert_true(content ~= nil or tostring(why):find("ECONNRESET", 1, true) ~= nil,
          "the connection in the listen backlog: " .. tostring(why))
      else
        self:assert_not_nil(content, "the connection in the listen backlog: " .. tostring(why))
        self:assert_true(content:match("^1:%d+$") ~= nil, content)
      end
      first, second = first:value(), second:value() -- the connections lost with the mute worker are closed
      sup:stop(0.2)
      running:value()
    end)
  end)
  self:assert_nil(first)
  self:assert_nil(second)
  self:assert_equal(1, count_events(memory, "hand_over_saturated"), "logged once, when the pause starts")
end

function T:test_a_stop_ends_a_pause_and_closes_the_connection_kept()
  if not can_run_workers() then return end
  set_flag("mute")
  local memory = log.MemorySink()
  local kept, reason
  reactor.run(function()
    local sup = new_supervisor({ count = 1, endpoint = { host = "127.0.0.1", port = 0, backlog = 1 },
      logger = log.Logger({ sinks = { memory } }), strategy = kernel.listening.select("round_robin", { logger = log.Logger({ sinks = { memory } }) }),
      env = { HECATE_TEST_FLAG = flag_path } })
    reactor.scope(function(scope)
      local running = scope:fork(sup.run, sup)
      wait_until(function() return sup:ready_count() == 1 end)
      local port = sup:local_address().port
      local held = scope:fork(get, port) -- handed over, never acknowledged
      local paused = scope:fork(get, port)
      wait_until(function() return workers.find_event(memory, "hand_over_saturated") ~= nil end)
      local stopping = scope:fork(sup.stop, sup, 0.2)
      -- The pause ends with the stop: the kept connection is closed at once, long before the mute worker is killed.
      reactor.deadline(5, function() kept, reason = paused:value() end)
      stopping:value()
      running:value()
      held:value()
    end)
  end)
  self:assert_nil(kept)
  -- Closed unanswered (an orderly close, or a reset since the request was never read: it depends on the system).
  self:assert_true(reason:find("after 0 bytes$") ~= nil, reason)
end

function T:test_cancelling_run_leaves_no_worker_process_alive()
  if not can_run_workers() then return end
  reactor.run(function()
    local sup = new_supervisor({ count = 2 })
    local pids = {}
    reactor.scope(function(scope)
      local running = scope:fork(sup.run, sup)
      wait_until(function() return sup:ready_count() == 2 end)
      local port = sup:local_address().port
      for _ = 1, 4 do
        local answer = get(port)
        pids[answer and answer:match(":(%d+)$") or "?"] = true
      end
      running:cancel()
      local ok, err = pcall(running.value, running)
      self:assert_false(ok)
      self:assert_true(core.is_instance_of(err, core.CancellationError), tostring(err))
    end)
    local count = 0
    for pid in pairs(pids) do
      count = count + 1
      -- The workers see their message pipe close and drain: they end by themselves, shortly.
      wait_until(function() return not alive(pid) end)
    end
    self:assert_equal(2, count)
  end)
end

function T:test_options_are_checked()
  local function refused(options)
    local err = self:assert_error(function() kernel.supervisor.Supervisor(options) end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
  end
  local endpoint = { host = "127.0.0.1", port = 0 }
  refused({ command = { "lua" }, count = 0, endpoint = endpoint })
  refused({ command = {}, count = 1, endpoint = endpoint })
  refused({ command = { "lua" }, count = 1, endpoint = endpoint, unknown = true })
  refused({ command = { "lua" }, count = 1, endpoint = endpoint, crash_limit = 0 })
  refused({ command = { "lua", 1 }, count = 1, endpoint = endpoint }) -- a non-string element
  refused({ command = { "lua" }, count = 1, endpoint = "127.0.0.1:80" }) -- the endpoint is not a table
  refused({ command = { "lua" }, count = 1, endpoint = endpoint, restart_delay = -1 })
  refused({ command = { "lua" }, count = 1, endpoint = endpoint, restart_delay = 0 / 0 })
  refused({ command = { "lua" }, count = 1, endpoint = endpoint, crash_window = -0.5 })
  refused({ command = { "lua" }, count = 1, endpoint = endpoint, crash_window = math.huge })
  refused({ command = { "lua" }, count = 1.5, endpoint = endpoint })
  refused({ command = { "lua" }, count = "2", endpoint = endpoint })
  refused({ command = { "lua" }, count = 1, endpoint = endpoint, crash_limit = 2.5 })
  refused("options")
end

function T:test_this_process_has_no_worker_role()
  self:assert_nil(kernel.supervisor.worker_role())
end

return T
