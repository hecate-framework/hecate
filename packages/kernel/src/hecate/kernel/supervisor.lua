-- Multi-process serving, the policy half (ADR 0023, "Mechanism in `reactor`, policy in `kernel`"): the supervisor in
-- the primary starts the workers, adds each to the rotation once it is ready, restarts a worker that exits with an
-- exponential backoff and a crash-loop limit, and stops them gracefully; the worker side reads the control messages of
-- the primary, feeds the connections it hands over to the server, and drains on `stop` or when the message pipe
-- closes (the primary died). The control messages are the same on every platform (Decision 5): `ready` (worker to
-- primary), `stop <seconds>` and `connection` with a stream (primary to worker). The rolling reload replaces workers
-- by restart (a fresh process from the same command, ready before the old one is stopped), so it needs no message of its
-- own: `reload` stays reserved in the protocol, unused, and a worker never sees it.
global <const> require, type, error, pcall, tostring, tonumber, math, table, ipairs, pairs, os

local core = require("hecate.core")
local reactor = require("hecate.reactor")
local log = require("hecate.log")
local listening = require("hecate.kernel.listening")
local errors = require("hecate.kernel.errors")

--- Multi-process serving: the supervisor of the workers in the primary and the worker side.
---@class hecate.kernel.supervisors
local supervisor = {}

--- Environment variables the primary gives each worker (the worker role, ADR 0023 Decision 1).
local ENV <const> = {
  index = "HECATE_WORKER_INDEX",
  strategy = "HECATE_WORKER_STRATEGY",
  host = "HECATE_WORKER_HOST",
  port = "HECATE_WORKER_PORT",
  backlog = "HECATE_WORKER_BACKLOG",
}
supervisor.ENV = ENV

--- Seconds after the grace period before the primary kills a worker that has not exited.
local KILL_MARGIN <const> = 1

---@param seconds any
---@return boolean
local function is_duration(seconds)
  return type(seconds) == "number" and seconds == seconds and seconds >= 0 and seconds < math.huge
end

--- Tells whether a text looks like an IP literal (IPv4 or IPv6, hexadecimal digits, colons and dots) or like a host name
--- (letters, digits, hyphens and dots, at most 253 characters): no space, no other character. Does not resolve anything.
---@param host any
---@return boolean
local function is_host(host)
  if type(host) ~= "string" or host == "" or #host > 253 then return false end
  if host:find(":", 1, true) then return host:match("^[%x:%.]+$") ~= nil end
  return host:match("^[%w][%w%.%-]*$") ~= nil
end

-- The primary --------------------------------------------------------------------------------------------------------

--- Options of `Supervisor`.
---@class hecate.kernel.SupervisorOptions
---@field command string[]  the worker program and its arguments (`{ interpreter, main program, ... }`): the same program as the primary, started again with the worker role
---@field count integer  number of workers, at least 1
---@field endpoint hecate.kernel.Endpoint  where the application listens
---@field strategy? hecate.kernel.ListeningStrategy  default `listening.select("auto")`
---@field env? table<string, string>  variables added to the environment of each worker
---@field logger? hecate.log.Logger  receives worker exits, restarts and the crash loop
---@field restart_delay? number  seconds before the first restart of a worker (default 0.1), doubled at each crash in the crash window, at most 10 s
---@field crash_limit? integer  crashes within `crash_window` that stop the supervisor (default 5)
---@field crash_window? number  seconds (default 60)
---@field on_crash_loop? "stop"|"degrade"  what a crash loop does: `stop` (default) ends `run` with a `SupervisorError`; `degrade` keeps restarting the workers at the maximum backoff (10 s), logs `crash_loop` at `error` once per crash window, and never ends `run` by itself

--- The supervisor of the workers, in the primary.
---@class hecate.kernel.Supervisor
---@overload fun(options: hecate.kernel.SupervisorOptions): hecate.kernel.Supervisor
local Supervisor = core.class("Supervisor")

local KNOWN = {
  command = true, count = true, endpoint = true, strategy = true, env = true, logger = true, restart_delay = true,
  crash_limit = true, crash_window = true, on_crash_loop = true,
}

--- The longest delay before a restart (the cap of the backoff, and the pace of a degraded crash loop).
local MAX_BACKOFF <const> = 10

