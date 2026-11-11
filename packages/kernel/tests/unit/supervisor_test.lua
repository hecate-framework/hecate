-- `Supervisor:local_address` without worker processes: a fake strategy whose `prepare` suspends shows what a caller
-- sees while the primary's socket is not bound yet.
---@diagnostic disable: need-check-nil, param-type-mismatch, missing-fields, undefined-field, inject-field
local test = require("harness.test")
local reactor = require("hecate.reactor")
local kernel = require("hecate.kernel")
local T = test.Case("SupervisorUnitTest")

--- A strategy whose `prepare` waits on `gate`, then reports `address`; workers are never started (the command fails).
local function gated_strategy(gate, address)
  return {
    name = "gated",
    prepare = function(_, _) gate:receive(); return address end,
    run = function() reactor.sleep(60) end,
    close = function() end,
  }
end

--- Runs a supervisor with `endpoint`; `observe(sup, open)` runs beside it, `open()` lets `prepare` return.
local function with_gated_supervisor(endpoint, address, observe)
  local gate = reactor.Channel(1)
  local sup = kernel.supervisor.Supervisor({
    command = { "hecate-no-such-program" }, count = 1, endpoint = endpoint, strategy = gated_strategy(gate, address),
  })
  reactor.run(function()
    reactor.fork(function() observe(sup, function() gate:send(true) end) end)
    pcall(reactor.deadline, 10, sup.run, sup) -- ends with start_failed: no worker program
  end)
end

function T:test_an_ephemeral_port_is_unknown_until_the_socket_is_bound()
  local before, after
  with_gated_supervisor({ host = "127.0.0.1", port = 0 }, { ip = "127.0.0.1", port = 41234, family = "inet" },
    function(sup, open)
      reactor.sleep(0.01)
      before = sup:local_address() or false
      open()
      reactor.sleep(0)
      after = sup:local_address()
    end)
  self:assert_false(before) -- not `{ port = 0 }`, which a caller cannot connect to
  self:assert_equal(41234, after.port)
end

function T:test_a_fixed_port_is_reported_while_preparing()
  local seen
  with_gated_supervisor({ host = "127.0.0.1", port = 8123 }, nil, function(sup, open)
    reactor.sleep(0.01)
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

--- Waits (at most 10 s) until `predicate()` holds.
local function wait_until(predicate)
  reactor.deadline(10, function()
    while not predicate() do reactor.sleep(0.005) end
  end)
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
  local core = require("hecate.core")
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

return T
