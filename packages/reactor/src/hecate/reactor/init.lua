-- hecate.reactor: the reactor over libuv (luv): scheduler, futures, structured concurrency
-- (concurrency.md; ADR 0002, ADR 0003): public entry point, re-exporting the primitives,
-- synchronisation objects, transport, processes, `ipc` and the ambient context.
global <const> require

local core = require("hecate.core")
local Reactor = require("hecate.reactor.reactor")
local primitives = require("hecate.reactor.primitives")
local tcp = require("hecate.reactor.tcp")
local pipe = require("hecate.reactor.pipe")
local udp = require("hecate.reactor.udp")
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
---@field UdpSocket hecate.reactor.UdpSocket
---@field PipeStream hecate.reactor.PipeStream
---@field PipeListener hecate.reactor.PipeListener
---@field Process hecate.reactor.Process
---@field Peer hecate.reactor.Peer
---@field ipc hecate.reactor.ipc
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
  ---@diagnostic disable-next-line: assign-type-mismatch  -- class constructor exported as its class
  UdpSocket = udp.UdpSocket,
  ---@diagnostic disable-next-line: assign-type-mismatch  -- class constructor exported as its class
  PipeStream = pipe.PipeStream,
  ---@diagnostic disable-next-line: assign-type-mismatch  -- class constructor exported as its class
  PipeListener = pipe.PipeListener,
  ---@diagnostic disable-next-line: assign-type-mismatch  -- class constructor exported as its class
  Process = require("hecate.reactor.process").Process,
  ---@diagnostic disable-next-line: assign-type-mismatch  -- class constructor exported as its class
  Peer = require("hecate.reactor.ipc").Peer,
  ipc = require("hecate.reactor.ipc"),
}

-- The functions are assigned one by one, not in the table constructor: LuaLS leaves
-- constructor entries out of the documentation export, and an entry hides the documented
-- definition of the same name (coding-standards.md, "Annotations for the reference").
reactor.connect_tcp = tcp.connect_tcp
reactor.listen_tcp = tcp.listen_tcp
reactor.connect_pipe = pipe.connect_pipe
reactor.listen_pipe = pipe.listen_pipe
reactor.bind_udp = udp.bind_udp
local process = require("hecate.reactor.process")
reactor.run_process = process.run_process
reactor.spawn = process.spawn -- glossary-ok: operating-system process (ADR 0023)
reactor.supports_reuseport = tcp.supports_reuseport
reactor.resolve = require("hecate.reactor.dns").resolve
reactor.wait_signal = require("hecate.reactor.signal").wait_signal
reactor.detach = primitives.detach
reactor.fork = primitives.fork
reactor.join = primitives.join
reactor.select = primitives.select
reactor.sleep = primitives.sleep
reactor.scope = primitives.scope
reactor.with_ambient = primitives.with_ambient
reactor.ambient = primitives.ambient
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
