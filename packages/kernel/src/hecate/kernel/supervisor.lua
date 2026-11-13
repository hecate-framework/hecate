-- Multi-process serving, the policy half (ADR 0023, "Mechanism in `reactor`, policy in `kernel`"): the supervisor in
-- the primary starts the workers, adds each to the rotation once it is ready, restarts a worker that exits with an
-- exponential backoff and a crash-loop limit, and stops them gracefully; the worker side reads the control messages of
-- the primary, feeds the connections it hands over to the server, and drains on `stop` or when the message pipe
-- closes (the primary died). The control messages are the same on every platform (Decision 5): `ready`,
-- `counters <requests> <connections>` and `received` (worker to primary), `stop <seconds>` and `connection` with a
-- stream (primary to worker). The primary keeps its copy of each stream it hands over, in a FIFO per worker process,
-- until the worker answers `received` (sent once it has taken the stream out of the frame, whether it queued or refused
-- it); it closes what is still held when the worker's message pipe ends or the worker exits or is killed. A stream in
-- flight in a message pipe is held by no process, and macOS discards it when another Unix socket closes (OQ-118). The
-- number of streams held for a worker is bounded by the connections in flight to it (written, not yet acknowledged). `counters` carries two non-negative integers in decimal, `requests` being `-` when the worker cannot count
-- them (`http.Server` has no request counter yet); a worker sends it at most once per second, only when a value
-- changed, and once more when it has stopped serving; the primary keeps the latest values of each worker
-- (`Supervisor:counters`), ignores a malformed message and a `received` with nothing held, and logs `hand_over_unaccounted` when a worker exits having
-- accepted fewer connections than were handed over to it.
-- A worker that does not say `ready` within `ready_timeout` seconds of its start is killed and counted as a crash. The rolling reload replaces workers
-- by restart (a fresh process from the same command, ready before the old one is stopped), so it needs no message of its
-- own: `reload` stays reserved in the protocol, unused, and a worker never sees it.
global <const> require, type, error, pcall, tostring, tonumber, math, table, ipairs, pairs, os

local core = require("hecate.core")
local reactor = require("hecate.reactor")
local log = require("hecate.log")
local http = require("hecate.http")
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

--- Tells whether a text looks like an IP literal (IPv4 or IPv6, hexadecimal digits, colons and dots; an IPv6 literal may
--- end with a zone id, `%` then letters, digits, `.`, `-` or `_`, as `fe80::1%eth0`, RFC 4007 section 11) or like a
--- host name (letters, digits, hyphens and dots, at most 253 characters): no space, no other character. Does not
--- resolve anything.
---@param host any
---@return boolean
local function is_host(host)
  if type(host) ~= "string" or host == "" or #host > 253 then return false end
  if host:find(":", 1, true) then
    local address, zone = host:match("^([%x:%.]+)%%([%w%.%-_]+)$")
    if address ~= nil then return zone ~= nil end
    return host:match("^[%x:%.]+$") ~= nil
  end
  return host:match("^[%w][%w%.%-]*$") ~= nil
end

--- Parses `counters <requests> <connections>` (decimal integers, `-` for unknown requests); nil when malformed.
---@param message string
---@return { requests: integer?, connections: integer }?
local function parse_counters(message)
  local requests, connections = message:match("^counters (%d+) (%d+)$")
  if requests == nil then
    requests, connections = message:match("^counters (%-) (%d+)$")
  end
  if connections == nil or #connections > 18 or (requests ~= "-" and #requests > 18) then return nil end
  return { requests = requests ~= "-" and math.tointeger(tonumber(requests)) or nil, connections = math.tointeger(tonumber(connections)) }
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
---@field ready_timeout? number  seconds a started worker (first start or restart) may take to send `ready` (default 30); past it the worker is killed, logged `worker_not_ready` at `error` and counted as a crash; a reload has its own `ready_timeout`
---@field on_crash_loop? "stop"|"degrade"  what a crash loop does: `stop` (default) ends `run` with a `SupervisorError`; `degrade` keeps restarting the workers at the maximum backoff (10 s), logs `crash_loop` at `error` once per crash window, and never ends `run` by itself; in `degrade` mode a restart that cannot start the program is logged `worker_start_failed` at `warning`, counted as a crash and retried (the first start of a worker that fails still ends `run` with `start_failed`)

