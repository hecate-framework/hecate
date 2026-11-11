-- `Application` with `workers = 2` (ADR 0023): the primary runs a supervisor, the workers (tests/fixtures/
-- application_worker.lua, the same application started again) boot it and serve through the worker role, clients are
-- answered, a signal stops the primary and its workers cleanly. Runs where `reactor.spawn` with a message pipe works (the
-- three platforms of the CI; a platform that reports no spawn or handle passing skips the tests, any other failure to
-- start a worker fails the test).
---@diagnostic disable: need-check-nil, param-type-mismatch, missing-fields, undefined-field, inject-field
local test = require("harness.test")
local uv = require("luv")
local core = require("hecate.core")
local net = require("hecate.net")
local reactor = require("hecate.reactor")
local log = require("hecate.log")
local kernel = require("hecate.kernel")
local T = test.Case("ApplicationWorkersTest")

local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]integration[/\\][^/\\]+$") or "."
local worker_script = uv.fs_realpath(here .. "/fixtures/application_worker.lua") or here .. "/fixtures/application_worker.lua"

--- Makes the relative entries of a search path absolute (the workers start in the same directory, but be safe).
local function absolute(search_path)
  local entries = {}
  for entry in search_path:gmatch("[^;]+") do
    local resolved = entry
    if not (entry:match("^[/\\]") or entry:match("^%a:") or entry:match("^!")) then resolved = uv.cwd() .. "/" .. entry end
    entries[#entries + 1] = resolved
  end
  return table.concat(entries, ";")
end

--- Gives the workers (they inherit this process's environment) the search paths of this process while `body` runs.
local function with_lua_paths(body)
  local names = { "LUA_PATH", "LUA_PATH_5_5", "LUA_CPATH", "LUA_CPATH_5_5" }
  local saved = {}
  for _, name in ipairs(names) do saved[name] = uv.os_getenv(name) end
  local path, cpath = absolute(package.path), absolute(package.cpath)
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

--- One request with `Connection: close`; returns the body, or nil when the connection ended without an answer.
local function get(port, path)
  local stream = net.connect("127.0.0.1", port)
  stream:write(("GET %s HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"):format(path))
  local parts = {}
  while true do
    local ok, data = pcall(stream.read, stream)
    if not ok or data == nil then break end
    parts[#parts + 1] = data
  end
  stream:close()
  return table.concat(parts):match("\r\n\r\n(.*)$")
end

local function wait_until(predicate)
  reactor.deadline(20, function()
    while not predicate() do reactor.sleep(0.02) end
  end)
end

local function wait_ready(app)
  wait_until(function() return app._supervisor ~= nil and app._supervisor:ready_count() == 2 end)
end

--- Tells whether the platform can run the workers; prints why not and lets the test return when it cannot.
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

function T:test_clients_are_answered_by_both_workers_and_a_signal_stops_everything()
  if not can_run_workers() then return end
  if uv.os_uname().sysname:match("Windows") then return end -- the signal is raised with kill; Windows delivers console signals only
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

return T
