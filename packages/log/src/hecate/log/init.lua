-- hecate.log: structured logging with RFC 5424 severities, per-scope context and pluggable sinks.
global <const> require, type, error

local core = require("hecate.core")
local severity = require("hecate.log.internal.severity")
local ambient = require("hecate.log.internal.ambient")

--- Structured logging: severities, records, loggers and sinks.
---@class hecate.log
---@field Severity hecate.log.Severity  the eight severities of RFC 5424, section 6.2.1
---@field Record table  the class of log records
---@field Logger table  the class of loggers
---@field Secret table  marks a value that no sink renders
---@field MemorySink table  synchronous in-memory sink
---@field JsonLinesSink table  sink writing one JSON object per line
---@field ConsoleSink table  sink writing human-readable lines
---@field FileSink table  sink appending JSON lines to a file
---@field LimitedSink table  decorator sink that samples and rate-limits records
---@field AsyncSink table  decorator sink that writes from a detached task, never suspending the caller
local log = {}

log.Severity = require("hecate.log.severity")
log.Record = require("hecate.log.record")
log.Logger = require("hecate.log.logger")
log.Secret = require("hecate.log.secret")
log.MemorySink = require("hecate.log.memory_sink")
log.JsonLinesSink = require("hecate.log.json_lines_sink")
log.ConsoleSink = require("hecate.log.console_sink")
log.FileSink = require("hecate.log.file_sink")
log.LimitedSink = require("hecate.log.limited_sink")
log.AsyncSink = require("hecate.log.async_sink")

--- Runs `fn(...)` with `fields` added to the ambient context of every record logged by the running
--- computation and by the computations it forks or detaches meanwhile (ADR 0025). A logger without a
--- `context_provider` reads it; `fields` wins over the fields bound outside, and the context of a
--- logger wins over both.
---
--- Raises `hecate.core.ArgumentError` if `fields` is not a table, and
--- `hecate.core.NonYieldableContextError` outside a managed coroutine.
---@param fields table  the fields to bind, for example `{ request_id = "r1" }`
---@param fn fun(...): ...  the function run with the binding
---@param ... any  the arguments passed to `fn`
---@return any ...  the results of `fn`
function log.bind(fields, fn, ...)
  if type(fields) ~= "table" then
    error(core.ArgumentError(("log.bind: expects a table of fields, got %s"):format(type(fields))), 2)
  end
  return ambient.bind(fields, fn, ...)
end

--- Returns the numerical code of a severity, as in RFC 5424, section 6.2.1 (0 for `emergency` to 7 for `debug`).
---@param level hecate.core.EnumerationValue  a `hecate.log.Severity` value
---@return integer code
function log.severity_code(level) return severity.code(level) end

return log
