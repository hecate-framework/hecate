-- A logger drops what is below its level, adds its context to every record and hands the rest to
-- its sinks.
local log = require("hecate.log")

local sink = log.MemorySink()
local logger = log.Logger({ level = "informational", sinks = { sink } }):with_context({ request = "r-1" })

logger:debug("not recorded")
logger:warning("slow query", { millis = 120 })
local record = sink:records()[1]
print(("%d %s %s %s"):format(#sink:records(), record.message, record.context.request, record.fields.millis))
-- Prints: 1 slow query r-1 120
