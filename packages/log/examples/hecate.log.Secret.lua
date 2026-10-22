-- A secret is never rendered by a sink, whatever the depth of the field that holds it.
local log = require("hecate.log")

local lines = {}
local logger = log.Logger({ sinks = { log.JsonLinesSink({ output = function(line) lines[#lines + 1] = line end }) } })

logger:error("login failed", { user = "ada", password = log.Secret("hunter2") })
print(("%s %s"):format(lines[1]:find("hunter2", 1, true) == nil, lines[1]:find("[redacted]", 1, true) ~= nil))
-- Prints: true true
