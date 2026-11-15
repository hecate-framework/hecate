-- Console reporter: one line per test, the failures with their details, a final summary line.
global <const> require, io, ipairs

local core = require("hecate.core")

--- Writes the progress of a run for a person: `.`-free, line-oriented output that is stable in logs.
---@class hecate.test.ConsoleReporter : hecate.test.Reporter
---@overload fun(write?: fun(text: string)): hecate.test.ConsoleReporter
local ConsoleReporter = core.class("ConsoleReporter")

local MARK = { passed = "PASS", failed = "FAIL", errored = "ERROR" }

--- Creates a console reporter.
---@param write? fun(text: string)  receives the output, default `io.stdout:write`
function ConsoleReporter:init(write)
  self._write = write or function(text) io.stdout:write(text) end
  self._problems = {}
end

--- Announces the plan.
---@param plan { total: integer }
function ConsoleReporter:start(plan)
  self._write(("Running %d test(s)\n"):format(plan.total))
end

--- Writes the line of one result.
---@param result hecate.test.Result
function ConsoleReporter:report(result)
  self._write(("%-5s %s\n"):format(MARK[result.status], result.name))
  if result.status ~= "passed" then self._problems[#self._problems + 1] = result end
end

--- Writes the details of the failures and the totals.
---@param summary hecate.test.Summary
function ConsoleReporter:finish(summary)
  for _, result in ipairs(self._problems) do
    self._write(("\n%s %s\n"):format(MARK[result.status], result.name))
    if result.location then self._write("  at " .. result.location .. "\n") end
    if result.message then self._write("  " .. result.message:gsub("\n", "\n  ") .. "\n") end
  end
  self._write(("\n%d test(s): %d passed, %d failed, %d errored\n"):format(
    summary.total, summary.passed, summary.failed, summary.errored))
end

return core.finalise(ConsoleReporter)
