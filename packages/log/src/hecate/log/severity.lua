-- The eight severities of RFC 5424, section 6.2.1, "Severity".
global <const> require

local core = require("hecate.core")

--- The severity of a log record, from the most urgent (`emergency`) to the least (`debug`).
---
--- The declaration order is the order of the numerical codes of RFC 5424, section 6.2.1: the
--- ordinal of a value minus one is its code (`hecate.log.severity_code`).
---@class hecate.log.Severity
---@field emergency hecate.core.EnumerationValue  code 0: the system is unusable
---@field alert hecate.core.EnumerationValue  code 1: action must be taken immediately
---@field critical hecate.core.EnumerationValue  code 2: critical conditions
---@field error hecate.core.EnumerationValue  code 3: error conditions
---@field warning hecate.core.EnumerationValue  code 4: warning conditions
---@field notice hecate.core.EnumerationValue  code 5: normal but significant condition
---@field informational hecate.core.EnumerationValue  code 6: informational messages
---@field debug hecate.core.EnumerationValue  code 7: debug messages
---@field values fun(self: hecate.log.Severity): hecate.core.EnumerationValue[]  the severities, most urgent first
---@field names fun(self: hecate.log.Severity): string[]  the severity names, most urgent first
---@field contains fun(self: hecate.log.Severity, candidate: any): boolean  tells whether a value is a severity
---@field find fun(self: hecate.log.Severity, name: string): hecate.core.EnumerationValue?  returns the severity named `name`
---@field size fun(self: hecate.log.Severity): integer  the number of severities
local Severity = core.enumeration("Severity", {
  "emergency", "alert", "critical", "error", "warning", "notice", "informational", "debug",
})

return Severity