--- Checks the options; nothing starts until `run`.
---
--- Raises `hecate.core.ArgumentError` for an unknown or malformed option.
---@param options hecate.kernel.SupervisorOptions
function Supervisor:init(options)
  if type(options) ~= "table" then error(core.ArgumentError("hecate.kernel.supervisor.init: options must be a table, got " .. type(options)), 2) end
  for key in pairs(options) do
    if not KNOWN[key] then
      local names = {}
      for name in pairs(KNOWN) do names[#names + 1] = name end
      table.sort(names)
      error(core.ArgumentError(("hecate.kernel.supervisor.init: unknown option '%s' (valid: %s)"):format(tostring(key), table.concat(names, ", "))), 2)
    end
  end
  local command = options.command
  if type(command) ~= "table" or type(command[1]) ~= "string" then
    error(core.ArgumentError("hecate.kernel.supervisor.init: command must be a list of strings, the program first, got " .. type(command)), 2)
  end
  for i = 1, #command do
    if type(command[i]) ~= "string" then error(core.ArgumentError("hecate.kernel.supervisor.init: command must be a list of strings, got a " .. type(command[i]) .. " at " .. i), 2) end
  end
  if math.type(options.count) ~= "integer" or options.count < 1 then
    error(core.ArgumentError("hecate.kernel.supervisor.init: count must be an integer of at least 1, got " .. tostring(options.count)), 2)
  end
  if type(options.endpoint) ~= "table" then error(core.ArgumentError("hecate.kernel.supervisor.init: endpoint must be a table, got " .. type(options.endpoint)), 2) end
  for _, key in ipairs({ "restart_delay", "crash_window" }) do
    if options[key] ~= nil and not is_duration(options[key]) then
      error(core.ArgumentError(("hecate.kernel.supervisor.init: %s must be a non-negative finite number of seconds, got %s"):format(key, tostring(options[key]))), 2)
    end
  end
  if options.crash_limit ~= nil and (math.type(options.crash_limit) ~= "integer" or options.crash_limit < 1) then
    error(core.ArgumentError("hecate.kernel.supervisor.init: crash_limit must be an integer of at least 1, got " .. tostring(options.crash_limit)), 2)
  end
  if options.on_crash_loop ~= nil and options.on_crash_loop ~= "stop" and options.on_crash_loop ~= "degrade" then
    error(core.ArgumentError(("hecate.kernel.supervisor.init: on_crash_loop must be \"stop\" or \"degrade\", got %s"):format(
      type(options.on_crash_loop) == "string" and ("%q"):format(options.on_crash_loop) or type(options.on_crash_loop))), 2)
  end
  self._options = options
  self._crash_loop_logged = nil ---@type number?  when `crash_loop` was last logged (degraded mode)
  self._strategy = options.strategy or listening.select("auto", { logger = options.logger })
  self._logger = options.logger
  self._ring = listening.WorkerRing()
  self._slots = {}
  self._crashes = {}
  self._started = 0
  self._ready = 0
  self._stopping = false
  self._reloading = false
  self._reload_end = nil ---@type hecate.reactor.Channel?
  self._state = "new" -- new, running, stopped
  self._requests = reactor.Channel(1) -- the grace period of the first stop request
  self._finished = reactor.Channel(0) -- closed once `run` has stopped every worker
  self._failure = nil
end

---@param self hecate.kernel.Supervisor
---@param severity string
---@param message string
---@param fields table
local function note(self, severity, message, fields)
  if self._logger ~= nil then self._logger:log(severity, "kernel.Supervisor: " .. message, fields) end
end

--- Asks `run` to stop, with `grace` seconds; only the first request counts. Never suspends.
---@param self hecate.kernel.Supervisor
---@param grace number
local function request_stop(self, grace)
  local requests = self._requests
  if not requests:is_closed() and requests:length() == 0 then
    ---@diagnostic disable-next-line: await-in-sync  -- room in the buffer: does not suspend
    requests:send(grace)
  end
end

--- The environment of a worker.
---@param self hecate.kernel.Supervisor
---@param index integer
---@return table<string, string>
local function worker_env(self, index)
  local env = {}
  for name, value in pairs(self._options.env or {}) do env[name] = value end
  local endpoint, address = self._options.endpoint, self._address
  env[ENV.index] = tostring(index)
  env[ENV.strategy] = self._strategy.name
  env[ENV.host] = address and address.ip or endpoint.host
  env[ENV.port] = tostring(address and address.port or endpoint.port)
  if endpoint.backlog ~= nil then env[ENV.backlog] = tostring(endpoint.backlog) end
  return env
end

--- Records a crash and returns the delay before the restart, or nil when the crash-loop limit is reached.
---@param self hecate.kernel.Supervisor
---@return number?
local function crash_delay(self)
  local options = self._options
  local window, limit = options.crash_window or 60, options.crash_limit or 5
  local now = reactor.now()
  local recent = {}
  for _, at in ipairs(self._crashes) do if now - at < window then recent[#recent + 1] = at end end
  recent[#recent + 1] = now
  self._crashes = recent
  if #recent >= limit then return nil end
  return math.min((options.restart_delay or 0.1) * 2 ^ (#recent - 1), MAX_BACKOFF)
end

--- One process of a worker slot: its message pipe, its place in the rotation and what the supervisor knows of it.
---@class hecate.kernel.WorkerGeneration
---@field process hecate.reactor.Process
---@field peer hecate.reactor.Peer
---@field target hecate.kernel.HandOverTarget  what the ring hands connections to
---@field ready boolean  reported `ready` and counted in `ready_count`
---@field planned boolean  being replaced by a reload: its exit is not a crash
---@field finished boolean  has exited and been reaped
---@field done hecate.reactor.Channel  closed once it has exited

--- A worker slot, the unit the supervisor keeps alive.
---@class hecate.kernel.WorkerSlot
---@field index integer
---@field gen hecate.kernel.WorkerGeneration?  the process in service (or starting), nil while the slot waits to restart
---@field next hecate.kernel.WorkerGeneration?  the replacement of a reload, ready, that takes over once `gen` has exited
---@field waiting boolean
---@field future hecate.reactor.Future?

--- Starts a worker process for `slot`; nil and the reason when the program cannot be started.
---@param self hecate.kernel.Supervisor
---@param slot hecate.kernel.WorkerSlot
---@return hecate.kernel.WorkerGeneration? generation
---@return any? reason
local function start_worker(self, slot)
  local command = self._options.command
  local args = table.move(command, 2, #command, 1, {})
  local started, process = pcall(reactor.spawn, command[1], args, { ipc = true, env = worker_env(self, slot.index) }) -- glossary-ok: operating-system process (ADR 0023)
  if not started then return nil, process end
  self._started = self._started + 1
  local peer = process.ipc --[[@as hecate.reactor.Peer]]
  return {
    process = process, peer = peer, ready = false, planned = false, finished = false, done = reactor.Channel(0),
    target = { hand_over = function(_, stream) peer:send("connection", stream) end },
  }
end

--- Runs one worker slot: starts the worker, reads its messages until its message pipe ends, waits for it, and
--- restarts it unless the supervisor stops. A worker that a reload replaced (`planned`) is followed by its
--- replacement, which the reload has started and found ready: no restart, no crash accounting. Never raises (a
--- failure stops the supervisor, `_failure`).
---@async
---@param self hecate.kernel.Supervisor
---@param slot hecate.kernel.WorkerSlot
local function supervise(self, slot)
  local gen ---@type hecate.kernel.WorkerGeneration?
  while true do
    if gen == nil then
      if self._stopping then return end
      local spawned, reason = start_worker(self, slot)
      if spawned == nil then
        self._failure = self._failure or errors.SupervisorError(("hecate.kernel.supervisor.run: cannot start a worker: %s"):format(tostring(reason)),
          { context = { reason = "start_failed" } })
        request_stop(self, 0)
        return
      end
      gen = spawned
    end
    slot.gen = gen
    local peer = gen.peer
    while true do
      local ok, message, stream = pcall(peer.receive, peer)
      if not ok or message == nil then break end
      -- The primary expects no stream from a worker: one that arrives is closed, not leaked (a descriptor each).
      if stream ~= nil then pcall(stream.close, stream) end
      if message == "ready" and not gen.ready and not gen.planned then
        gen.ready = true
        self._ready = self._ready + 1
        if not self._stopping then self._ring:add(gen.target) end
      end
    end
    self._ring:remove(gen.target)
    if gen.ready then self._ready = self._ready - 1 end
    peer:close()
    local status = gen.process:wait()
    gen.finished = true
    slot.gen = nil
    gen.done:close()
    local successor = slot.next
    if gen.planned and successor ~= nil then
      slot.next, gen = nil, successor
    else
      local exited = gen
      gen = nil
      if self._stopping then return end
      local delay = crash_delay(self)
      note(self, "warning", "a worker exited; restarting it", {
        code = "worker_exited", worker = slot.index, pid = exited.process.pid, exit_code = status.code, signal = status.signal,
      })
      if delay == nil and self._options.on_crash_loop == "degrade" then
        -- Degraded mode: the limit is reached, the supervisor keeps trying at the slowest pace and says so once per window.
        delay = MAX_BACKOFF
        local now, window = reactor.now(), self._options.crash_window or 60
        if self._crash_loop_logged == nil or now - self._crash_loop_logged >= window then
          self._crash_loop_logged = now
          note(self, "error", "crash loop: restarting the workers at the maximum backoff", { code = "crash_loop", delay = delay })
        end
      end
      if delay == nil then
        self._failure = self._failure or errors.SupervisorError(
          "hecate.kernel.supervisor.run: workers keep exiting (crash loop); stopping", { context = { reason = "crash_loop" } })
        note(self, "error", "crash loop: stopping every worker", { code = "crash_loop" })
        request_stop(self, 0)
        return
      end
      slot.waiting = true
      local slept, err = pcall(reactor.sleep, delay)
      slot.waiting = false
      if not slept then
        if self._stopping then return end
        error(err, 0)
      end
    end
  end
end

--- The processes of a slot that may be running: the one in service and a replacement not taken over yet.
---@param slot hecate.kernel.WorkerSlot
---@return hecate.kernel.WorkerGeneration[]
local function live(slot)
  local list = {}
  if slot.gen ~= nil then list[#list + 1] = slot.gen end
  if slot.next ~= nil then list[#list + 1] = slot.next end
  return list
end

--- Stops every worker: removes them from the rotation, sends `stop` with the grace period, kills those still running
--- after it (plus one second), and waits for every slot to end. A replacement a reload has started is stopped too.
---@async
---@param self hecate.kernel.Supervisor
---@param grace number
local function stop_workers(self, grace)
  self._stopping = true
  self._strategy:close()
  self._ring:close()
  local message = "stop " .. tostring(grace)
  for _, slot in ipairs(self._slots) do
    if slot.waiting and slot.future ~= nil then slot.future:cancel() end
    for _, gen in ipairs(live(slot)) do pcall(gen.peer.send, gen.peer, message) end
  end
  local function wait_all()
    for _, slot in ipairs(self._slots) do
      if slot.future ~= nil then
        local waited, failure = pcall(slot.future.value, slot.future)
        -- The cancellation of the deadline that bounds the wait must not be swallowed here (the future is then still
        -- pending), or a worker that ignores `stop` is never killed. A future that ended by itself is not that case.
        if not waited and slot.future:state() == "pending" and core.is_instance_of(failure, core.CancellationError) then
          error(failure, 0)
        end
      end
    end
    local reload_end = self._reload_end -- a reload in flight ends once its replacement has exited (killed below at the latest)
    if reload_end ~= nil then
      local received, err = pcall(reload_end.receive, reload_end)
      if not received and core.is_instance_of(err, core.CancellationError) then error(err, 0) end
    end
  end
  local in_time = pcall(reactor.deadline, grace + KILL_MARGIN, wait_all)
  if not in_time then
    for _, slot in ipairs(self._slots) do
      for _, gen in ipairs(live(slot)) do
        if gen.process:is_running() then
          note(self, "warning", "a worker did not stop in time; killing it", { code = "worker_killed", worker = slot.index, pid = gen.process.pid })
          pcall(gen.process.kill, gen.process, "sigkill")
        end
      end
    end
    wait_all()
  end
end

--- Binds the endpoint (`prepare` of the strategy), starts the workers and hands connections over to them, until
--- `stop`. Returns once every worker has exited.
---
--- Raises `hecate.kernel.SupervisorError` (`context.reason`: `crash_loop` when workers kept exiting, `start_failed`
--- when the program cannot be started, `already_run`), and what the strategy's `prepare` raises.
---@async
function Supervisor:run()
  if self._state ~= "new" then
    error(errors.SupervisorError("hecate.kernel.supervisor.run: run was already called", { context = { reason = "already_run" } }), 2)
  end
  self._state = "running"
  local ok, err = pcall(function()
    self._address = self._strategy:prepare(self._options.endpoint)
    reactor.scope(function(scope)
      for index = 1, self._options.count do
        local slot = { index = index, waiting = false }
        self._slots[index] = slot
        slot.future = scope:fork(supervise, self, slot)
      end
      local handing_over = scope:fork(function() self._strategy:run(self._ring) end)
      local grace = self._requests:receive()
      stop_workers(self, grace)
      handing_over:cancel()
    end)
  end)
  self._state = "stopped"
  self._requests:close()
  self._finished:close()
  if not ok then
    self._strategy:close()
    error(err, 0)
  end
  if self._failure ~= nil then error(self._failure, 0) end
end

--- Stops the workers gracefully: each stops accepting and drains its requests for `grace_timeout` seconds, then is
--- killed. Returns once `run` has returned. Does nothing when not running; a second call waits for the first.
---
--- Raises `hecate.core.ArgumentError` for a malformed `grace_timeout`.
---@async
---@param grace_timeout? number  seconds, default 30
function Supervisor:stop(grace_timeout)
  if grace_timeout ~= nil and not is_duration(grace_timeout) then
    error(core.ArgumentError("hecate.kernel.supervisor.stop: grace_timeout must be a non-negative finite number of seconds, got " .. tostring(grace_timeout)), 2)
  end
  if self._state ~= "running" then return end
  request_stop(self, grace_timeout or 30)
  pcall(self._finished.receive, self._finished)
end

--- Asks `gen` to leave the rotation and stop with `grace` seconds, waits for it to exit, and kills it when it does not
--- in time (as `stop` does).
---@async
---@param self hecate.kernel.Supervisor
---@param slot hecate.kernel.WorkerSlot
---@param gen hecate.kernel.WorkerGeneration
---@param grace number
local function retire(self, slot, gen, grace)
  note(self, "informational", "stopping the replaced worker", { code = "reload_old_stopping", worker = slot.index, pid = gen.process.pid })
  pcall(gen.peer.send, gen.peer, "stop " .. tostring(grace))
  local ok, err = pcall(reactor.deadline, grace + KILL_MARGIN, function()
    local received, failure = pcall(gen.done.receive, gen.done)
    -- The cancellation of the deadline must not be swallowed here, or a worker that ignores `stop` is never killed.
    if not received and core.is_instance_of(failure, core.CancellationError) then error(failure, 0) end
  end)
  if not ok then
    if not core.is_instance_of(err, core.DeadlineExceededError) then error(err, 0) end
    if gen.process:is_running() then
      note(self, "warning", "a replaced worker did not stop in time; killing it", { code = "worker_killed", worker = slot.index, pid = gen.process.pid })
      pcall(gen.process.kill, gen.process, "sigkill")
    end
    pcall(gen.done.receive, gen.done)
  end
  note(self, "informational", "the replaced worker has exited", { code = "reload_old_exited", worker = slot.index, pid = gen.process.pid })
end

--- Kills and reaps a worker nobody supervises (a failed replacement).
---@async
---@param gen hecate.kernel.WorkerGeneration
local function discard(gen)
  pcall(gen.peer.close, gen.peer)
  if gen.process:is_running() then pcall(gen.process.kill, gen.process, "sigkill") end
  pcall(gen.process.wait, gen.process)
end

---@param self hecate.kernel.Supervisor
---@param slot hecate.kernel.WorkerSlot
---@param cause string
---@param message string
---@return hecate.kernel.SupervisorError
local function reload_failure(self, slot, cause, message)
  note(self, "error", message, { code = "reload_slot_failed", worker = slot.index, cause = cause })
  return errors.SupervisorError(("hecate.kernel.supervisor.reload: reload failed (worker %d): %s"):format(slot.index, message),
    { context = { reason = "reload_failed", cause = cause, worker = slot.index } })
end

--- Replaces the worker of `slot`: starts the replacement, waits for its `ready`, puts it in the rotation, then retires
--- the old one. The old worker is never taken out before the replacement is ready.
---@async
---@param self hecate.kernel.Supervisor
---@param slot hecate.kernel.WorkerSlot
---@param grace number
---@param ready_timeout number
local function replace(self, slot, grace, ready_timeout)
  if slot.gen == nil then -- waiting to restart: its restart starts the code on disk now
    note(self, "informational", "worker not running; its restart starts it afresh", { code = "reload_slot_skipped", worker = slot.index })
    return
  end
  local fresh, reason = start_worker(self, slot)
  if fresh == nil then error(reload_failure(self, slot, "start_failed", "cannot start a replacement: " .. tostring(reason)), 0) end
  slot.next = fresh
  local ok, got = pcall(reactor.deadline, ready_timeout, function()
    while true do
      local received, message, stream = pcall(fresh.peer.receive, fresh.peer)
      if not received then
        if core.is_instance_of(message, core.CancellationError) then error(message, 0) end
        return false
      end
      if message == nil then return false end
      if stream ~= nil then pcall(stream.close, stream) end -- a worker sends no stream to the primary
      if message == "ready" then return true end
    end
  end)
  local old = slot.gen
  local cause, text
  if not ok then
    if not core.is_instance_of(got, core.DeadlineExceededError) then
      slot.next = nil
      discard(fresh)
      error(got, 0)
    end
    cause, text = "not_ready", ("the replacement was not ready within %s s"):format(tostring(ready_timeout))
  elseif not got then
    cause, text = self._stopping and "stopping" or "exited", "the replacement exited before it was ready"
  elseif self._stopping then
    cause, text = "stopping", "the supervisor is stopping"
  elseif old == nil or old.finished or not old.process:is_running() then
    cause, text = "worker_lost", "the worker to replace exited meanwhile"
  end
  if cause ~= nil then
    slot.next = nil
    discard(fresh)
    error(reload_failure(self, slot, cause, text), 0)
  end
  ---@cast old hecate.kernel.WorkerGeneration
  note(self, "informational", "the replacement is ready", { code = "reload_replacement_ready", worker = slot.index, pid = fresh.process.pid })
  -- From here to the `stop` message nothing suspends: rotation, counters and `planned` change together.
  old.planned = true
  self._ring:add(fresh.target)
  self._ring:remove(old.target)
  fresh.ready = true
  if old.ready then old.ready = false else self._ready = self._ready + 1 end
  retire(self, slot, old, grace)
end

--- Replaces the workers one at a time with fresh processes started from the same command, so they run the code on
--- disk now (the rolling reload, ADR 0023 Decision 6). For each slot the replacement is started and awaited until it
--- reports `ready`, joins the rotation, and only then the old worker leaves it and is stopped with `grace_timeout`
--- seconds (then killed, as by `stop`): at most one worker is out of service at a time, and with `round_robin` the
--- primary stops handing connections over to the draining worker, so no connection is lost. With `reuseport` the connections queued
--- in the socket of a closing worker are reset by the kernel: the limit of that strategy, which a reload does not
--- hide. The number of workers does not change. A planned exit is not a crash: it does not count towards the
--- crash-loop limit and triggers no restart. No message is sent to a worker beyond `stop`.
---
--- Raises `hecate.kernel.SupervisorError` with `context.reason`: `reload_failed` (`context.cause`: `start_failed`,
--- `exited` or `not_ready`, a replacement that did not become ready, with `context.worker`; `worker_lost`, `stopping`;
--- the old worker stays in service and the slots already replaced stay replaced), `reload_in_progress` (another reload
--- is running), `stopping` (the supervisor is stopping) and `not_running` (not started, or stopped).
--- Raises `hecate.core.ArgumentError` for a malformed argument.
---@async
---@param options? { grace_timeout?: number, ready_timeout?: number }  `grace_timeout`: seconds the old workers drain, default 30; `ready_timeout`: seconds a replacement may take to become ready, default 30
function Supervisor:reload(options)
  if options ~= nil and type(options) ~= "table" then
    error(core.ArgumentError("hecate.kernel.supervisor.reload: options must be a table { grace_timeout?, ready_timeout? }, got " .. type(options)), 2)
  end
  options = options or {}
  if options.grace_timeout ~= nil and not is_duration(options.grace_timeout) then
    error(core.ArgumentError("hecate.kernel.supervisor.reload: grace_timeout must be a non-negative finite number of seconds, got " .. tostring(options.grace_timeout)), 2)
  end
  if options.ready_timeout ~= nil and not is_duration(options.ready_timeout) then
    error(core.ArgumentError("hecate.kernel.supervisor.reload: ready_timeout must be a non-negative finite number of seconds, got " .. tostring(options.ready_timeout)), 2)
  end
  local function refuse(reason, text)
    error(errors.SupervisorError("hecate.kernel.supervisor.reload: cannot reload: " .. text, { context = { reason = reason } }), 3)
  end
  if self._state ~= "running" or #self._slots == 0 then refuse("not_running", "the supervisor is not running") end
  if self._stopping or self._requests:length() > 0 then refuse("stopping", "the supervisor is stopping") end
  if self._reloading then refuse("reload_in_progress", "another reload is running") end
  self._reloading = true
  local reload_end = reactor.Channel(0)
  self._reload_end = reload_end
  local grace, ready_timeout = options.grace_timeout or 30, options.ready_timeout or 30
  local ok, err = pcall(function()
    for _, slot in ipairs(self._slots) do
      if self._stopping then
        error(reload_failure(self, slot, "stopping", "the supervisor is stopping"), 0)
      end
      replace(self, slot, grace, ready_timeout)
    end
  end)
  self._reloading, self._reload_end = false, nil
  reload_end:close()
  if not ok then error(err, 0) end
end

--- Kills every worker that is still running, at once, and stops the supervisor (no restart): the forced stop of a
--- second signal. Never suspends; `run` returns once the workers have exited. Does nothing when not running.
function Supervisor:force()
  if self._state ~= "running" then return end
  self._stopping = true
  request_stop(self, 0)
  for _, slot in ipairs(self._slots) do
    for _, gen in ipairs(live(slot)) do
      if gen.process:is_running() then
        note(self, "warning", "forced stop: killing a worker", { code = "worker_killed", worker = slot.index, pid = gen.process.pid })
        pcall(gen.process.kill, gen.process, "sigkill")
      end
    end
  end
end

--- The address the application listens on: the primary's socket for `round_robin`, the endpoint for `reuseport`;
--- nil before `run` has bound it. With an ephemeral port (`port = 0`) it stays nil until the socket is bound, so a
--- caller never sees port 0, which it could not connect to.
---@return hecate.reactor.SocketAddress|hecate.kernel.Endpoint|nil
function Supervisor:local_address()
  if self._state == "new" then return nil end
  if self._address ~= nil then return self._address end
  local endpoint = self._options.endpoint
  if endpoint.port == 0 then return nil end
  return endpoint
end

--- Number of workers that reported `ready` and still run.
---@return integer
function Supervisor:ready_count() return self._ready end

--- Number of worker processes started so far, restarts included.
---@return integer
function Supervisor:started_count() return self._started end

core.finalise(Supervisor)
supervisor.Supervisor = Supervisor

-- The worker ---------------------------------------------------------------------------------------------------------

--- The worker side: the control message pipe to the primary and the listener of the strategy.
---@class hecate.kernel.WorkerRole
---@field index integer  the worker's number, from 1
---@field strategy string  `round_robin` or `reuseport`
---@field endpoint hecate.kernel.Endpoint  for `round_robin`, the primary's listening address
---@overload fun(peer: hecate.reactor.Peer, environment: table<string, string?>): hecate.kernel.WorkerRole
local WorkerRole = core.class("WorkerRole")

--- Prefer `supervisor.worker_role()`.
---@param peer hecate.reactor.Peer
---@param environment table<string, string?>  the `HECATE_WORKER_*` variables
---@private
function WorkerRole:init(peer, environment)
  local strategy = environment[ENV.strategy]
  if strategy ~= "round_robin" and strategy ~= "reuseport" then
    error(core.ArgumentError(("hecate.kernel.supervisor.worker_role: unknown strategy %q (valid: reuseport, round_robin)"):format(tostring(strategy))), 2)
  end
  local port = math.tointeger(tonumber(environment[ENV.port]))
  if port == nil or port < 0 or port > 65535 then error(core.ArgumentError("hecate.kernel.supervisor.worker_role: malformed port, an integer from 0 to 65535 expected, got " .. tostring(environment[ENV.port])), 2) end
  self._peer = peer
  self.index = math.tointeger(tonumber(environment[ENV.index])) or 0
  self.strategy = strategy --[[@as string]]
  local host = environment[ENV.host] or "127.0.0.1"
  if not is_host(host) then
    error(core.ArgumentError(("hecate.kernel.supervisor.worker_role: malformed %s, an IP literal or a host name without spaces expected, got %q")
      :format(ENV.host, tostring(host))), 2)
  end
  local backlog
  local raw_backlog = environment[ENV.backlog]
  if raw_backlog ~= nil then
    backlog = math.tointeger(tonumber(raw_backlog))
    if backlog == nil then
      error(core.ArgumentError(("hecate.kernel.supervisor.worker_role: malformed %s, an integer expected (clamped to 1..65535), got %q")
        :format(ENV.backlog, tostring(raw_backlog))), 2)
    end
    backlog = math.max(1, math.min(65535, backlog))
  end
  self.endpoint = { host = host, port = port, backlog = backlog }
  local address = { ip = self.endpoint.host, port = port, family = self.endpoint.host:find(":", 1, true) and "inet6" or "inet" }
  -- The hand-over queue is bounded like the listen backlog it stands for (default 128).
  self._hand_over = listening.HandOverListener(address, self.endpoint.backlog)
end

--- The listener the server accepts from: the hand-over listener (`round_robin`) or a socket bound with `SO_REUSEPORT`.
---
--- Raises `hecate.reactor.TransportError` when a `reuseport` socket cannot be bound.
---@async
---@return hecate.kernel.HandOverListener|hecate.net.TcpListener
function WorkerRole:listener()
  if self._listener == nil then
    local strategy = self.strategy == "reuseport" and listening.ReuseportStrategy() or listening.RoundRobinStrategy()
    self._listener = strategy:worker_listener({ endpoint = self.endpoint, hand_over = self._hand_over })
  end
  return self._listener
end

--- Reads the messages of the primary until `stop` or the end of the message pipe, then calls `on_stop` with the grace
--- period (the one of `stop`, else `default_grace`). Connections handed over go to the hand-over listener; unknown
--- messages are ignored (a newer primary may send what this worker does not know).
---@async
---@param on_stop async fun(grace: number)
---@param default_grace number
function WorkerRole:control(on_stop, default_grace)
  local grace = default_grace
  local peer = self._peer
  while true do
    local ok, message, stream = pcall(peer.receive, peer)
    if not ok then
      if core.is_instance_of(message, core.CancellationError) then error(message, 0) end
      break
    end
    if message == nil then break end
    if message == "connection" and stream ~= nil then
      local queued, reason = self._hand_over:push(stream)
      if not queued and reason == "full" then
        -- The primary cannot be told (the message pipe is one way here); the client sees its connection closed.
        log.default():warning("kernel.WorkerRole: the hand-over queue is full; connection closed",
          { code = "hand_over_queue_full", worker = self.index, capacity = self._hand_over:capacity() })
      end
    else
      if stream ~= nil then stream:close() end
      local seconds = message:match("^stop (.+)$")
      if seconds ~= nil then
        local value = tonumber(seconds)
        if is_duration(value) then grace = value --[[@as number]] end
        break
      end
    end
  end
  self._hand_over:close()
  on_stop(grace)
end

--- Serves `server` as a worker: binds the listener, tells the primary it is ready, serves until `stop` or the end of
--- the message pipe, which shut the server down gracefully. Returns when the server has stopped; closes the message
--- pipe.
---
--- Raises what `hecate.http.Server:serve` raises.
---@async
---@param server hecate.http.Server
---@param default_grace? number  grace period when the primary disappears without `stop` (default 30)
function WorkerRole:serve(server, default_grace)
  local listener = self:listener()
  local ok, err = pcall(reactor.scope, function(scope)
    local control = scope:fork(self.control, self, function(grace)
      -- The connections handed over before the `stop` message are served first (a rolling reload loses none).
      if listener.drain ~= nil then (listener --[[@as hecate.kernel.HandOverListener]]):drain(math.min(grace, 1)) end
      server:shutdown(grace)
    end, default_grace or 30)
    self._peer:send("ready")
    server:serve(listener --[[@as hecate.net.TcpListener]])
    control:cancel()
  end)
  self._peer:close()
  if not ok then error(err, 0) end
end

core.finalise(WorkerRole)
supervisor.WorkerRole = WorkerRole

--- The worker role of this process, or nil when it was not started by a `Supervisor` (no message pipe to a primary, or
--- no `HECATE_WORKER_STRATEGY`). Does not suspend.
---@return hecate.kernel.WorkerRole?
function supervisor.worker_role()
  if os.getenv(ENV.strategy) == nil then return nil end
  local peer = reactor.ipc.parent()
  if peer == nil then return nil end
  local environment = {}
  for _, name in pairs(ENV) do environment[name] = os.getenv(name) end
  return WorkerRole(peer, environment)
end

return supervisor
