-- The rolling reload of the supervisor (ADR 0023, Decisions 5 and 6) with real worker processes
-- (tests/fixtures/worker_app.lua): one worker at a time, the replacement ready before the old one stops, a failed
---@diagnostic disable: need-check-nil, param-type-mismatch, missing-fields, undefined-field, inject-field, assign-type-mismatch
-- is refused or ends it.
---@diagnostic disable: need-check-nil, param-type-mismatch, missing-fields, undefined-field, inject-field
local test = require("harness.test")
local uv = require("luv")
local core = require("hecate.core")
local net = require("hecate.net")
local reactor = require("hecate.reactor")
local log = require("hecate.log")
local kernel = require("hecate.kernel")
local T = test.Case("SupervisorReloadTest")

local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]integration[/\\][^/\\]+$") or "."
local worker_script = uv.fs_realpath(here .. "/fixtures/worker_app.lua") or here .. "/fixtures/worker_app.lua"

local function absolute(search_path)
  local entries = {}
  for entry in search_path:gmatch("[^;]+") do
    local resolved = entry
    if not (entry:match("^[/\\]") or entry:match("^%a:") or entry:match("^!")) then resolved = uv.cwd() .. "/" .. entry end
    entries[#entries + 1] = resolved
  end
  return table.concat(entries, ";")
end

local function can_run_workers()
  for _, query in ipairs({ reactor.supports_spawn, reactor.supports_handle_passing }) do
    local supported, reason = query()
    if not supported then
      io.stderr:write("# SKIP: workers are not supported here: ", tostring(reason), "\n")
      return false
    end
  end
  return true
end

local flag_path = uv.os_tmpdir() .. "/hecate-reload-flag-" .. uv.os_getpid()

--- A supervisor of `count` workers and the memory sink that holds its log.
local function new_supervisor(count, extra)
  local path, cpath = absolute(package.path), absolute(package.cpath)
  local memory = log.MemorySink()
  local options = {
    command = { uv.exepath(), worker_script }, count = count, endpoint = { host = "127.0.0.1", port = 0 },
    strategy = kernel.listening.select("round_robin"), restart_delay = 0.01, crash_limit = 2,
    logger = log.Logger({ sinks = { memory }, severity = "informational" }),
    env = { LUA_PATH = path, LUA_PATH_5_5 = path, LUA_CPATH = cpath, LUA_CPATH_5_5 = cpath, HECATE_TEST_FLAG = flag_path },
  }
  for key, value in pairs(extra or {}) do options[key] = value end
  return kernel.supervisor.Supervisor(options), memory
end

local function wait_until(predicate)
  reactor.deadline(20, function()
    while not predicate() do reactor.sleep(0.02) end
  end)
end

local function set_flag(mode)
  if mode == nil then os.remove(flag_path) return end
  local handle = assert(io.open(flag_path, "w"))
  handle:write(mode)
  handle:close()
end

--- One request with `Connection: close`; returns "<index>:<pid>", or nil when the connection ended without an answer.
local function get(port)
  local ok, stream = pcall(net.connect, "127.0.0.1", port)
  if not ok then return nil end
  stream:write("GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n")
  local parts = {}
  while true do
    local read_ok, data = pcall(stream.read, stream)
    if not read_ok or data == nil then break end
    parts[#parts + 1] = data
  end
  stream:close()
  return table.concat(parts):match("\r\n\r\n(.*)$")
end

local function pid_of(answer) return answer and answer:match(":(%d+)$") end

--- The codes of the log records, in order, each with its worker.
local function events(memory)
  local list = {}
  for _, record in ipairs(memory:records()) do
    local fields = record.fields
    if fields and fields.code then list[#list + 1] = { code = fields.code, worker = fields.worker } end
  end
  return list
end

--- Runs `body(sup, memory, port)` with a running supervisor of `count` workers, ready; stops it at the end.
local function with_running(self, count, extra, body)
  reactor.run(function()
    local sup, memory = new_supervisor(count, extra)
    reactor.scope(function(scope)
      local running = scope:fork(sup.run, sup)
      wait_until(function() return sup:ready_count() == count end)
      body(sup, memory, sup:local_address().port)
      sup:stop(5)
      running:value()
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
    sup:reload(5)
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
    local first = events(memory)
    local workers = {}
    for _, event in ipairs(first) do
      if event.code == "reload_replacement_ready" then workers[#workers + 1] = event.worker end
    end
    self:assert_equal("1,2", table.concat(workers, ","))
  end)
end

function T:test_a_planned_exit_is_not_a_crash()
  if not can_run_workers() then return end
  -- crash_limit is 2: two counted exits would stop the supervisor. Two reloads replace four workers.
  with_running(self, 2, nil, function(sup, memory, port)
    sup:reload(5)
    sup:reload(5)
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
    local err = self:assert_error(function() sup:reload(5) end)
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
    sup:reload(5) -- the supervisor is usable afterwards
  end)
end

function T:test_a_replacement_that_is_never_ready_times_out_and_is_killed()
  if not can_run_workers() then return end
  with_running(self, 1, nil, function(sup, memory, port)
    local before = pid_of(get(port))
    set_flag("hang")
    local err = self:assert_error(function() sup:reload(5, { ready_timeout = 0.5 }) end)
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
      local first = scope:fork(sup.reload, sup, 5)
      reactor.sleep(0)
      local err = self:assert_error(function() sup:reload(5) end)
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
        local ok, err = pcall(sup.reload, sup, 5, { ready_timeout = 10 })
        failure = not ok and err or nil
      end)
      reactor.sleep(0.3) -- the replacement is started and never ready
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

function T:test_reload_checks_its_arguments_and_needs_a_running_supervisor()
  local sup = new_supervisor(1)
  local err = self:assert_error(function() sup:reload(-1) end)
  self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
  err = self:assert_error(function() sup:reload(1, { ready_timeout = ("x"):rep(1) --[[@as any]] }) end)
  self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
  reactor.run(function()
    local refused = self:assert_error(function() sup:reload() end)
    self:assert_equal("not_running", refused.context.reason)
  end)
end

return T
