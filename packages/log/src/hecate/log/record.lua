-- One log record: what a logger hands to its sinks.
global <const> require

local core = require("hecate.core")

--- A log record. Sinks read it and never modify it.
---@class hecate.log.Record
---@field severity hecate.core.EnumerationValue  a `hecate.log.Severity` value
---@field message string
---@field fields table  structured fields given at the call
---@field context table  context of the logger and of its scope, merged
---@field timestamp number  clock reading, in seconds since the epoch
---@field logger? string  name of the logger that produced it
---@overload fun(severity: hecate.core.EnumerationValue, message: string, fields: table, context: table, timestamp: number, logger?: string): hecate.log.Record
local Record = core.class("Record")

--- Initialises a record.
---@param severity hecate.core.EnumerationValue
---@param message string
---@param fields table
---@param context table
---@param timestamp number
---@param logger? string
function Record:init(severity, message, fields, context, timestamp, logger)
  self.severity, self.message, self.fields, self.context = severity, message, fields, context
  self.timestamp, self.logger = timestamp, logger
end

return core.finalise(Record)