--- The supervisor of the workers, in the primary.
---@class hecate.kernel.Supervisor
---@overload fun(options: hecate.kernel.SupervisorOptions): hecate.kernel.Supervisor
local Supervisor = core.class("Supervisor")

local KNOWN = {
  command = true, count = true, endpoint = true, strategy = true, env = true, logger = true, restart_delay = true,
  crash_limit = true, crash_window = true, on_crash_loop = true, ready_timeout = true,
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
  for _, key in ipairs({ "restart_delay", "crash_window", "ready_timeout" }) do
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
---@field counters? { requests: integer?, connections: integer }  the latest `counters` message
---@field handed integer  connections handed over to it (written to its message pipe)
---@field held hecate.reactor.TcpStream[]  streams written to it that it has not acknowledged with `received` yet, oldest first (`held_first` is the index of the oldest)
---@field held_first integer
---@field held_last integer
---@field held_count integer  the streams held (written, not acknowledged): the ring skips the worker once it reaches `capacity`
---@field capacity integer  the hand-over queue of the worker (its backlog): the most connections held for it at once
---@field pump hecate.reactor.Future?  while a reload retires the old worker, the computation that reads the messages of this replacement; `supervise` cancels it and takes over
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
  -- The worker queues at most its backlog of connections (`HandOverListener`); the primary holds at most as many
  -- unacknowledged ones for it, so that a worker that stops reading its message pipe is skipped by the ring instead of
  -- stalling the hand-over loop of every worker on a full pipe (back-pressure from the `received` acknowledgements).
  local backlog = self._options.endpoint.backlog
  local capacity = math.max(1, math.min(65535, math.tointeger(backlog) or http.Server.DEFAULTS.backlog))
  local gen = {
    process = process, peer = peer, ready = false, planned = false, finished = false, done = reactor.Channel(0), handed = 0,
    held = {}, held_first = 1, held_last = 0, held_count = 0, capacity = capacity,
  }
  -- The stream stays open in the primary until the worker answers `received` (or the worker is gone): a stream in flight
  -- in a message pipe is held by no process, and macOS discards it when another Unix socket closes (OQ-118). It is
  -- recorded before the write so that a fast `received` always finds it; a failed write takes it back.
  gen.target = {
    hand_over = function(_, stream)
      local index = gen.held_last + 1
      gen.held_last, gen.held[index] = index, stream
      gen.held_count = gen.held_count + 1
      local sent, err = pcall(peer.send, peer, "connection", stream, { keep_open = true })
      if not sent then
        if gen.held[index] == stream then -- the position stays (later entries are ahead of it)
          gen.held[index] = false
          gen.held_count = gen.held_count - 1
        end
        error(err, 0)
      end
      gen.handed = gen.handed + 1
    end,
    saturated = function() return gen.held_count >= gen.capacity end,
  }
  return gen
end

--- Closes the oldest stream held for `gen` (the worker acknowledged it); does nothing when none is held (a stray
--- `received` is ignored). A position emptied by a failed write is skipped. Never suspends.
---@param gen hecate.kernel.WorkerGeneration
local function release_oldest(gen)
  while gen.held_first <= gen.held_last do
    local index = gen.held_first
    local stream = gen.held[index]
    gen.held[index], gen.held_first = nil, index + 1
    if stream then
      gen.held_count = gen.held_count - 1
      pcall(stream.close, stream)
      return
    end
  end
end

--- Closes every stream still held for `gen`: its message pipe ended, or it exited or was killed. Idempotent. Never suspends.
---@param gen hecate.kernel.WorkerGeneration
local function release_held(gen)
  while gen.held_first <= gen.held_last do release_oldest(gen) end
end

--- Handles one message of a worker (`ready`, `counters`, `received`); anything else is ignored. The primary expects no
--- stream from a worker: one that arrives is closed, not leaked (a descriptor each).
---@param self hecate.kernel.Supervisor
---@param gen hecate.kernel.WorkerGeneration
---@param message string
---@param stream hecate.reactor.TcpStream?
local function on_message(self, gen, message, stream)
  if stream ~= nil then pcall(stream.close, stream) end
  if message == "ready" and not gen.ready and not gen.planned then
    gen.ready = true
    self._ready = self._ready + 1
    if not self._stopping then self._ring:add(gen.target) end
  elseif message == "received" then
    release_oldest(gen)
  elseif message:sub(1, 9) == "counters " then
    gen.counters = parse_counters(message) or gen.counters -- a malformed message changes nothing
  end
end

--- Records a crash (an exit, or a restart that could not start) and returns the delay before the next start, or nil
--- when the crash-loop limit is reached in `stop` mode (the supervisor then stops: `_failure` is set). In `degrade` mode
--- the limit gives the maximum backoff and logs `crash_loop` once per crash window.
---@param self hecate.kernel.Supervisor
---@return number?
local function after_crash(self)
  local delay = crash_delay(self)
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
  end
  return delay
end

--- Sleeps `delay` seconds before a restart of `slot`; false when the sleep was cancelled by a stop.
---@async
---@param self hecate.kernel.Supervisor
---@param slot hecate.kernel.WorkerSlot
---@param delay number
---@return boolean
local function wait_restart(self, slot, delay)
  slot.waiting = true
  local slept, err = pcall(reactor.sleep, delay)
  slot.waiting = false
  if not slept then
    if self._stopping then return false end
    error(err, 0)
  end
  return true
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
  local restarting = false -- a worker of this slot has run: a start is a restart
  while true do
    while gen == nil do
      if self._stopping then return end
      local spawned, reason = start_worker(self, slot)
      if spawned == nil and restarting and self._options.on_crash_loop == "degrade" then
        -- In degraded mode a restart that cannot start (descriptors or memory exhausted for a while) is a crash like an
        -- exit: counted, retried with the backoff. The first start of a slot is not: a program that cannot start at
        -- all is a boot error.
        note(self, "warning", "a worker could not be restarted; retrying", {
          code = "worker_start_failed", worker = slot.index, reason = tostring(reason),
        })
        local delay = after_crash(self)
        if delay == nil or not wait_restart(self, slot, delay) then return end
      elseif spawned == nil then
        self._failure = self._failure or errors.SupervisorError(("hecate.kernel.supervisor.run: cannot start a worker: %s"):format(tostring(reason)),
          { context = { reason = "start_failed" } })
        request_stop(self, 0)
        return
      end
      gen = spawned
    end
    ---@cast gen hecate.kernel.WorkerGeneration
    restarting = true
    slot.gen = gen
    local peer = gen.peer
    -- A worker that does not say `ready` in time is killed; the loop below then sees its message pipe end and counts a
    -- crash. The watchdog ends as soon as `ready` arrives: a reload that retires the worker later clears `gen.ready`,
    -- and the worker then drains under the grace period of the reload, never under this timeout.
    reactor.scope(function(scope)
      local watchdog
      if not gen.ready then
        local timeout = self._options.ready_timeout or 30
        watchdog = scope:fork(function()
          reactor.sleep(timeout)
          if not gen.ready and not gen.planned and not gen.finished and not self._stopping and gen.process:is_running() then
            note(self, "error", "a worker was not ready in time; killing it", {
              code = "worker_not_ready", worker = slot.index, pid = gen.process.pid, ready_timeout = timeout,
            })
            pcall(gen.process.kill, gen.process, "sigkill")
          end
        end)
      end
      while true do
        local ok, message, stream = pcall(peer.receive, peer)
        if not ok or message == nil then break end
        on_message(self, gen, message, stream)
        if watchdog ~= nil and gen.ready then
          watchdog:cancel()
          watchdog = nil
        end
      end
      if watchdog ~= nil then watchdog:cancel() end
    end)
    self._ring:remove(gen.target)
    release_held(gen) -- the message pipe ended: whatever the worker did not acknowledge is lost for it, close our copies
    if gen.ready then self._ready = self._ready - 1 end
    -- A worker sends its final counters before it exits: connections handed over that it never accepted were lost in
    -- its message pipe or its queue (a worker that reports no count is not judged).
    local accepted = gen.counters and gen.counters.connections
    if accepted ~= nil and accepted < gen.handed then
      note(self, "warning", "connections handed over to a worker were never accepted by it", {
        code = "hand_over_unaccounted", worker = slot.index, pid = gen.process.pid, handed = gen.handed, accepted = accepted,
      })
    end
    peer:close()
    local status = gen.process:wait()
    release_held(gen)
    gen.finished = true
    slot.gen = nil
    gen.done:close()
    local successor = slot.next
    if gen.planned and successor ~= nil then
      -- One reader at a time on the message pipe of the replacement: the reload's pump ends before this loop reads.
      local pump = successor.pump
      if pump ~= nil then
        successor.pump = nil
        pump:cancel()
        pcall(pump.value, pump)
      end
      slot.next, gen = nil, successor
    else
      local exited = gen
      gen = nil
      if self._stopping then return end
      note(self, "warning", "a worker exited; restarting it", {
        code = "worker_exited", worker = slot.index, pid = exited.process.pid, exit_code = status.code, signal = status.signal,
      })
      local delay = after_crash(self)
      if delay == nil or not wait_restart(self, slot, delay) then return end
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
  -- On purpose, `pcall` also absorbs an outer cancellation of this stop (the deadline that bounds the wait is
  -- indistinguishable from it): the workers are then killed below rather than left running.
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
--- when the program cannot be started (in `degrade` mode, only at the first start of a worker: a restart that cannot
--- start is a crash, retried), `already_run`), and what the strategy's `prepare` raises.
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
  release_held(gen)
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
  -- The replacement already receives connections: its messages (`received` above all) are read while the old worker
  -- drains, until `supervise` takes the slot over. A receive that is cancelled loses nothing.
  reactor.scope(function(scope)
    local pump = scope:fork(function()
      while true do
        local received, message, stream = pcall(fresh.peer.receive, fresh.peer)
        if not received then
          if core.is_instance_of(message, core.CancellationError) then error(message, 0) end
          return
        end
        if message == nil then return end
        on_message(self, fresh, message, stream)
      end
    end)
    fresh.pump = pump
    local retired, failure = pcall(retire, self, slot, old, grace)
    if not retired then
      fresh.pump = nil
      pump:cancel()
      error(failure, 0)
    end
    -- `supervise` cancels the pump when it takes the replacement over, which happens as soon as the old worker has exited.
  end)
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
---@param options? { grace_timeout?: number, ready_timeout?: number, on_accepted?: fun() }  `grace_timeout`: seconds the old workers drain, default 30; `ready_timeout`: seconds a replacement may take to become ready, default 30; `on_accepted`: called once, when the reload is accepted (not refused) and before the first worker is replaced
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
  if options.on_accepted ~= nil and type(options.on_accepted) ~= "function" then
    error(core.ArgumentError("hecate.kernel.supervisor.reload: on_accepted must be a function, got " .. type(options.on_accepted)), 2)
  end
  local function refuse(reason, text)
    error(errors.SupervisorError("hecate.kernel.supervisor.reload: cannot reload: " .. text, { context = { reason = reason } }), 3)
  end
  if self._state ~= "running" or #self._slots == 0 then refuse("not_running", "the supervisor is not running") end
  if self._stopping or self._requests:length() > 0 then refuse("stopping", "the supervisor is stopping") end
  if self._reloading then refuse("reload_in_progress", "another reload is running") end
  self._reloading = true
  if options.on_accepted ~= nil then
    local called, failure = pcall(options.on_accepted)
    if not called then
      self._reloading = false
      error(failure, 0)
    end
  end
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

