-- hecate.reactor: the reactor over libuv (luv): scheduler, futures, structured concurrency
-- (concurrency.md; ADR 0002, ADR 0003). Step 1 of the roadmap item: loop, Future, fork,
-- join, select, sleep, scope, deadline, cancellation and virtual clock.
global <const> require

local core = require("hecate.core")
local Reactor = require("hecate.reactor.reactor")
local primitives = require("hecate.reactor.primitives")
local tcp = require("hecate.reactor.tcp")
local uv_call = require("hecate.reactor.internal.uv_call")

--- The reactor over libuv: scheduler, futures, structured concurrency, channels, timers,
--- signals, processes, file system and transport primitives.
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
---@field TransportError hecate.core.NetworkError
---@field fs hecate.reactor.fs
---@field TcpStream hecate.reactor.TcpStream
---@field TcpListener hecate.reactor.TcpListener
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
  TransportError = uv_call.TransportError,
  fs = require("hecate.reactor.fs"),
  ---@diagnostic disable-next-line: assign-type-mismatch  -- class constructor exported as its class
  TcpStream = tcp.TcpStream,
  ---@diagnostic disable-next-line: assign-type-mismatch  -- class constructor exported as its class
  TcpListener = tcp.TcpListener,
}

-- The functions are assigned one by one, not in the table constructor: LuaLS leaves
-- constructor entries out of the documentation export, and an entry hides the documented
-- definition of the same name (coding-standards.md, "Annotations for the reference").
reactor.tcp_connect = tcp.tcp_connect
reactor.tcp_listen = tcp.tcp_listen
reactor.run_process = require("hecate.reactor.process").run_process
reactor.resolve = require("hecate.reactor.dns").resolve
reactor.wait_signal = require("hecate.reactor.signal").wait_signal
reactor.detach = primitives.detach
reactor.fork = primitives.fork
reactor.join = primitives.join
reactor.select = primitives.select
reactor.sleep = primitives.sleep
reactor.scope = primitives.scope
reactor.deadline = primitives.deadline
reactor.now = primitives.now

--- Runs `fn(...)` on a new reactor until it and everything it forked have finished.
--- Returns the results of `fn`.
---
--- Raises the error of `fn`, or the first failure of a computation it forked.
---@param fn fun(...): ...  the main computation
---@param ... any  the arguments passed to `fn`
---@return any ...  the results of `fn`
function reactor.run(fn, ...)
  return Reactor():run(fn, ...)
end

--- Returns the absolute instant `seconds` on the reactor clock, for `deadline`.
---@param seconds number  a reading of the reactor clock
---@return hecate.reactor.Instant instant  the instant at that reading
function reactor.at(seconds)
  return reactor.Instant(seconds)
end

--- Returns whether `value` is a `hecate.reactor.Future`.
---@param value any  the value to test
---@return boolean result  `true` for a future
reactor.is_future = function(value) return core.is_instance_of(value, reactor.Future) end

return reactor
