-- Builds the default logger from the logging keys of a configuration (configuration.md, "Logging keys").
global <const> require, ipairs, pairs, error, io

local core = require("hecate.core")
local log = require("hecate.log")

--- The logger of the application, built from the `logging` configuration.
---@class hecate.kernel.logging
local M = {}

local function stdout(line) io.stdout:write(line) end

--- Builds a logger from `logging.*`: severity, sinks, `async`, `redact` added to `log.DEFAULT_REDACT`. A named
--- severity (`logging.severities`) matching the logger name `hecate` replaces `logging.severity`. `console` and
--- `json_lines` write to standard output (twelve-factor "Logs").
---
--- Raises `hecate.core.ArgumentError` for a `file` sink without a path.
---@param configuration hecate.config.Configuration
---@return hecate.log.Logger logger
function M.build(configuration)
  local section = configuration:get("logging")
  local sinks = {}
  for _, name in ipairs(section.sinks) do
    local sink
    if name == "console" then
      sink = log.ConsoleSink({ output = stdout })
    elseif name == "json_lines" then
      sink = log.JsonLinesSink({ output = stdout })
    else
      local file = section.file
      if file == nil or file.path == nil then
        error(core.ArgumentError("hecate.kernel.logging.build: logging.sinks contains file but logging.file.path is not set"), 2)
      end
      sink = log.FileSink({ path = file.path })
    end
    if section.async then sink = log.AsyncSink({ sink = sink }) end
    sinks[#sinks + 1] = sink
  end
  local redact = {}
  for _, name in ipairs(log.DEFAULT_REDACT) do redact[#redact + 1] = name end
  for _, name in ipairs(section.redact) do redact[#redact + 1] = name end
  local name = "hecate"
  local severity = section.severities[name] or section.severity
  return log.Logger({ name = name, severity = severity, redact = redact, sinks = sinks })
end

return M