--- The latest counters each worker reported over its message pipe (`counters <requests> <connections>`), by worker
--- index, for the workers in service that reported at least once: `{ worker, pid, connections, requests }`, `requests`
--- being nil when the worker cannot count them. A restarted worker has none until it reports. Never suspends.
---@return { worker: integer, pid: integer, connections: integer, requests: integer? }[]
function Supervisor:counters()
  local list = {}
  for _, slot in ipairs(self._slots) do
    local gen = slot.gen
    if gen ~= nil and gen.counters ~= nil then
      list[#list + 1] = { worker = slot.index, pid = gen.process.pid, connections = gen.counters.connections, requests = gen.counters.requests }
    end
  end
  return list
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
---@overload fun(peer: hecate.reactor.Peer, environment: table<string, string?>, options?: hecate.kernel.WorkerRoleOptions): hecate.kernel.WorkerRole
local WorkerRole = core.class("WorkerRole")

--- Options of `WorkerRole` and `supervisor.worker_role`.
---@class hecate.kernel.WorkerRoleOptions
---@field logger? hecate.log.Logger  receives what the worker side logs (`control_failed`, `hand_over_queue_full`, `hand_over_discarded`); default `log.default()` at the time of each record

--- Prefer `supervisor.worker_role()`.
---
--- Raises `hecate.core.ArgumentError` for a malformed environment or option.
---@param peer hecate.reactor.Peer
---@param environment table<string, string?>  the `HECATE_WORKER_*` variables
---@param options? hecate.kernel.WorkerRoleOptions
---@private
function WorkerRole:init(peer, environment, options)
  if options ~= nil and type(options) ~= "table" then
    error(core.ArgumentError("hecate.kernel.supervisor.worker_role: options must be a table { logger? }, got " .. type(options)), 2)
  end
  local logger = options and options.logger
  if logger ~= nil and (type(logger) ~= "table" or type(logger.log) ~= "function") then
    error(core.ArgumentError("hecate.kernel.supervisor.worker_role: logger must be a hecate.log.Logger, got " .. type(logger)), 2)
  end
  self._logger = logger
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
--- period (the one of `stop`, else `default_grace`). Connections handed over go to the hand-over listener, and each is
--- answered with `received` (written by a computation of its own, so that reading `stop` is never delayed); unknown
--- messages are ignored (a newer primary may send what this worker does not know).
---@async
---@param on_stop async fun(grace: number)
---@param default_grace number
function WorkerRole:control(on_stop, default_grace)
  local grace = default_grace
  local peer = self._peer
  local unacknowledged = 0 -- `connection` frames taken out of the message pipe and not answered with `received` yet
  local wake = reactor.Channel(1)
  local stopped, failure
  local cancelled ---@type any  a cancellation met by the loop: raised once the scope is left
  reactor.scope(function(scope)
    -- `received` is written by this computation, never by the loop below: a write may suspend (full pipe), and the loop
    -- must stay free to read `stop`. It flushes what is left when the loop and `on_stop` are over.
    scope:fork(function()
      while true do
        pcall(wake.receive, wake) -- woken by a connection, or closed at the end
        while unacknowledged > 0 do
          unacknowledged = unacknowledged - 1
          local sent, err = pcall(peer.send, peer, "received")
          if not sent then
            if core.is_instance_of(err, core.CancellationError) then error(err, 0) end
            return -- a failing pipe ends the control loop too
          end
        end
        if wake:is_closed() then return end
      end
    end)
    while true do
      local ok, message, stream = pcall(peer.receive, peer)
      if not ok then
        if core.is_instance_of(message, core.CancellationError) then
          cancelled = message
          wake:close()
          return
        end
        -- A broken or violated message pipe ends the worker like the end of the pipe; the handles still in it are lost.
        (self._logger or log.default()):log("error", "kernel.WorkerRole: the message pipe to the primary failed; the worker stops",
          { code = "control_failed", worker = self.index, reason = tostring(message) })
        break
      end
      if message == nil then break end
      if message == "connection" and stream ~= nil then
        local queued, reason = self._hand_over:push(stream)
        if not queued and reason == "full" then
          -- The client sees its connection closed; the primary is told only that the stream was taken out of the frame.
          (self._logger or log.default()):log("warning", "kernel.WorkerRole: the hand-over queue is full; connection closed",
            { code = "hand_over_queue_full", worker = self.index, capacity = self._hand_over:capacity() })
        end
        -- Whatever became of the stream, the primary may now close its copy (it holds it until this message).
        unacknowledged = unacknowledged + 1
        if wake:length() == 0 then
          ---@diagnostic disable-next-line: await-in-sync  -- room in the buffer: does not suspend
          wake:send(true)
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
    -- Nothing is pushed any more. The connections already queued are not closed here: `on_stop` lets the server take
    -- them (`HandOverListener:drain`) before it shuts down, so a rolling reload resets none; whatever is still queued
    -- afterwards is closed.
    stopped, failure = pcall(on_stop, grace)
    local discarded = self._hand_over:close()
    if discarded > 0 then
      (self._logger or log.default()):log("warning", "kernel.WorkerRole: connections still queued at the stop were closed unserved",
        { code = "hand_over_discarded", worker = self.index, count = discarded })
    end
    wake:close()
  end)
  if cancelled ~= nil then error(cancelled, 0) end
  if not stopped then error(failure, 0) end
end

--- The counters of this worker: requests (nil: `http.Server` keeps no request counter yet) and the connections the
--- hand-over listener accepted (nil with `reuseport`, whose listener keeps no counter).
---@return integer? requests
---@return integer? connections
function WorkerRole:counters()
  if self.strategy ~= "round_robin" then return nil, nil end
  return nil, self._hand_over:accepted()
end

--- Sends `counters <requests> <connections>` to the primary every `interval` seconds (default 1), only when the values
--- changed since the last message; runs until cancelled. It never reads the message pipe, so the control loop stays
--- free to receive `stop`; a failing pipe is ignored (the control loop ends on it).
---@async
---@param interval? number
function WorkerRole:report_counters(interval)
  local last
  while true do
    reactor.sleep(interval or 1)
    local requests, connections = self:counters()
    if connections ~= nil then
      local text = ("counters %s %d"):format(requests ~= nil and ("%d"):format(requests) or "-", connections)
      if text ~= last then
        last = text
        local ok, err = pcall(self._peer.send, self._peer, text)
        if not ok and core.is_instance_of(err, core.CancellationError) then error(err, 0) end
      end
    end
  end
end

--- Serves `server` as a worker: binds the listener, tells the primary it is ready, serves until `stop` or the end of
--- the message pipe, which shut the server down gracefully: the connections already handed over are taken first (at
--- most 1 s), then the server drains for what is left of the grace period. Returns when the server has stopped; closes
--- the message pipe.
---
--- Raises what `hecate.http.Server:serve` raises.
---@async
---@param server hecate.http.Server
---@param default_grace? number  grace period when the primary disappears without `stop` (default 30)
function WorkerRole:serve(server, default_grace)
  local listener = self:listener()
  local ok, err = pcall(reactor.scope, function(scope)
    local control = scope:fork(self.control, self, function(grace)
      -- The connections handed over before the `stop` message are served first (a rolling reload loses none). The
      -- drain counts in the grace period: the server gets what is left of it, so that the worker ends before the
      -- primary kills it (at grace + 1 s).
      local began = reactor.now()
      if listener.drain ~= nil then (listener --[[@as hecate.kernel.HandOverListener]]):drain(math.min(grace, 1)) end
      server:shutdown(math.max(0, grace - (reactor.now() - began)))
    end, default_grace or 30)
    local reporter = scope:fork(self.report_counters, self, 1)
    self._peer:send("ready")
    server:serve(listener --[[@as hecate.net.TcpListener]])
    reporter:cancel()
    control:cancel()
    -- The final counters, so that the primary can tell connections it handed over and this worker never accepted.
    local requests, connections = self:counters()
    if connections ~= nil then
      pcall(self._peer.send, self._peer, ("counters %s %d"):format(requests ~= nil and ("%d"):format(requests) or "-", connections))
    end
  end)
  self._peer:close()
  if not ok then error(err, 0) end
end

core.finalise(WorkerRole)
supervisor.WorkerRole = WorkerRole

--- The worker role of this process, or nil when it was not started by a `Supervisor` (no message pipe to a primary, or
--- no `HECATE_WORKER_STRATEGY`). Does not suspend.
---
--- Raises `hecate.core.ArgumentError` for a malformed worker environment or option.
---@param options? hecate.kernel.WorkerRoleOptions  `logger`: where the worker side logs (`Application` gives its own)
---@return hecate.kernel.WorkerRole?
function supervisor.worker_role(options)
  if os.getenv(ENV.strategy) == nil then return nil end
  local peer = reactor.ipc.parent()
  if peer == nil then return nil end
  local environment = {}
  for _, name in pairs(ENV) do environment[name] = os.getenv(name) end
  return WorkerRole(peer, environment, options)
end

return supervisor
