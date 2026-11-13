-- The rolling reload of the supervisor (ADR 0023, Decisions 5 and 6) with real worker processes
-- (tests/fixtures/worker_app.lua): one worker at a time, the replacement ready before the old one stops, a failed
-- replacement leaves the old worker in service, a second reload is refused and a `stop` ends it.
---@diagnostic disable: param-type-mismatch, assign-type-mismatch
local test = require("harness.test")
local uv = require("luv")
local core = require("hecate.core")
local reactor = require("hecate.reactor")
local log = require("hecate.log")
local kernel = require("hecate.kernel")
local T = test.Case("SupervisorReloadTest")

local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]integration[/\\][^/\\]+$") or "."
local workers = dofile(here .. "/helpers/workers.lua")
local can_run_workers, wait_until, get, alive = workers.can_run_workers, workers.wait_until, workers.get, workers.alive
local events, find_event = workers.events, workers.find_event

local flag_path = uv.os_tmpdir() .. "/hecate-reload-flag-" .. uv.os_getpid()

--- A supervisor of `count` workers and the memory sink that holds its log.
local function new_supervisor(count, extra)
  local memory = log.MemorySink()
  local options = {
    command = { uv.exepath(), workers.fixture("worker_app.lua") }, count = count, endpoint = { host = "127.0.0.1", port = 0 },
    strategy = kernel.listening.select("round_robin"), restart_delay = 0.01, crash_limit = 2,
    logger = log.Logger({ sinks = { memory }, severity = "informational" }),
    env = workers.lua_env({ HECATE_TEST_FLAG = flag_path }),
  }
  for key, value in pairs(extra or {}) do options[key] = value end
  return kernel.supervisor.Supervisor(options), memory
end

--- Gives the next worker process that starts a mode (see the fixture); nil removes the flag.
local function set_flag(mode)
  if mode == nil then os.remove(flag_path) return end
  local handle = assert(io.open(flag_path, "w"))
  handle:write(mode)
  handle:close()
end

--- Whether a worker process has taken the mode of the flag file (see the fixture).
local function flag_taken()
  local handle = io.open(flag_path, "r")
  if handle == nil then return true end
  handle:close()
  return false
end

local function pid_of(answer) return answer and answer:match(":(%d+)$") end

--- Runs `body(sup, memory, port)` with a running supervisor of `count` workers, ready. The supervisor is always
--- stopped afterwards, also when the body fails, so that no worker outlives the test; the failure is then raised.
local function with_running(_, count, extra, body)
  reactor.run(function()
    local sup, memory = new_supervisor(count, extra)
    reactor.scope(function(scope)
      local running = scope:fork(sup.run, sup)
      local ok, err = pcall(function()
        wait_until(function() return sup:ready_count() == count end)
        body(sup, memory, sup:local_address().port)
      end)
      pcall(sup.stop, sup, 5)
      local joined, failure = pcall(running.value, running)
      if not ok then error(err, 0) end
      if not joined then error(failure, 0) end
    end)
  end)
end

function T:set_up() set_flag(nil) end
function T:tear_down() set_flag(nil) end

