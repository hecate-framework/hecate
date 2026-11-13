-- `Application` with `workers = 2` (ADR 0023): the primary runs a supervisor, the workers (tests/fixtures/
-- application_worker.lua, the same application started again) boot it and serve through the worker role, clients are
-- answered, a signal stops the primary and its workers cleanly. Runs where `reactor.spawn` with a message pipe works (the
-- three platforms of the CI; a platform that reports no spawn or handle passing skips the tests, any other failure to
-- start a worker fails the test).
---@diagnostic disable: need-check-nil, undefined-field
local test = require("harness.test")
local uv = require("luv")
local core = require("hecate.core")
local net = require("hecate.net")
local reactor = require("hecate.reactor")
local log = require("hecate.log")
local kernel = require("hecate.kernel")
local T = test.Case("ApplicationWorkersTest")

local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]integration[/\\][^/\\]+$") or "."
local workers = dofile(here .. "/helpers/workers.lua")
local worker_script = workers.fixture("application_worker.lua")
local can_run_workers, wait_until, get = workers.can_run_workers, workers.wait_until, workers.get

--- Gives the workers (they inherit this process's environment) the search paths of this process while `body` runs.
local function with_lua_paths(body)
  local names = { "LUA_PATH", "LUA_PATH_5_5", "LUA_CPATH", "LUA_CPATH_5_5" }
  local saved = {}
  for _, name in ipairs(names) do saved[name] = uv.os_getenv(name) end
  local path, cpath = workers.absolute(package.path), workers.absolute(package.cpath)
  uv.os_setenv("LUA_PATH", path); uv.os_setenv("LUA_PATH_5_5", path)
  uv.os_setenv("LUA_CPATH", cpath); uv.os_setenv("LUA_CPATH_5_5", cpath)
  local ok, err = pcall(body)
  for _, name in ipairs(names) do
    if saved[name] then uv.os_setenv(name, saved[name]) else uv.os_unsetenv(name) end
  end
  if not ok then error(err, 0) end
end

local function new_application(options)
  local routes = kernel.routes("primary")
  options = options or {}
  options.routes = { routes }
  options.workers, options.strategy, options.grace_timeout = 2, "round_robin", 5
  options.logger = options.logger or log.Logger({ sinks = {} })
  options.server = { host = "127.0.0.1", port = 0 }
  options.worker_command = { uv.exepath(), worker_script }
  return kernel.Application(options)
end

local function wait_ready(app)
  wait_until(function() return app._supervisor ~= nil and app._supervisor:ready_count() == 2 end)
end

function T:test_clients_are_answered_by_both_workers_and_a_signal_stops_everything()
  if not can_run_workers() then return end
  if not workers.can_raise_signals() then return end -- the signal is raised with kill; Windows delivers console signals only
  local guard = uv.new_signal() -- a signal raised before the watcher listens must not end the test process
  guard:start("sigterm", function() end)
  local memory = log.MemorySink()
  local app = new_application({ logger = log.Logger({ sinks = { memory } }) })
  local pids, ok, err = {}, nil, nil
  with_lua_paths(function()
    reactor.run(function()
      reactor.fork(function()
        wait_ready(app)
        local port = app:local_address().port
        for _ = 1, 6 do
          local body = get(port, "/whoami")
          local pid = body and body:match('"pid"%s*:%s*(%d+)')
          if pid then pids[pid] = true end
        end
        uv.kill(uv.os_getpid(), "sigterm")
      end)
      ok, err = pcall(reactor.deadline, 30, app.serve, app)
    end)
  end)
  guard:close()
  self:assert_true(ok, tostring(err))
  local count = 0
  for _ in pairs(pids) do count = count + 1 end
  self:assert_equal(2, count) -- round robin: both workers answered
  local started, signalled = false, false
  for _, record in ipairs(memory:records()) do
    local code = record.fields and record.fields.code
    if code == "workers_starting" then started = true end
    if code == "shutdown_signal" then signalled = true end
  end
  self:assert_true(started)
  self:assert_true(signalled)
  self:assert_nil(app._supervisor)
  self:assert_nil(app:local_address())
end

function T:test_a_worker_survives_sigint_and_sigterm_sent_to_its_own_pid()
  -- OQ-116: a signal of the terminal reaches the whole process group; a worker ignores it and the primary decides.
  if not can_run_workers() then return end
  if not workers.can_raise_signals() then return end -- raised with kill; Windows delivers console signals only
  local app = new_application({ signals = false })
  local ok, err, target, before, after, alive_after
  with_lua_paths(function()
    reactor.run(function()
      reactor.fork(function()
        local inner_ok, inner_err = pcall(function()
          wait_ready(app)
          local port = app:local_address().port
          for _ = 1, 4 do
            local body = get(port, "/whoami")
            target = target or (body and body:match('"pid"%s*:%s*(%d+)'))
          end
          before = app._supervisor:started_count()
          uv.kill(tonumber(target), "sigint")
          uv.kill(tonumber(target), "sigterm")
          -- A worker that took the default action would be gone (and restarted) by now; it still answers.
          reactor.sleep(0.5)
          local seen = {}
          for _ = 1, 4 do
            local body = get(port, "/whoami")
            local pid = body and body:match('"pid"%s*:%s*(%d+)')
            if pid then seen[pid] = true end
          end
          alive_after = seen[target] == true and workers.alive(target)
          after = app._supervisor:started_count()
        end)
        app:shutdown(5)
        if not inner_ok then error(inner_err, 0) end
      end)
      ok, err = pcall(reactor.deadline, 30, app.serve, app)
    end)
  end)
  self:assert_true(ok, tostring(err))
  self:assert_not_nil(target)
  self:assert_true(alive_after, "the signalled worker still serves")
  self:assert_equal(before, after, "no worker was restarted")
end

function T:test_a_forced_stop_kills_the_workers()
  if not can_run_workers() then return end
  local app = new_application({ signals = false })
  local ok, err
  with_lua_paths(function()
    reactor.run(function()
      reactor.fork(function()
        wait_ready(app)
        app._supervisor:force()
      end)
      ok, err = pcall(reactor.deadline, 30, app.serve, app)
    end)
  end)
  self:assert_true(ok, tostring(err))
  self:assert_false(core.is_instance_of(err, core.Error))
end

--- The sorted pids of the workers that answer `count` requests.
local function pids_of(port, count)
  local pids = {}
  for _ = 1, count do
    local body = get(port, "/whoami")
    local pid = body and body:match('"pid"%s*:%s*(%d+)')
    if pid then pids[pid] = true end
  end
  return pids
end

local function codes_of(memory)
  local codes = {}
  for _, record in ipairs(memory:records()) do
    local code = record.fields and record.fields.code
    if code then codes[#codes + 1] = code end
  end
  return codes
end

--- Sends one request and counts it in `tally` (`answered`, `failures`); a failure records its reason, its time
--- relative to `tally.origin` and the log codes seen so far (`codes`, the memory sink of the primary, may be nil).
local function count_request(tally, port, memory)
  local content, reason = get(port, "/whoami")
  if content ~= nil then
    tally.answered = tally.answered + 1
    return
  end
  tally.failures = tally.failures + 1
  local last
  if memory ~= nil then
    local records = memory:records()
    for i = #records, 1, -1 do
      local code = records[i].fields and records[i].fields.code
      if code then last = code break end
    end
  end
  tally.reasons[#tally.reasons + 1] = ("%s at +%.3f s (last event: %s)"):format(tostring(reason),
    reactor.now() - tally.origin, tostring(last))
end

--- The log events of the primary, in order, with the fields that tell a lost connection apart.
local function describe_events(memory)
  local parts = {}
  for _, record in ipairs(memory:records()) do
    local fields = record.fields or {}
    if fields.code then
      local text = tostring(fields.code)
      if fields.worker then text = text .. "#" .. tostring(fields.worker) end
      if fields.handed then text = ("%s(handed %s, accepted %s)"):format(text, tostring(fields.handed), tostring(fields.accepted)) end
      if fields.reason then text = text .. "(" .. tostring(fields.reason) .. ")" end
      parts[#parts + 1] = text
    end
  end
  return table.concat(parts, ", ")
end

local function new_tally() return { answered = 0, failures = 0, reasons = {}, origin = reactor.now() } end

local function contains(list, value)
  for _, item in ipairs(list) do if item == value then return true end end
  return false
end

function T:test_reload_replaces_the_workers_without_failing_a_request()
  if not can_run_workers() then return end
  local memory = log.MemorySink()
  local app = new_application({ logger = log.Logger({ sinks = { memory } }), signals = false })
  local ok, err, before, after, tally = nil, nil, {}, {}, nil
  with_lua_paths(function()
    reactor.run(function()
      reactor.fork(function()
        wait_ready(app)
        local port = app:local_address().port
        before = pids_of(port, 6)
        local reloading = true
        tally = new_tally()
        local client = reactor.fork(function()
          while reloading do count_request(tally, port, memory) end
        end)
        app:reload({ grace_timeout = 5 })
        reloading = false
        client:value()
        after = pids_of(port, 6)
        app:shutdown(5)
      end)
      ok, err = pcall(reactor.deadline, 60, app.serve, app)
    end)
  end)
  self:assert_true(ok, tostring(err))
  local function count(set) local n = 0 for _ in pairs(set) do n = n + 1 end return n end
  self:assert_equal(2, count(before))
  self:assert_equal(2, count(after))
  for pid in pairs(after) do self:assert_nil(before[pid], "a worker of before the reload still answers") end
  self:assert_equal(0, tally.failures, table.concat(tally.reasons, "; ") .. " | events: " .. describe_events(memory))
  self:assert_true(tally.answered > 0)
  local codes = codes_of(memory)
  self:assert_true(contains(codes, "reload_started"))
  self:assert_true(contains(codes, "reload_done"))
end

function T:test_a_reload_resets_no_connection_handed_over_just_before_the_stop()
  if not can_run_workers() then return end
  local memory = log.MemorySink()
  local app = new_application({ logger = log.Logger({ sinks = { memory } }), signals = false })
  local ok, err, reloads, tally = nil, nil, 0, nil
  local CLIENTS = 4
  with_lua_paths(function()
    reactor.run(function()
      reactor.fork(function()
        wait_ready(app)
        local port = app:local_address().port
        local reloading = true
        local clients = {}
        tally = new_tally()
        -- Short requests in a tight loop from several clients: some connection is always on its way to the worker that
        -- the primary is about to stop. The reload must reset none of them.
        for _ = 1, CLIENTS do
          clients[#clients + 1] = reactor.fork(function()
            while reloading do count_request(tally, port, memory) end
          end)
        end
        for _ = 1, 2 do
          app:reload({ grace_timeout = 5 })
          reloads = reloads + 1
        end
        reloading = false
        for _, client in ipairs(clients) do client:value() end
        app:shutdown(5)
      end)
      ok, err = pcall(reactor.deadline, 90, app.serve, app)
    end)
  end)
  self:assert_true(ok, tostring(err))
  self:assert_equal(2, reloads)
  self:assert_equal(0, tally.failures, table.concat(tally.reasons, "; ") .. " | events: " .. describe_events(memory))
  self:assert_true(tally.answered >= CLIENTS * 2, "the clients were served during the reloads")
end

function T:test_sighup_starts_the_reload_and_a_terminal_signal_during_it_stops()
  if not can_run_workers() then return end
  if not workers.can_raise_signals() then return end -- libuv delivers no sighup there
  local guard, hup_guard = uv.new_signal(), uv.new_signal() -- installed before any signal is raised: a signal that finds no watcher does not end the test process
  guard:start("sigterm", function() end)
  hup_guard:start("sighup", function() end)
  local memory = log.MemorySink()
  local app = new_application({ logger = log.Logger({ sinks = { memory } }) })
  local ok, err, before, after = nil, nil, {}, {}
  with_lua_paths(function()
    reactor.run(function()
      reactor.fork(function()
        wait_ready(app)
        local port = app:local_address().port
        before = pids_of(port, 6)
        uv.kill(uv.os_getpid(), "sighup")
        wait_until(function() return contains(codes_of(memory), "reload_done") end)
        after = pids_of(port, 6)
        uv.kill(uv.os_getpid(), "sigterm")
      end)
      ok, err = pcall(reactor.deadline, 60, app.serve, app)
    end)
  end)
  guard:close()
  hup_guard:close()
  self:assert_true(ok, tostring(err))
  for pid in pairs(after) do self:assert_nil(before[pid], "a worker of before the reload still answers") end
  self:assert_true(next(after) ~= nil)
  local codes = codes_of(memory)
  self:assert_true(contains(codes, "reload_started"))
  self:assert_true(contains(codes, "shutdown_signal"))
end

function T:test_reload_needs_a_serving_primary()
  local app = kernel.Application({ logger = log.Logger({ sinks = {} }) })
  reactor.run(function()
    local err = self:assert_error(function() app:reload() end)
    self:assert_true(core.is_instance_of(err, core.StateError), tostring(err))
  end)
end

function T:test_sighup_is_ignored_by_a_single_process()
  if not workers.can_raise_signals() then return end
  local guard, hup_guard = uv.new_signal(), uv.new_signal()
  guard:start("sigterm", function() end)
  hup_guard:start("sighup", function() end)
  local memory = log.MemorySink()
  local routes = kernel.routes("single")
  routes:get("/ping", { action = function() return { pong = true } end })
  local app = kernel.Application({
    routes = { routes }, logger = log.Logger({ sinks = { memory }, severity = "debug" }), server = { host = "127.0.0.1", port = 0 },
  })
  local ok, err, body = nil, nil, nil
  reactor.run(function()
    reactor.fork(function()
      wait_until(function() return app:local_address() ~= nil end)
      -- The watcher exists once the address is known; the signal is raised until the application says it ignored one.
      wait_until(function()
        uv.kill(uv.os_getpid(), "sighup")
        return contains(codes_of(memory), "reload_ignored")
      end)
      body = get(app:local_address().port, "/ping")
      uv.kill(uv.os_getpid(), "sigterm")
    end)
    ok, err = pcall(reactor.deadline, 30, app.serve, app)
  end)
  guard:close()
  hup_guard:close()
  self:assert_true(ok, tostring(err))
  self:assert_not_nil(body) -- still serving after the sighup
  self:assert_true(body:find("pong", 1, true) ~= nil)
  self:assert_false(contains(codes_of(memory), "reload_started"), "a single process does not reload")
end

return T
