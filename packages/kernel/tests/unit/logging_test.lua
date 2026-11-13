---@diagnostic disable: need-check-nil, missing-fields, undefined-field, param-type-mismatch, assign-type-mismatch, invisible
-- The logger built from the `logging.*` keys of a configuration (`hecate.kernel.logging`, configuration.md, "Logging keys").
local test = require("harness.test")
local core = require("hecate.core")
local config = require("hecate.config")
local json = require("hecate.json")
local log = require("hecate.log")
local reactor = require("hecate.reactor")
local logging = require("hecate.kernel.logging")
local T = test.Case("LoggingTest")

--- A configuration of the `development` environment whose `config/default.lua` sets `logging = <source>`.
---@param source string  a Lua table constructor
---@return hecate.config.Configuration
local function configuration(source)
  return config.load({
    properties = {}, environment = "development",
    getenv = function() return nil end,
    read_file = function(path)
      if path == "config/default.lua" then return "return { logging = " .. source .. " }" end
      if path == "config/development.lua" then return "return {}" end
      return nil, "no such file: " .. path, true
    end,
  })
end

--- Runs `body` with `io.stdout` and `io.stderr` replaced by recorders; returns what each received.
---@param body fun(stdout: string[], stderr: string[])
---@return string[] stdout
---@return string[] stderr
local function capture(body)
  local out, err = {}, {}
  local function recorder(into)
    local file = {}
    function file.write(self, ...)
      for _, part in ipairs({ ... }) do into[#into + 1] = tostring(part) end
      return self
    end
    function file.flush(self) return self end
    return file
  end
  local saved_out, saved_err = io.stdout, io.stderr
  io.stdout, io.stderr = recorder(out), recorder(err)
  local ok, failure = pcall(body, out, err)
  io.stdout, io.stderr = saved_out, saved_err
  if not ok then error(failure, 0) end
  return out, err
end

-- Documented in website/en/how-to/before-going-to-production.md (Logging).
function T:test_the_default_logger_is_one_console_sink_at_informational_on_the_standard_output()
  local logger = logging.build(configuration("{}"))
  self:assert_true(logger:severity() == log.Severity.informational)
  self:assert_false(logger:is_enabled("debug"))
  local out, err = capture(function()
    logger:informational("listening", { port = 8080 })
    logger:debug("not recorded")
  end)
  self:assert_equal(1, #out)
  self:assert_true(out[1]:find("listening", 1, true) ~= nil, out[1])
  self:assert_nil(out[1]:find("not recorded", 1, true))
  self:assert_equal(0, #err) -- nothing on the standard error stream
  -- Human-readable: not a JSON object.
  self:assert_false((pcall(json.decode, out[1])))
end

-- Documented in website/en/how-to/before-going-to-production.md (Logging).
function T:test_json_lines_writes_one_json_object_per_line_on_the_standard_output()
  local logger = logging.build(configuration("{ sinks = { 'json_lines' } }"))
  local out, err = capture(function()
    logger:warning("first", { n = 1 })
    logger:notice("second", { n = 2 })
  end)
  self:assert_equal(0, #err)
  self:assert_equal(2, #out)
  for index, expected in ipairs({ { "first", "warning" }, { "second", "notice" } }) do
    local line = out[index]
    self:assert_equal("\n", line:sub(-1))
    self:assert_nil(line:sub(1, -2):find("\n", 1, true), "one line per record")
    local object = json.decode(line:sub(1, -2))
    self:assert_equal(expected[1], object.message)
    self:assert_equal(expected[2], object.severity)
  end
end

-- Documented in website/en/how-to/before-going-to-production.md (Logging).
function T:test_console_and_json_lines_together_both_write_to_the_standard_output()
  local logger = logging.build(configuration("{ sinks = { 'console', 'json_lines' } }"))
  local out, err = capture(function() logger:notice("twice") end)
  self:assert_equal(0, #err)
  self:assert_equal(2, #out)
  self:assert_false((pcall(json.decode, out[1])))
  self:assert_equal("twice", json.decode(out[2]:sub(1, -2)).message)
end

-- Documented in website/en/how-to/before-going-to-production.md (Logging).
function T:test_async_wraps_each_sink_in_an_async_sink()
  local logger = logging.build(configuration("{ sinks = { 'console', 'json_lines' }, async = true }"))
  local sinks = logger._shared.sinks
  self:assert_equal(2, #sinks)
  for _, sink in ipairs(sinks) do self:assert_true(core.is_instance_of(sink, log.AsyncSink)) end
  -- The record is queued by the call and written later by the drain computation of each sink.
  local during
  local out = capture(function(written)
    reactor.run(function()
      logger:notice("queued")
      during = #written
      for _, sink in ipairs(sinks) do sink:close() end
    end)
  end)
  self:assert_equal(0, during)
  self:assert_equal(2, #out) -- both sinks wrote once their drain ran
  self:assert_true(out[1]:find("queued", 1, true) ~= nil, out[1])
  local synchronous = logging.build(configuration("{ sinks = { 'json_lines' }, async = false }"))
  self:assert_true(core.is_instance_of(synchronous._shared.sinks[1], log.JsonLinesSink))
end

-- Documented in website/en/how-to/before-going-to-production.md (Logging): with `logging.async`, each sink queues at
-- most 1024 records and drops the others silently; the drop count of the sink is not reachable from the logger.
function T:test_async_drops_records_past_a_queue_of_1024_without_a_reachable_count()
  local logger = logging.build(configuration("{ sinks = { 'json_lines' }, async = true }"))
  local sink = logger._shared.sinks[1]
  local out = capture(function()
    reactor.run(function()
      -- No suspension between the calls: the drain computation cannot run, so the queue fills up.
      for index = 1, 1030 do logger:notice("record", { index = index }) end
      self:assert_equal(1024, sink:pending())
      self:assert_equal(6, sink:dropped())
      sink:close()
    end)
  end)
  self:assert_equal(1024, #out)
  self:assert_equal(0, logger:failures()) -- a dropped record is not a failure of the logger
  self:assert_nil(logger.sinks, "the logger has no public accessor of its sinks")
  self:assert_nil(logger.dropped, "nor of their drop counts")
end

-- Documented in website/en/how-to/before-going-to-production.md (Redaction does not read free text).
function T:test_redact_names_are_added_to_the_default_list()
  local logger = logging.build(configuration("{ sinks = { 'json_lines' }, redact = { 'pin' } }"))
  local out = capture(function()
    logger:notice("login", { password = "hunter2", token = "t0k", pin = "1234", PIN = "5678", user_pin = "kept", user = "ada" })
  end)
  self:assert_equal(1, #out)
  local fields = json.decode(out[1]:sub(1, -2)).fields
  self:assert_equal("[redacted]", fields.password) -- a name of log.DEFAULT_REDACT, still redacted
  self:assert_equal("[redacted]", fields.token)
  self:assert_equal("[redacted]", fields.pin) -- the configured name
  self:assert_equal("[redacted]", fields.PIN) -- case-insensitive
  self:assert_equal("kept", fields.user_pin) -- matched exactly, not as a part of a name
  self:assert_equal("ada", fields.user)
  for _, leak in ipairs({ "hunter2", "t0k", "1234", "5678" }) do self:assert_nil(out[1]:find(leak, 1, true), leak) end
end

-- Documented in website/en/how-to/before-going-to-production.md (Logging).
function T:test_severities_applies_to_the_logger_named_exactly_as_the_key()
  local exact = logging.build(configuration("{ severity = 'warning', severities = { hecate = 'debug' } }"))
  self:assert_true(exact:severity() == log.Severity.debug)
  -- A dotted name below it, a prefix of it or another name leaves `logging.severity` in force.
  local others = logging.build(configuration(
    "{ severity = 'warning', severities = { ['hecate.kernel'] = 'debug', hec = 'debug', app = 'debug', HECATE = 'debug' } }"))
  self:assert_true(others:severity() == log.Severity.warning)
  self:assert_false(others:is_enabled("notice"))
end

return T
