-- Listening strategies of multi-process serving (ADR 0023, "A listening strategy is the only platform-dependent
-- part"): where a worker accepts connections from. `reuseport`: each worker binds the port with `SO_REUSEPORT` and the
-- operating system balances (Linux). `round_robin`: the primary accepts and hands each connection to the next worker
-- (every platform, and the fallback). Everything above the listener a worker gets (server, router, actions) is the
-- same for both. The supervisor that starts the workers builds on this module.
global <const> require, type, error, pcall, tostring, math, table

local core = require("hecate.core")
local reactor = require("hecate.reactor")
local net = require("hecate.net")
local http = require("hecate.http")

---@class hecate.kernel.listening
local listening = {}

--- Where the application listens.
---@class hecate.kernel.Endpoint
---@field host string  a numeric address (as for `hecate.http.ServerOptions`)
---@field port integer  0 to 65535; 0 (a free port) only with `round_robin`
---@field backlog? integer  pending connections the system queues (default 128)

--- A worker as the primary sees it, for `round_robin`.
---@class hecate.kernel.HandOverTarget
---@field hand_over async fun(self: hecate.kernel.HandOverTarget, stream: hecate.reactor.TcpStream)  passes a connection to the worker (for example `Peer:send("connection", stream)`); raises when the worker cannot take it

--- What a worker gives its strategy to build its listener.
---@class hecate.kernel.WorkerContext
---@field endpoint hecate.kernel.Endpoint
---@field hand_over hecate.kernel.HandOverListener  fed with the connections the primary hands over (`round_robin`)

---@param endpoint any
---@param call string
---@return hecate.kernel.Endpoint
local function check_endpoint(endpoint, call)
  if type(endpoint) ~= "table" then error(core.ArgumentError(call .. ": endpoint must be a table { host, port, backlog? }"), 3) end
  if type(endpoint.host) ~= "string" or endpoint.host == "" then
    error(core.ArgumentError(call .. ": endpoint.host must be a non-empty string"), 3)
  end
  local port = endpoint.port
  if math.type(port) ~= "integer" or port < 0 or port > 65535 then
    error(core.ArgumentError(call .. ": endpoint.port must be an integer from 0 to 65535"), 3)
  end
  local backlog = endpoint.backlog
  if backlog ~= nil and (math.type(backlog) ~= "integer" or backlog < 1) then
    error(core.ArgumentError(call .. ": endpoint.backlog must be a positive integer"), 3)
  end
  return endpoint
end

---@param operation string
local function raise_closed(operation)
  error(reactor.TransportError({
    message = "kernel.HandOverListener." .. operation .. ": EBADF: the listener is closed",
    context = { operation = operation, errno = "EBADF" },
  }), 0)
end

--- The listener of a `round_robin` worker: `accept` returns the connections the primary handed over, pushed by the
--- worker's control loop. It has the interface `hecate.http.Server:serve` expects of a listener.
---@class hecate.kernel.HandOverListener
---@overload fun(address?: hecate.reactor.SocketAddress, capacity?: integer): hecate.kernel.HandOverListener
local HandOverListener = core.class("HandOverListener")

--- Creates an empty, open listener.
---
--- Raises `hecate.core.ArgumentError` when `capacity` is not a positive integer.
---@param address? hecate.reactor.SocketAddress  what `local_address` reports (the primary's listening address)
---@param capacity? integer  the most connections queued at once, the role of a listen backlog (default `http.Server.DEFAULTS.backlog`)
function HandOverListener:init(address, capacity)
  if capacity == nil then capacity = http.Server.DEFAULTS.backlog end
  if math.type(capacity) ~= "integer" or capacity < 1 then
    error(core.ArgumentError("hecate.kernel.listening.init: capacity must be a positive integer, got " .. tostring(capacity)), 3)
  end
  self._address = address
  self._capacity = capacity
  -- Pushing never suspends: the control loop that pushes must stay free to receive `stop`. A connection that does not
  -- fit is closed instead, as a kernel drops a connection when the listen backlog is full.
  self._pending = reactor.Channel(capacity)
end

--- The most connections queued at once.
---@return integer
function HandOverListener:capacity() return self._capacity end

--- Queues a connection handed over by the primary. Never suspends. Returns false and a reason, after closing the
--- stream, when the listener is closed (`"closed"`) or already holds `capacity` connections (`"full"`).
---@param stream hecate.reactor.TcpStream|hecate.net.TcpStream
---@return boolean queued
---@return ("closed"|"full")? reason
function HandOverListener:push(stream)
  local pending = self._pending
  if pending:is_closed() then
    stream:close()
    return false, "closed"
  end
  if pending:length() >= self._capacity then
    stream:close()
    return false, "full"
  end
  pending:send(stream)
  return true
end

--- Returns the next connection, suspending while there is none.
---
--- Raises `hecate.reactor.TransportError` (`EBADF`, `context.operation` `accept`) when the listener is closed.
---@async
---@return hecate.net.TcpStream
function HandOverListener:accept()
  if self._pending:is_closed() then raise_closed("accept") end
  local ok, stream = pcall(self._pending.receive, self._pending)
  if not ok then
    if core.is_instance_of(stream, core.CancellationError) then error(stream, 0) end
    raise_closed("accept")
  end
  if core.is_instance_of(stream, net.TcpStream) then return stream end
  return net.TcpStream(stream)
end

--- Stops accepting: a waiting `accept` fails, the queued connections are closed. Idempotent, never suspends.
function HandOverListener:close()
  local pending = self._pending
  if pending:is_closed() then return end
  pending:close()
  while pending:length() > 0 do
    local ok, stream = pcall(pending.receive, pending) -- a closed channel yields its buffered values without suspending
    if ok then stream:close() end
  end
end

---@return boolean
function HandOverListener:is_closed() return self._pending:is_closed() end

--- The address given at creation, or nil.
---@return hecate.reactor.SocketAddress?
function HandOverListener:local_address() return self._address end

core.finalise(HandOverListener)
listening.HandOverListener = HandOverListener

--- The workers that take connections, in rotation (`round_robin`). The supervisor adds a worker once it is ready
--- and removes it when it drains or exits.
---@class hecate.kernel.WorkerRing
---@overload fun(): hecate.kernel.WorkerRing
local WorkerRing = core.class("WorkerRing")

--- Creates an empty, open ring.
function WorkerRing:init()
  self._members = {}
  self._index = 0
  self._closed = false
  self._changed = reactor.Channel(1) -- holds one wake-up for the waiting `next`
end

---@param self hecate.kernel.WorkerRing
local function signal(self)
  local changed = self._changed
  if not changed:is_closed() and changed:length() == 0 then changed:send(true) end -- room: does not suspend
end

--- Adds a worker at the end of the rotation (nothing if it is a member already). Never suspends.
---@param worker hecate.kernel.HandOverTarget
function WorkerRing:add(worker)
  local members = self._members
  for i = 1, #members do if members[i] == worker then return end end
  members[#members + 1] = worker
  signal(self)
end

--- Removes a worker from the rotation (nothing if it is not a member). Never suspends.
---@param worker hecate.kernel.HandOverTarget
function WorkerRing:remove(worker)
  local members = self._members
  for i = 1, #members do
    if members[i] == worker then
      table.remove(members, i)
      if self._index >= i then self._index = self._index - 1 end
      return
    end
  end
end

--- Number of workers in the rotation.
---@return integer
function WorkerRing:size() return #self._members end

--- The next worker in the rotation, suspending while there is none; nil once the ring is closed. One caller at a time
--- (the hand-over loop of the primary).
---@async
---@return hecate.kernel.HandOverTarget?
function WorkerRing:next()
  while not self._closed and #self._members == 0 do
    local ok, err = pcall(self._changed.receive, self._changed)
    if not ok and core.is_instance_of(err, core.CancellationError) then error(err, 0) end
  end
  if self._closed then return nil end
  local members = self._members
  self._index = self._index % #members + 1
  return members[self._index]
end

--- Closes the ring: `next` returns nil from now on, also in a waiting caller. Never suspends.
function WorkerRing:close()
  self._closed = true
  self._changed:close()
end

core.finalise(WorkerRing)
listening.WorkerRing = WorkerRing

--- `round_robin`: the primary accepts and hands every connection to the next worker. Supported everywhere.
---@class hecate.kernel.RoundRobinStrategy
---@field name "round_robin"
---@overload fun(options?: { logger?: hecate.log.Logger }): hecate.kernel.RoundRobinStrategy
local RoundRobin = core.class("RoundRobinStrategy")
RoundRobin.name = "round_robin"

---@param options? { logger?: hecate.log.Logger }
function RoundRobin:init(options)
  self._logger = options and options.logger or nil
  self._listener = nil
end

--- Always true: handing over connections works on every platform.
---@return boolean supported
---@return string? reason
function RoundRobin:supported() return true, nil end

--- Binds the listening socket in the primary, once (suspends for the bind). Returns the bound address (with
--- `port = 0`, the port the system chose).
---
--- Raises `hecate.core.ArgumentError` for a malformed endpoint or a second call, `hecate.reactor.TransportError`
--- when the address cannot be bound.
---@async
---@param endpoint hecate.kernel.Endpoint
---@return hecate.reactor.SocketAddress address
function RoundRobin:prepare(endpoint)
  check_endpoint(endpoint, "hecate.kernel.listening.prepare")
  if self._listener ~= nil then error(core.ArgumentError("hecate.kernel.listening.prepare: already prepared"), 2) end
  self._listener = net.listen(endpoint.host, endpoint.port, { backlog = endpoint.backlog })
  return self._listener:local_address()
end

--- The listener of a worker: the hand-over listener of its context, fed by its control loop. Does not suspend.
---@param context hecate.kernel.WorkerContext
---@return hecate.kernel.HandOverListener
function RoundRobin:worker_listener(context)
  if type(context) ~= "table" or not core.is_instance_of(context.hand_over, HandOverListener) then
    error(core.ArgumentError("hecate.kernel.listening.worker_listener: context.hand_over must be a HandOverListener, got " .. type(type(context) == "table" and context.hand_over or nil)), 2)
  end
  return context.hand_over
end

--- Hands one connection to a worker; tries each worker of the ring at most once, then closes the connection.
---@async
---@param self hecate.kernel.RoundRobinStrategy
---@param workers hecate.kernel.WorkerRing
---@param stream hecate.net.TcpStream
---@return boolean continue  false once the ring is closed
local function deliver(self, workers, stream)
  local inner = stream:transport() -- the reactor stream is what `reactor.ipc` passes (ADR 0027)
  local attempts = math.max(1, workers:size())
  for _ = 1, attempts do
    local worker = workers:next()
    if worker == nil then
      stream:close()
      return false
    end
    local ok, err = pcall(worker.hand_over, worker, inner)
    if ok then return true end
    if core.is_instance_of(err, core.CancellationError) then
      stream:close()
      error(err, 0)
    end
    if self._logger ~= nil then
      self._logger:warning("kernel.listening: a worker could not take a connection", { code = "hand_over_failed", reason = tostring(err) })
    end
  end
  stream:close()
  return true
end

--- The hand-over loop, in the primary: accepts each connection and hands it over to the next worker of `workers`. Returns
--- when `close` is called or the ring is closed. An accept failure (descriptor exhaustion) backs off from 50 ms to
--- 1 s, as `hecate.http.Server` does, and is logged once per burst.
---
--- Raises `hecate.core.ArgumentError` when `prepare` was not called.
---@async
---@param workers hecate.kernel.WorkerRing
function RoundRobin:run(workers)
  local listener = self._listener
  if listener == nil then error(core.ArgumentError("hecate.kernel.listening.run: call prepare first"), 2) end
  local failures = 0
  while true do
    local ok, stream = pcall(listener.accept, listener)
    if not ok then
      if core.is_instance_of(stream, core.CancellationError) then error(stream, 0) end
      if listener:is_closed() then return end
      failures = failures + 1
      if failures == 1 and self._logger ~= nil then
        self._logger:warning("kernel.listening: accept failed", { code = "accept_failed", reason = tostring(stream) })
      end
      reactor.sleep(math.min(0.05 * 2 ^ (failures - 1), 1))
    else
      failures = 0
      if not deliver(self, workers, stream) then return end
    end
  end
end

--- Closes the primary's listening socket: `run` returns. Idempotent, never suspends.
function RoundRobin:close()
  if self._listener ~= nil then self._listener:close() end
end

--- The primary's listening address, or nil before `prepare`.
---@return hecate.reactor.SocketAddress?
function RoundRobin:local_address()
  return self._listener and self._listener:local_address() or nil
end

core.finalise(RoundRobin)
listening.RoundRobinStrategy = RoundRobin

--- `reuseport`: each worker binds the port with `SO_REUSEPORT` and the operating system balances the connections;
--- the primary is not in the data path. Supported on Linux with a luv that has TCP `reuseport` (OQ-43).
---@class hecate.kernel.ReuseportStrategy
---@field name "reuseport"
---@overload fun(options?: { system?: string, reuseport?: boolean }): hecate.kernel.ReuseportStrategy
local Reuseport = core.class("ReuseportStrategy")
Reuseport.name = "reuseport"

--- `options.system` and `options.reuseport` replace `reactor.system_name()` and `reactor.supports_reuseport()`
--- (tests).
---@param options? { system?: string, reuseport?: boolean }
function Reuseport:init(options)
  options = options or {}
  self._system = options.system
  self._reuseport = options.reuseport
  self._endpoint = nil
end

--- True on Linux when TCP `SO_REUSEPORT` is available; otherwise false and the reason. macOS accepts the flag and
--- gives every connection to one socket (ADR 0023), so it is not supported there. Does not suspend.
---@return boolean supported
---@return string? reason
function Reuseport:supported()
  local system = self._system or reactor.system_name()
  if system ~= "Linux" then
    return false, ("reuseport balances connections only on Linux (this system is %s)"):format(system)
  end
  local available = self._reuseport
  if available == nil then available = reactor.supports_reuseport() end
  if not available then return false, "TCP SO_REUSEPORT is not available in this luv (OQ-43)" end
  return true, nil
end

--- Records the endpoint; nothing is bound in the primary. Does not suspend.
---
--- Raises `hecate.core.ArgumentError` for a malformed endpoint or port 0 (each worker would get another port).
---@param endpoint hecate.kernel.Endpoint
---@return hecate.reactor.SocketAddress? address  nil: the address is known once a worker has bound it
function Reuseport:prepare(endpoint)
  check_endpoint(endpoint, "hecate.kernel.listening.prepare")
  if endpoint.port == 0 then
    error(core.ArgumentError("hecate.kernel.listening.prepare: port 0 would give each worker its own port; use a fixed port or round_robin"), 2)
  end
  self._endpoint = endpoint
  return nil
end

--- The listener of a worker: its own socket on the endpoint, bound with `reuseport = true`.
---
--- Raises `hecate.reactor.TransportError` when the address cannot be bound.
---@async
---@param context hecate.kernel.WorkerContext
---@return hecate.net.TcpListener
function Reuseport:worker_listener(context)
  local endpoint = check_endpoint(type(context) == "table" and context.endpoint or nil, "hecate.kernel.listening.worker_listener")
  return net.listen(endpoint.host, endpoint.port, { backlog = endpoint.backlog, reuseport = true })
end

--- No hand-over loop: returns at once.
---@async
---@param workers hecate.kernel.WorkerRing
function Reuseport:run(workers) local _ = workers end

--- Nothing to close in the primary.
function Reuseport:close() end

--- Nil: the primary binds nothing.
---@return nil
function Reuseport:local_address() return nil end

core.finalise(Reuseport)
listening.ReuseportStrategy = Reuseport

---@alias hecate.kernel.ListeningStrategy hecate.kernel.RoundRobinStrategy|hecate.kernel.ReuseportStrategy

--- Options of `listening.select`.
---@class hecate.kernel.SelectOptions
---@field system? string  replaces `reactor.system_name()` (tests)
---@field reuseport? boolean  replaces `reactor.supports_reuseport()` (tests)
---@field logger? hecate.log.Logger  given to `round_robin`

--- Chooses the listening strategy for `server.strategy` (ADR 0023, Decision 3): `"auto"` is `reuseport` when
--- it is supported (Linux with TCP `SO_REUSEPORT`) and `round_robin` otherwise; a strategy named but not supported
--- falls back to `round_robin`, and the second result gives the reason (the caller logs it as a warning). `auto`
--- falling back is the documented default, not a warning. Does not suspend.
---
--- Raises `hecate.core.ArgumentError` for an unknown name.
---@param name "auto"|"reuseport"|"round_robin"
---@param options? hecate.kernel.SelectOptions
---@return hecate.kernel.ListeningStrategy strategy  a new strategy
---@return string? fallback_reason  set when the named strategy is not supported
function listening.select(name, options)
  options = options or {}
  local round_robin = RoundRobin({ logger = options.logger })
  if name == "round_robin" then return round_robin, nil end
  if name ~= "auto" and name ~= "reuseport" then
    error(core.ArgumentError(("hecate.kernel.listening.select: unknown strategy %q (valid: auto, reuseport, round_robin)"):format(tostring(name))), 2)
  end
  local reuseport = Reuseport({ system = options.system, reuseport = options.reuseport })
  local supported, reason = reuseport:supported()
  if supported then return reuseport, nil end
  if name == "auto" then return round_robin, nil end
  return round_robin, ("strategy reuseport is not supported, using round_robin: %s"):format(reason)
end

return listening
