-- hecate.reactor: the reactor over libuv (luv): scheduler, futures, structured concurrency
-- (concurrency.md; ADR 0002, ADR 0003). Step 1 of the roadmap item: loop, Future, fork,
-- join, select, sleep, scope, deadline, cancellation and virtual clock.
global <const> require

local core = require("hecate.core")
local Reactor = require("hecate.reactor.reactor")
local primitives = require("hecate.reactor.primitives")

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
