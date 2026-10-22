-- hecate.log: structured logging with RFC 5424 severities, per-scope context and pluggable sinks.
global <const> require

local severity = require("hecate.log.internal.severity")

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

--- Returns the numerical code of a severity, as in RFC 5424, section 6.2.1 (0 for `emergency` to 7 for `debug`).
---@param level hecate.core.EnumerationValue  a `hecate.log.Severity` value
---@return integer code
function log.severity_code(level) return severity.code(level) end

return log
