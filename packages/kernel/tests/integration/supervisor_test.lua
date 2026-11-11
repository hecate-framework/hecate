-- The supervisor of the workers (ADR 0023) with real worker processes (tests/fixtures/worker_app.lua), on every
-- platform: connections spread over the workers, a worker that exits is restarted, a crash loop stops the
-- supervisor, `stop` ends every worker.
---@diagnostic disable: need-check-nil, param-type-mismatch, missing-fields, undefined-field, inject-field
local test = require("harness.test")
local uv = require("luv")
local core = require("hecate.core")
local net = require("hecate.net")
local reactor = require("hecate.reactor")
local kernel = require("hecate.kernel")
local T = test.Case("SupervisorTest")

local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]integration[/\\][^/\\]+$") or "."
local worker_script = uv.fs_realpath(here .. "/fixtures/worker_app.lua") or here .. "/fixtures/worker_app.lua"

--- Makes the relative entries of a search path absolute.
local function absolute(search_path)
  local entries = {}
  for entry in search_path:gmatch("[^;]+") do
    local resolved = entry
    if not (entry:match("^[/\\]") or entry:match("^%a:") or entry:match("^!")) then resolved = uv.cwd() .. "/" .. entry end
    entries[#entries + 1] = resolved
  end
  return table.concat(entries, ";")
end

local function lua_env(extra)
  local path, cpath = absolute(package.path), absolute(package.cpath)
  local env = { LUA_PATH = path, LUA_PATH_5_5 = path, LUA_CPATH = cpath, LUA_CPATH_5_5 = cpath }
  for name, value in pairs(extra or {}) do env[name] = value end
  return env
end

local function new_supervisor(options)
  options.command = { uv.exepath(), worker_script }
  options.endpoint = options.endpoint or { host = "127.0.0.1", port = 0 }
  options.strategy = options.strategy or kernel.listening.select("round_robin")
  options.env = lua_env(options.env)
  return kernel.supervisor.Supervisor(options)
end

--- Waits (at most 20 s) until `predicate()` holds.
local function wait_until(predicate)
  reactor.deadline(20, function()
    while not predicate() do reactor.sleep(0.02) end
  end)
end

--- One request with `Connection: close`; returns the content, or nil when the connection ended without an answer.
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
  local answer = table.concat(parts)
  return answer:match("\r\n\r\n(.*)$")
end

function T:test_connections_are_spread_over_the_workers_and_stop_ends_them()
  reactor.run(function()
    local sup = new_supervisor({ count = 2 })
    reactor.scope(function(scope)
      local running = scope:fork(sup.run, sup)
      wait_until(function() return sup:ready_count() == 2 end)
      local port = sup:local_address().port
      local seen = {}
      for _ = 1, 6 do
        local content = get(port, "/")
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
  reactor.run(function()
    local sup = new_supervisor({ count = 1, restart_delay = 0.01 })
    reactor.scope(function(scope)
      local running = scope:fork(sup.run, sup)
      wait_until(function() return sup:ready_count() == 1 end)
      local port = sup:local_address().port
      local first = get(port, "/")
      self:assert_nil(get(port, "/crash"))
      wait_until(function() return sup:started_count() == 2 and sup:ready_count() == 1 end)
      local second = get(port, "/")
      self:assert_not_nil(second)
      self:assert_true(first ~= second, "a new process serves after the restart")
      sup:stop(5)
      running:value()
    end)
  end)
end

function T:test_a_crash_loop_stops_the_supervisor()
  reactor.run(function()
    local sup = new_supervisor({ count = 2, restart_delay = 0.01, crash_limit = 3, env = { HECATE_TEST_MODE = "exit" } })
    local err = self:assert_error(function() sup:run() end)
    self:assert_true(core.is_instance_of(err, kernel.SupervisorError), tostring(err))
    self:assert_equal("crash_loop", err.context.reason)
    self:assert_equal(0, sup:ready_count())
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
end

function T:test_this_process_has_no_worker_role()
  self:assert_nil(kernel.supervisor.worker_role())
end

return T
