-- JUnit XML reporter: the de facto report format of continuous-integration servers (one
-- `testsuite` per suite, one `testcase` per test), written once at the end of the run.
global <const> require, io, table, tostring, ipairs, assert

local core = require("hecate.core")

--- Writes the results of a run as JUnit XML.
---@class hecate.test.JUnitReporter : hecate.test.Reporter
---@overload fun(options?: hecate.test.ReporterOptions): hecate.test.JUnitReporter
local JUnitReporter = core.class("JUnitReporter")

--- Creates a JUnit XML reporter.
---@param options? hecate.test.ReporterOptions  `write` receives the document
function JUnitReporter:init(options)
  local reporter_options = require("hecate.test.reporters.options")
  self._write = reporter_options.writer(reporter_options.check("JUnitReporter", options))
  self._suites, self._order = {}, {}
end

-- XML 1.0 text: the five predefined entities are escaped; characters that XML 1.0 cannot carry
-- (controls other than tab, line feed and carriage return) become U+FFFD.
local function escape(text)
  text = tostring(text):gsub("[%c]", function(c)
    if c == "\t" or c == "\n" or c == "\r" then return c end
    return "\u{FFFD}"
  end)
  return (text:gsub('[&<>"\']', {
    ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;", ["'"] = "&apos;",
  }))
end

-- The name of a test without its case prefix (`Case.test_x` is `test_x`).
local function short(result)
  local prefix = result.case .. "."
  if result.name:sub(1, #prefix) == prefix then return result.name:sub(#prefix + 1) end
  return result.name
end

local function seconds(value) return ("%.6f"):format(value or 0) end

-- The lines of the element of one test.
local function testcase(result, lines)
  local head = ('    <testcase classname="%s" name="%s" time="%s"'):format(
    escape(result.case), escape(short(result)), seconds(result.duration))
  if result.status == "passed" then
    lines[#lines + 1] = head .. "/>"
    return
  end
  local tag = result.status == "failed" and "failure" or "error"
  local body = {}
  if result.location then body[#body + 1] = "at " .. result.location end
  if result.traceback then body[#body + 1] = result.traceback end
  lines[#lines + 1] = head .. ">"
  lines[#lines + 1] = ('      <%s message="%s" type="%s">%s</%s>'):format(tag,
    escape((result.message or ""):match("^[^\n]*")), result.status == "failed" and "AssertionFailure" or "Error",
    escape(table.concat({ result.message or "", table.concat(body, "\n") }, "\n")), tag)
  lines[#lines + 1] = "    </testcase>"
end

--- Handles one event of the run: results are collected, the document is written at
--- `run_finished`.
---@param event hecate.test.Event
function JUnitReporter:handle(event)
  if event.type == "test_finished" then
    local name = event.result.suite
    local suite = self._suites[name]
    if not suite then
      suite = { name = name, results = {}, failures = 0, errors = 0, time = 0 }
      self._suites[name], self._order[#self._order + 1] = suite, suite
    end
    suite.results[#suite.results + 1] = event.result
    suite.time = suite.time + (event.result.duration or 0)
    if event.result.status == "failed" then suite.failures = suite.failures + 1
    elseif event.result.status == "errored" then suite.errors = suite.errors + 1 end
  elseif event.type == "run_finished" then
    local summary = assert(event.summary, "run_finished carries a summary")
    local lines = { '<?xml version="1.0" encoding="UTF-8"?>',
      ('<testsuites tests="%d" failures="%d" errors="%d" time="%s">'):format(
        summary.total, summary.failed, summary.errored, seconds(summary.duration)) }
    for _, suite in ipairs(self._order) do
      lines[#lines + 1] = ('  <testsuite name="%s" tests="%d" failures="%d" errors="%d" skipped="0" time="%s">'):format(
        escape(suite.name), #suite.results, suite.failures, suite.errors, seconds(suite.time))
      for _, result in ipairs(suite.results) do testcase(result, lines) end
      lines[#lines + 1] = "  </testsuite>"
    end
    lines[#lines + 1] = "</testsuites>"
    self._write(table.concat(lines, "\n") .. "\n")
  end
end

return core.finalise(JUnitReporter)
