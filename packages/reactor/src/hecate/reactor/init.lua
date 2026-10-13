-- hecate.reactor: the reactor over libuv (luv): scheduler, futures, structured concurrency
-- (concurrency.md; ADR 0002, ADR 0003). Step 1 of the roadmap item: loop, Future, fork,
-- join, select, sleep, scope, deadline, cancellation and virtual clock.
global <const> require

local core = require("hecate.core")
local Reactor = require("hecate.reactor.reactor")
local primitives = require("hecate.reactor.primitives")
local tcp = require("hecate.reactor.tcp")
local uv_call = require("hecate.reactor.internal.uv_call")

---@class hecate.reactor
---@field Reactor hecate.reactor.Reactor
---@field Future hecate.reactor.Future
---@field Scope hecate.reactor.Scope
---@field Instant hecate.reactor.Instant
---@field Channel hecate.reactor.Channel
---@field ChannelOperation hecate.reactor.ChannelOperation
---@field Semaphore hecate.reactor.Semaphore
---@field Mutex hecate.reactor.Mutex
---@field Monitor hecate.reactor.Monitor
---@field Condition hecate.reactor.Condition
---@field Permit hecate.reactor.Permit
---@field IoError hecate.core.Error
---@field fs hecate.reactor.fs
---@field TcpStream hecate.reactor.TcpStream
---@field TcpListener hecate.reactor.TcpListener
---@field resolve fun(host: string, options?: hecate.reactor.ResolveOptions): hecate.reactor.ResolvedAddress[]
local reactor = {
  Reactor = Reactor,
  Future = require("hecate.reactor.future"),
  Scope = require("hecate.reactor.scope"),
  Instant = require("hecate.reactor.instant"),
  Channel = require("hecate.reactor.channel"),
  ChannelOperation = require("hecate.reactor.channel_operation"),
  Semaphore = require("hecate.reactor.semaphore"),
  Mutex = require("hecate.reactor.mutex"),
  Monitor = require("hecate.reactor.monitor"),
  Condition = require("hecate.reactor.condition"),
  Permit = require("hecate.reactor.permit"),
  IoError = uv_call.IoError,
  fs = require("hecate.reactor.fs"),
  ---@diagnostic disable-next-line: assign-type-mismatch  -- class constructor exported as its class
  TcpStream = tcp.TcpStream,
  ---@diagnostic disable-next-line: assign-type-mismatch  -- class constructor exported as its class
  TcpListener = tcp.TcpListener,
  tcp_connect = tcp.connect,
  tcp_listen = tcp.listen,
  resolve = require("hecate.reactor.dns").resolve,
  wait_signal = require("hecate.reactor.signal").wait_signal,
  run_process = require("hecate.reactor.process").run,
  detach = primitives.detach,
  fork = primitives.fork,
  join = primitives.join,
  select = primitives.select,
  sleep = primitives.sleep,
  scope = primitives.scope,
  deadline = primitives.deadline,
  now = primitives.now,
}

--- Runs `fn(...)` on a new reactor until it and everything it forked have finished.
---@param fn fun(...): ...
---@param ... any
---@return any ...
function reactor.run(fn, ...)
  return Reactor():run(fn, ...)
end

--- Returns the absolute instant `seconds` on the reactor clock, for `deadline`.
---@param seconds number
---@return hecate.reactor.Instant
function reactor.at(seconds)
  return reactor.Instant(seconds)
end

reactor.is_future = function(value) return core.is_instance_of(value, reactor.Future) end

return reactor
