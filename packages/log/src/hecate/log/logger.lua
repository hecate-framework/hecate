-- The logger: filters by severity, builds a record, hands it to synchronous sinks.
-- Logging never suspends the caller: no call below touches the reactor (invariant).
global <const> require, type, pairs, pcall, os, error, ipairs, tostring

local core = require("hecate.core")
local Record = require("hecate.log.record")
local Severity = require("hecate.log.severity")
local severity = require("hecate.log.internal.severity")

local EMPTY = {}

--- A sink: any object with a `write` method. It is called synchronously and must not suspend.
---@class hecate.log.Sink
---@field write fun(self: hecate.log.Sink, record: hecate.log.Record)

--- Options of `Logger`.
---@class hecate.log.LoggerOptions
---@field level? hecate.core.EnumerationValue|string  least urgent severity recorded (default `informational`)
---@field sinks? hecate.log.Sink[]  where records go
---@field name? string  name stored in every record
---@field context? table  fields added to every record
---@field context_provider? fun(): table?  returns the ambient context of the running computation (per scope), merged under `context`
---@field clock? fun(): number  seconds since the epoch (default `os.time`)

--- A logger with the eight methods of RFC 5424 (`emergency` to `debug`), a threshold and a context.
---
--- Each method is `logger:severity_name(message, fields?)`: `message` is a string, `fields` a table of
--- structured fields. A call below the threshold returns before any record is built.
---@class hecate.log.Logger
---@field emergency fun(self: hecate.log.Logger, message: string, fields?: table)
---@field alert fun(self: hecate.log.Logger, message: string, fields?: table)
---@field critical fun(self: hecate.log.Logger, message: string, fields?: table)
---@field error fun(self: hecate.log.Logger, message: string, fields?: table)
---@field warning fun(self: hecate.log.Logger, message: string, fields?: table)
---@field notice fun(self: hecate.log.Logger, message: string, fields?: table)
---@field informational fun(self: hecate.log.Logger, message: string, fields?: table)
---@field debug fun(self: hecate.log.Logger, message: string, fields?: table)
---@overload fun(options?: hecate.log.LoggerOptions): hecate.log.Logger
local Logger = core.class("Logger")

---@param sink any
local function check_sink(sink)
  if type(sink) ~= "table" or type(sink.write) ~= "function" then
    error(core.ArgumentError("invalid sink: expected an object with a write method"), 3)
  end
end

--- Initialises a logger.
---
--- Raises `hecate.core.ArgumentError` for an unknown severity, a sink without `write` or an option of the wrong type.
---@param options? hecate.log.LoggerOptions
function Logger:init(options)
  options = options or EMPTY
  self._threshold = severity.resolve(options.level or Severity.informational, 2).ordinal
  self._name = options.name
  self._context = options.context or EMPTY
  self._provider = options.context_provider
  self._clock = options.clock or os.time
  -- State shared with the children made by `with_context`: the sink list and the failure count.
  self._shared = { sinks = {}, failures = 0 }
  for _, sink in ipairs(options.sinks or EMPTY) do
    check_sink(sink)
    self._shared.sinks[#self._shared.sinks + 1] = sink
  end
end

--- Adds a sink; the children made by `with_context` see it too.
---
--- Raises `hecate.core.ArgumentError` if the sink has no `write` method.
---@param sink hecate.log.Sink
function Logger:add_sink(sink)
  check_sink(sink)
  local sinks = self._shared.sinks
  sinks[#sinks + 1] = sink
end

--- Sets the least urgent severity that is recorded.
---
--- Raises `hecate.core.ArgumentError` for an unknown severity.
---@param level hecate.core.EnumerationValue|string
function Logger:set_level(level) self._threshold = severity.resolve(level, 2).ordinal end

--- Returns the least urgent severity that is recorded.
---@return hecate.core.EnumerationValue
function Logger:level() return Severity:values()[self._threshold] end

--- Tells whether a severity is recorded. Use it to skip costly arguments when a level is disabled.
---
--- Raises `hecate.core.ArgumentError` for an unknown severity.
---@param level hecate.core.EnumerationValue|string
---@return boolean
function Logger:is_enabled(level) return severity.resolve(level, 2).ordinal <= self._threshold end

--- Returns how many times a sink raised while writing a record (shared with the children).
---@return integer
function Logger:failures() return self._shared.failures end

--- Returns a child logger whose context is this one's extended with `fields` (`fields` wins).
--- The child shares the sinks, and takes the threshold, name, clock and provider of this logger.
--- Pass the child to forked computations: it carries its context across fork and join.
---
--- Raises `hecate.core.ArgumentError` if `fields` is not a table.
---@param fields table
---@return hecate.log.Logger
function Logger:with_context(fields)
  if type(fields) ~= "table" then
    error(core.ArgumentError(("with_context expects a table, got %s"):format(type(fields))), 2)
  end
  local child = Logger({
    level = self:level(), name = self._name, context_provider = self._provider, clock = self._clock,
  })
  local context = {}
  for key, value in pairs(self._context) do context[key] = value end
  for key, value in pairs(fields) do context[key] = value end
  child._context = context
  child._shared = self._shared
  return child
end

---@param self hecate.log.Logger
---@param level hecate.core.EnumerationValue
---@param message string
---@param fields? table
local function emit(self, level, message, fields)
  if type(message) ~= "string" then
    error(core.ArgumentError(("log message must be a string, got %s"):format(type(message))), 3)
  end
  if fields ~= nil and type(fields) ~= "table" then
    error(core.ArgumentError(("log fields must be a table, got %s"):format(type(fields))), 3)
  end
  local context = {}
  local ambient = self._provider and self._provider()
  if ambient then for key, value in pairs(ambient) do context[key] = value end end
  for key, value in pairs(self._context) do context[key] = value end
  local record = Record(level, message, fields or {}, context, self._clock(), self._name)
  local shared = self._shared
  for _, sink in ipairs(shared.sinks) do
    -- A sink must never fail the caller: the failure is counted (OQ-55).
    if not pcall(sink.write, sink, record) then shared.failures = shared.failures + 1 end
  end
end

--- Records a message at a severity, if that severity is enabled.
---
--- Raises `hecate.core.ArgumentError` for an unknown severity, a message that is not a string or fields that are not a table.
---@param level hecate.core.EnumerationValue|string
---@param message string
---@param fields? table
function Logger:log(level, message, fields)
  local resolved = severity.resolve(level, 2)
  if resolved.ordinal > self._threshold then return end
  emit(self, resolved, message, fields)
end

for _, level in ipairs(Severity:values()) do
  local ordinal = level.ordinal
  Logger[level.name] = function(self, message, fields)
    if ordinal > self._threshold then return end
    emit(self, level, message, fields)
  end
end

return core.finalise(Logger)
