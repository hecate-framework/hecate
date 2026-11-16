-- JSON-lines event reporter: one JSON object per event, one per line, flushed as it is written.
-- No colour, no cursor control: the stream an IDE test adapter, a CI annotator or a JUnit XML
-- converter reads. The schema is documented in the package README ("Event stream").
global <const> require, io, ipairs

local core = require("hecate.core")

--- Writes the events of a run as JSON lines (schema version 1).
---@class hecate.test.JsonLinesReporter : hecate.test.Reporter
---@overload fun(options?: hecate.test.ReporterOptions): hecate.test.JsonLinesReporter
local JsonLinesReporter = core.class("JsonLinesReporter")

--- The version of the event schema, repeated in the `run_started` line.
JsonLinesReporter.SCHEMA_VERSION = 1

--- Creates a reporter.
---@param options? hecate.test.ReporterOptions  `write` receives each line with its newline
function JsonLinesReporter:init(options)
  local reporter_options = require("hecate.test.reporters.options")
  self._write = reporter_options.writer(reporter_options.check("JsonLinesReporter", options), true)
  -- required here so that the other reporters do not need the native encoder
  self._encode = require("hecate.json").encode
end

local SUITE_FIELDS = { "total", "passed", "failed", "errored", "assertions", "duration" }
local RUN_FIELDS = { "total", "passed", "failed", "errored", "assertions", "ok", "exit_code", "duration" }

local function copy_fields(into, from, names)
  for _, name in ipairs(names) do into[name] = from[name] end
  return into
end

--- The document of an event: `type` plus the fields documented in the README.
---@param event hecate.test.Event
---@return table
local function document(event)
  local kind = event.type
  if kind == "run_started" then
    return { type = kind, version = JsonLinesReporter.SCHEMA_VERSION, total = event.total, suites = event.suites }
  elseif kind == "suite_started" then
    return { type = kind, suite = event.suite, total = event.total }
  elseif kind == "test_started" then
    return { type = kind, suite = event.suite, test = event.test, index = event.index }
  elseif kind == "test_finished" then
    local result = event.result --[[@as hecate.test.Result]]
    local doc = {
      type = kind, suite = event.suite, test = event.test, index = event.index, case = result.case,
      status = result.status, assertions = result.assertions, duration = result.duration,
      message = result.message, location = result.location, traceback = result.traceback,
    }
    if result.differences and #result.differences > 0 then doc.differences = result.differences end
    return doc
  elseif kind == "suite_finished" then
    return copy_fields({ type = kind, suite = event.suite }, event.summary, SUITE_FIELDS)
  end
  return copy_fields({ type = kind }, event.summary, RUN_FIELDS)
end

--- Writes one line for the event.
---@param event hecate.test.Event
function JsonLinesReporter:handle(event)
  self._write(self._encode(document(event), { canonical = true }) .. "\n")
end

return core.finalise(JsonLinesReporter)
