-- TAP 14 reporter (Test Anything Protocol, version 14): version line, plan, one test point per
-- test, failures with a YAML diagnostic block (TAP 14, "YAML Diagnostics").
global <const> require, io, table

local core = require("hecate.core")

--- Writes the results of a run as TAP 14.
---@class hecate.test.TapReporter : hecate.test.Reporter
---@overload fun(write?: fun(text: string)): hecate.test.TapReporter
local TapReporter = core.class("TapReporter")

--- Creates a TAP reporter.
---@param write? fun(text: string)  receives the output, default `io.stdout:write`
function TapReporter:init(write)
  self._write = write or function(text) io.stdout:write(text) end
  self._count = 0
end

-- A YAML double-quoted scalar (YAML 1.2, section 7.3.1).
local function quoted(text)
  return '"' .. text:gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" end
    return ("\\x%02X"):format(c:byte())
  end) .. '"'
end

-- A test name goes on the point line: `#` and `\` are escaped (TAP 14, "Test Points").
local function describe(name) return (name:gsub("[\\#]", "\\%0")) end

-- Writes the point of one result.
function TapReporter:_point(result)
  self._count = self._count + 1
  local ok = result.status == "passed"
  self._write(("%s %d - %s\n"):format(ok and "ok" or "not ok", self._count, describe(result.name)))
  if ok then return end
  local lines = { "  ---" }
  lines[#lines + 1] = "  severity: " .. (result.status == "failed" and "fail" or "error")
  if result.message then
    lines[#lines + 1] = "  message: |-"
    for line in (result.message .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = "    " .. line end
  end
  if result.location then lines[#lines + 1] = "  at: " .. quoted(result.location) end
  lines[#lines + 1] = "  ..."
  self._write(table.concat(lines, "\n") .. "\n")
end

--- Handles one event of the run: the version line and the plan at `run_started` (the plan comes
--- first, as TAP 14 allows), one point per `test_finished`; other events write nothing.
---@param event hecate.test.Event
function TapReporter:handle(event)
  if event.type == "run_started" then
    self._write("TAP version 14\n1.." .. event.total .. "\n")
  elseif event.type == "test_finished" then
    self:_point(event.result)
  end
end

return core.finalise(TapReporter)
