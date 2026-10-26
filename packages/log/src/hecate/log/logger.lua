-- The logger: filters by severity, builds a record, hands it to synchronous sinks.
-- Logging never suspends the caller: no call below touches the reactor (invariant).
global <const> require, type, pairs, pcall, os, error, ipairs, tostring, getmetatable, next

local core = require("hecate.core")
local Record = require("hecate.log.record")
local Severity = require("hecate.log.severity")
local severities = require("hecate.log.internal.severity")
local ambient = require("hecate.log.internal.ambient")

local Secret = require("hecate.log.secret")

local EMPTY = {}
local MAX_REDACT_DEPTH = 16

--- Copies `value`, wrapping in a `Secret` every value whose key is in `names`. Stops at `MAX_REDACT_DEPTH`
--- (a deeper table is kept as is: sinks bound their own depth).
---@param value any
---@param names table<string, true>
---@param depth integer
---@return any
local function redact(value, names, depth)
  if type(value) ~= "table" or getmetatable(value) ~= nil or depth > MAX_REDACT_DEPTH then return value end
  local copy = {}
  for key, item in pairs(value) do
    if type(key) == "string" and names[key:lower()] and not core.is_instance_of(item, Secret) then
      copy[key] = Secret(item)
    else
      copy[key] = redact(item, names, depth + 1)
    end
  end
  return copy
end

--- A sink: any object with a `write` method. It is called synchronously and must not suspend.
---@class hecate.log.Sink
---@field write fun(self: hecate.log.Sink, record: hecate.log.Record)

--- Options of `Logger`.
---@class hecate.log.LoggerOptions
---@field severity? hecate.core.EnumerationValue|string  least urgent severity recorded (default `informational`)
---@field sinks? hecate.log.Sink[]  where records go
---@field name? string  name stored in every record
---@field context? table  fields added to every record
---@field context_provider? fun(): table?  returns the ambient context of the running computation, merged under `context` (default: the fields bound by `log.bind`); if it raises or returns a non-table the call is counted in `failures()` and the record is written without it
---@field redact? string[]  field names (case-insensitive, at any depth) whose values are replaced by a `Secret`
---@field clock? fun(): number  seconds since the epoch (default `os.time`)

--- A logger with the eight methods of RFC 5424 (`emergency` to `debug`), a severity filter and a context.
---
--- Each method is `logger:severity_name(message, fields?)`: `message` is a string, `fields` a table of
--- structured fields. A call less urgent than the logger's severity returns before any record is built.
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
    error(core.ArgumentError("log.Logger: invalid sink: expected an object with a write method"), 3)
  end
end

--- Initialises a logger.
---
--- Raises `hecate.core.ArgumentError` for an unknown severity, a sink without `write` or an option of the wrong type.
---@param options? hecate.log.LoggerOptions
function Logger:init(options)
  options = options or EMPTY
  self._severity = severities.resolve(options.severity or Severity.informational, 2, "log.Logger").ordinal
  self._name = options.name
  self._context = options.context or EMPTY
  self._provider = options.context_provider or ambient.fields
  self._clock = options.clock or os.time
  if options.redact ~= nil then
    if type(options.redact) ~= "table" then
      error(core.ArgumentError("log.Logger: invalid redact option: expected a list of field names"), 2)
    end
    local names = {}
    for _, name in ipairs(options.redact) do
      if type(name) ~= "string" then error(core.ArgumentError("log.Logger: invalid redact option: names are strings"), 2) end
      names[name:lower()] = true
    end
    if next(names) then self._redact = names end
  end
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
---@param severity hecate.core.EnumerationValue|string
function Logger:set_severity(severity) self._severity = severities.resolve(severity, 2, "log.Logger.set_severity").ordinal end

--- Returns the least urgent severity that is recorded.
---@return hecate.core.EnumerationValue
function Logger:severity() return Severity:values()[self._severity] end

--- Tells whether a severity is recorded. Use it to skip costly arguments when a severity is disabled.
---
--- Raises `hecate.core.ArgumentError` for an unknown severity.
---@param severity hecate.core.EnumerationValue|string
---@return boolean
function Logger:is_enabled(severity) return severities.resolve(severity, 2, "log.Logger.is_enabled").ordinal <= self._severity end

--- Returns how many times a sink raised while writing a record (shared with the children).
---@return integer
function Logger:failures() return self._shared.failures end

--- Returns a child logger whose context is this one's extended with `fields` (`fields` wins).
--- The child shares the sinks, and takes the severity, name, clock and provider of this logger.
--- Pass the child to forked computations: it carries its context across fork and join.
---
--- Raises `hecate.core.ArgumentError` if `fields` is not a table.
---@param fields table
---@return hecate.log.Logger
function Logger:with_context(fields)
  if type(fields) ~= "table" then
    error(core.ArgumentError(("log.Logger.with_context: expects a table, got %s"):format(type(fields))), 2)
  end
  local child = Logger({
    severity = self:severity(), name = self._name, context_provider = self._provider, clock = self._clock,
  })
  child._redact = self._redact
  local context = {}
  for key, value in pairs(self._context) do context[key] = value end
  for key, value in pairs(fields) do context[key] = value end
  child._context = context
  child._shared = self._shared
  return child
end

---@param self hecate.log.Logger
---@param call string  qualified name of the call the caller wrote (message prefix)
---@param severity hecate.core.EnumerationValue
---@param message string
---@param fields? table
local function emit(self, call, severity, message, fields)
  if type(message) ~= "string" then
    error(core.ArgumentError(("%s: message must be a string, got %s"):format(call, type(message))), 3)
  end
  if fields ~= nil and type(fields) ~= "table" then
    error(core.ArgumentError(("%s: fields must be a table, got %s"):format(call, type(fields))), 3)
  end
  local context = {}
  if self._provider then
    -- A provider that raises or returns something else than a table is counted and ignored: the record is kept.
    local ok, ambient = pcall(self._provider)
    if ok and type(ambient) == "table" then
      for key, value in pairs(ambient) do context[key] = value end
    elseif not ok or ambient ~= nil then
      self._shared.failures = self._shared.failures + 1
    end
  end
  for key, value in pairs(self._context) do context[key] = value end
  fields = fields or {}
  local names = self._redact
  if names then
    fields = redact(fields, names, 1)
    context = redact(context, names, 1)
  end
  local record = Record(severity, message, fields, context, self._clock(), self._name)
  local shared = self._shared
  for _, sink in ipairs(shared.sinks) do
    -- A sink must never fail the caller: the failure is counted (OQ-55).
    if not pcall(sink.write, sink, record) then shared.failures = shared.failures + 1 end
  end
end

--- Records a message at a severity, if that severity is enabled.
---
--- Raises `hecate.core.ArgumentError` for an unknown severity, a message that is not a string or fields that are not a table.
---@param severity hecate.core.EnumerationValue|string
---@param message string
---@param fields? table
function Logger:log(severity, message, fields)
  local resolved = severities.resolve(severity, 2, "log.Logger.log")
  if resolved.ordinal > self._severity then return end
  emit(self, "log.Logger.log", resolved, message, fields)
end

for _, value in ipairs(Severity:values()) do
  local ordinal = value.ordinal
  local call = "log.Logger." .. value.name
  Logger[value.name] = function(self, message, fields)
    if ordinal > self._severity then return end
    emit(self, call, value, message, fields)
  end
end

return core.finalise(Logger)