function T:test_each_worker_is_replaced_ready_first_one_at_a_time()
  if not can_run_workers() then return end
  with_running(self, 2, nil, function(sup, memory, port)
    local before = {}
    for _ = 1, 4 do before[pid_of(get(port))] = true end
    sup:reload({ grace_timeout = 5 })
    local after = {}
    for _ = 1, 4 do
      local pid = pid_of(get(port))
      self:assert_not_nil(pid)
      self:assert_nil(before[pid], "a worker of before the reload answered")
      after[pid] = true
    end
    local count = 0
    for _ in pairs(after) do count = count + 1 end
    self:assert_equal(2, count)
    self:assert_equal(2, sup:ready_count())
    self:assert_equal(4, sup:started_count())
    -- Order: replacement ready, then the old stops and exits, and only then the next slot is touched.
    local expected = {
      "reload_replacement_ready", "reload_old_stopping", "reload_old_exited",
      "reload_replacement_ready", "reload_old_stopping", "reload_old_exited",
    }
    local seen = {}
    for _, event in ipairs(events(memory)) do
      if event.code:match("^reload_") then seen[#seen + 1] = event.code end
    end
    self:assert_equal(table.concat(expected, ","), table.concat(seen, ","))
    local slots = {}
    for _, event in ipairs(events(memory)) do
      if event.code == "reload_replacement_ready" then slots[#slots + 1] = event.worker end
    end
    self:assert_equal("1,2", table.concat(slots, ","))
  end)
end

function T:test_a_planned_exit_is_not_a_crash()
  if not can_run_workers() then return end
  -- crash_limit is 2: two counted exits would stop the supervisor. Two reloads replace four workers.
  with_running(self, 2, nil, function(sup, memory, port)
    sup:reload({ grace_timeout = 5 })
    sup:reload({ grace_timeout = 5 })
    self:assert_equal(2, sup:ready_count())
    self:assert_equal(6, sup:started_count())
    for _, event in ipairs(events(memory)) do
      self:assert_true(event.code ~= "worker_exited" and event.code ~= "crash_loop", event.code)
    end
    self:assert_not_nil(get(port))
  end)
end

function T:test_a_replacement_that_exits_aborts_the_reload_and_keeps_the_old_worker()
  if not can_run_workers() then return end
  with_running(self, 2, nil, function(sup, memory, port)
    local before = {}
    for _ = 1, 4 do before[pid_of(get(port))] = true end
    set_flag("exit")
    local err = self:assert_error(function() sup:reload({ grace_timeout = 5 }) end)
    self:assert_true(core.is_instance_of(err, kernel.SupervisorError), tostring(err))
    self:assert_equal("reload_failed", err.context.reason)
    self:assert_equal("exited", err.context.cause)
    self:assert_equal(1, err.context.worker)
    self:assert_equal(2, sup:ready_count())
    for _ = 1, 4 do
      local pid = pid_of(get(port))
      self:assert_true(before[pid] == true, "only the old workers serve")
    end
    set_flag(nil)
    sup:reload({ grace_timeout = 5 }) -- the supervisor is usable afterwards
  end)
end

function T:test_a_replacement_that_is_never_ready_times_out_and_is_killed()
  if not can_run_workers() then return end
  with_running(self, 1, nil, function(sup, memory, port)
    local before = pid_of(get(port))
    set_flag("hang")
    local err = self:assert_error(function() sup:reload({ grace_timeout = 5, ready_timeout = 0.5 }) end)
    self:assert_equal("reload_failed", err.context.reason)
    self:assert_equal("not_ready", err.context.cause)
    self:assert_equal(before, pid_of(get(port)))
    self:assert_equal(1, sup:ready_count())
  end)
end

function T:test_a_second_reload_is_refused_while_one_runs()
  if not can_run_workers() then return end
  with_running(self, 1, nil, function(sup)
    reactor.scope(function(scope)
      local first = scope:fork(sup.reload, sup, { grace_timeout = 5 })
      wait_until(function() return sup:started_count() == 2 end) -- the replacement is started: the reload runs
      local err = self:assert_error(function() sup:reload({ grace_timeout = 5 }) end)
      self:assert_equal("reload_in_progress", err.context.reason)
      first:value()
    end)
  end)
end

function T:test_a_stop_during_a_reload_ends_it_and_refuses_new_ones()
  if not can_run_workers() then return end
  reactor.run(function()
    local sup = new_supervisor(1)
    local failure
    reactor.scope(function(scope)
      local running = scope:fork(sup.run, sup)
      wait_until(function() return sup:ready_count() == 1 end)
      set_flag("hang")
      local reloading = scope:fork(function()
        local ok, err = pcall(sup.reload, sup, { grace_timeout = 5, ready_timeout = 10 })
        failure = not ok and err or nil
      end)
      wait_until(function() return sup:started_count() == 2 end) -- the replacement is started and never ready
      sup:stop(2)
      reloading:value()
      running:value()
    end)
    self:assert_not_nil(failure)
    self:assert_equal("reload_failed", failure.context.reason)
    self:assert_equal("stopping", failure.context.cause)
    local err = self:assert_error(function() sup:reload() end)
    self:assert_equal("not_running", err.context.reason)
  end)
end

--- The codes of the reload and of the kills, in order.
local function reload_trace(memory)
  local seen = {}
  for _, event in ipairs(events(memory)) do
    if event.code:match("^reload_") or event.code == "worker_killed" then seen[#seen + 1] = event.code end
  end
  return table.concat(seen, ",")
end

function T:test_a_deaf_old_worker_is_killed_during_a_reload_and_the_replacement_serves()
  if not can_run_workers() then return end
  set_flag("deaf") -- the first process, the worker in service, never drains
  with_running(self, 1, nil, function(sup, memory, port)
    sup:reload({ grace_timeout = 0.2 })
    self:assert_equal("reload_replacement_ready,reload_old_stopping,worker_killed,reload_old_exited", reload_trace(memory))
    local old = find_event(memory, "reload_old_stopping").pid
    self:assert_equal(old, find_event(memory, "worker_killed").pid)
    self:assert_false(alive(old), "the deaf worker is gone")
    local pid = pid_of(get(port))
    self:assert_not_nil(pid, "the replacement serves")
    self:assert_true(tostring(old) ~= pid)
    self:assert_equal(1, sup:ready_count())
  end)
end

function T:test_the_worker_to_replace_exiting_during_the_reload_fails_it_with_worker_lost()
  if not can_run_workers() then return end
  -- A long restart delay keeps the slot empty while the replacement, slow to become ready, is awaited.
  with_running(self, 1, { restart_delay = 3 }, function(sup, memory, port)
    set_flag("slow_ready=1.5")
    local failure, replacement
    reactor.scope(function(scope)
      local reloading = scope:fork(function()
        local ok, err = pcall(sup.reload, sup, { grace_timeout = 1, ready_timeout = 30 })
        failure = not ok and err or nil
      end)
      wait_until(function() return sup:started_count() == 2 and flag_taken() end)
      replacement = sup._slots[1].next.process.pid -- private: the replacement of the slot, to see it discarded
      self:assert_nil(get(port, "/crash")) -- the old worker exits
      wait_until(function() return sup:ready_count() == 0 end)
      reloading:value()
    end)
    self:assert_true(core.is_instance_of(failure, kernel.SupervisorError), tostring(failure))
    self:assert_equal("reload_failed", failure.context.reason)
    self:assert_equal("worker_lost", failure.context.cause)
    self:assert_equal(1, failure.context.worker)
    self:assert_equal("worker_exited", find_event(memory, "worker_exited").code)
    self:assert_equal("worker_lost", memory:records()[#memory:records()].fields.cause)
    self:assert_nil(sup._slots[1].next)
    wait_until(function() return not alive(replacement) end)
    self:assert_equal(2, sup:started_count()) -- the slot had not restarted yet: no worker was started by the failure
  end)
end

function T:test_cancelling_a_reload_leaves_no_replacement_and_a_later_reload_succeeds()
  if not can_run_workers() then return end
  with_running(self, 1, nil, function(sup, _, port)
    local before = pid_of(get(port))
    set_flag("slow_ready=30") -- the replacement of the first reload is not ready for a long time
    local replacement
    reactor.scope(function(scope)
      local reloading = scope:fork(sup.reload, sup, { grace_timeout = 1, ready_timeout = 60 })
      wait_until(function() return sup:started_count() == 2 and flag_taken() end)
      replacement = sup._slots[1].next.process.pid -- private: the replacement of the slot, to see it discarded
      reloading:cancel()
      local ok, err = pcall(reloading.value, reloading)
      self:assert_false(ok)
      self:assert_true(core.is_instance_of(err, core.CancellationError), tostring(err))
    end)
    self:assert_nil(sup._slots[1].next)
    wait_until(function() return not alive(replacement) end)
    self:assert_equal(1, sup:ready_count())
    self:assert_equal(before, pid_of(get(port)), "the old worker is still the one in service")
    sup:reload({ grace_timeout = 1 }) -- the flag was taken: this replacement is an ordinary worker
    local after = pid_of(get(port))
    self:assert_not_nil(after)
    self:assert_true(after ~= before)
    self:assert_equal(3, sup:started_count())
  end)
end

function T:test_reload_checks_its_arguments_and_needs_a_running_supervisor()
  local sup = new_supervisor(1)
  local err = self:assert_error(function() sup:reload({ grace_timeout = -1 }) end)
  self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
  err = self:assert_error(function() sup:reload({ grace_timeout = 1, ready_timeout = "x" --[[@as any]] }) end)
  self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
  err = self:assert_error(function() sup:reload(5 --[[@as any]]) end) -- the old positional form is refused
  self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
  reactor.run(function()
    local refused = self:assert_error(function() sup:reload() end)
    self:assert_equal("not_running", refused.context.reason)
  end)
end

return T
