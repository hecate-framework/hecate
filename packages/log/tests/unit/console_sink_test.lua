local test = require("harness.test")
local log = require("hecate.log")
local T = test.Case("ConsoleSinkTest")

local function new_logger(options)
  local lines = {}
  options = options or {}
  options.sinks = { log.ConsoleSink({ output = function(line) lines[#lines + 1] = line end }) }
  options.clock = options.clock or function() return 1000000000 end
  return log.Logger(options), lines
end

function T:test_a_line_holds_timestamp_severity_logger_message_and_sorted_pairs()
  local logger, lines = new_logger({ name = "app", context = { request_id = "r1" } })
  logger:warning("slow", { ms = 12, a = true })
  self:assert_equal("2001-09-09T01:46:40Z WARNING [app] slow request_id=r1 a=true ms=12\n", lines[1])
end

function T:test_secrets_are_redacted_and_awkward_values_are_quoted_or_escaped()
  local logger, lines = new_logger()
  logger:error("a\nb", { token = log.Secret("tok-123"), note = "x y", nested = {} })
  self:assert_nil(lines[1]:find("tok-123", 1, true))
  self:assert_equal(1, select(2, lines[1]:gsub("\n", "")))
  self:assert_not_nil(lines[1]:find('note="x y"', 1, true))
  self:assert_not_nil(lines[1]:find("token=[redacted]", 1, true))
  self:assert_not_nil(lines[1]:find("nested={...}", 1, true))
end

function T:test_output_must_be_a_function()
  self:assert_error(function() log.ConsoleSink({}) end)
end

function T:test_control_characters_in_a_key_or_a_logger_name_cannot_forge_a_line()
  local lines = {}
  local logger = log.Logger({
    name = "a\nb", clock = function() return 0 end,
    sinks = { log.ConsoleSink({ output = function(line) lines[#lines + 1] = line end }) },
  })
  logger:informational("hi", { ["k\n1970-01-01T00:00:00Z ALERT forged"] = 1 })
  self:assert_equal(1, select(2, lines[1]:gsub("\n", "")))
  self:assert_not_nil(lines[1]:find("\\x0a", 1, true))
end

return T
