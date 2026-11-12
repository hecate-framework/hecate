---@diagnostic disable: missing-fields, param-type-mismatch, assign-type-mismatch  -- the tests pass invalid options and arguments on purpose
local test = require("harness.test")
local json = require("hecate.json")
local log = require("hecate.log")
local T = test.Case("JsonLinesSinkTest")

local function new_logger(options)
  local lines = {}
  local sink = log.JsonLinesSink({ output = function(line) lines[#lines + 1] = line end })
  options = options or {}
  options.sinks = { sink }
  options.clock = options.clock or function() return 1000000000 end
  return log.Logger(options), lines
end

function T:test_one_record_is_one_line_ending_with_a_newline()
  local logger, lines = new_logger()
  logger:error("a\nb", { n = 1 })
  self:assert_equal(1, #lines)
  self:assert_equal("\n", lines[1]:sub(-1))
  self:assert_nil(lines[1]:sub(1, -2):find("\n", 1, true))
end

function T:test_the_line_holds_severity_code_message_timestamp_context_and_fields()
  local logger, lines = new_logger({ name = "app", context = { request_id = "r" } })
  logger:warning("slow", { ms = 12 })
  local object = json.decode(lines[1])
  self:assert_equal("warning", object.severity)
  self:assert_equal(4, object.code)
  self:assert_equal("slow", object.message)
  self:assert_equal("2001-09-09T01:46:40Z", object.timestamp)
  self:assert_equal("app", object.logger)
  self:assert_equal("r", object.context.request_id)
  self:assert_equal(12, object.fields.ms)
end

function T:test_a_fractional_timestamp_keeps_milliseconds()
  local logger, lines = new_logger({ clock = function() return 1000000000.25 end })
  logger:error("x")
  self:assert_equal("2001-09-09T01:46:40.250Z", json.decode(lines[1]).timestamp)
end

function T:test_a_secret_is_never_rendered_at_any_depth()
  local logger, lines = new_logger({ context = { token = log.Secret("tok-123") } })
  logger:error("login", { password = log.Secret("hunter2"), nested = { list = { log.Secret("deep") } } })
  self:assert_nil(lines[1]:find("hunter2", 1, true))
  self:assert_nil(lines[1]:find("tok-123", 1, true))
  self:assert_nil(lines[1]:find("deep", 1, true))
  local object = json.decode(lines[1])
  self:assert_equal("[redacted]", object.fields.password)
  self:assert_equal("[redacted]", object.fields.nested.list[1])
  self:assert_equal("[redacted]", object.context.token)
end

function T:test_a_value_that_cannot_be_encoded_still_yields_a_valid_line()
  local logger, lines = new_logger()
  logger:error("bad", { callback = function() end })
  local object = json.decode(lines[1])
  self:assert_equal("bad", object.message)
  self:assert_not_nil(object.encoding_error)
end

function T:test_a_cyclic_field_does_not_loop()
  local logger, lines = new_logger()
  local cycle = {}
  cycle.self = cycle
  logger:error("cycle", { cycle = cycle })
  self:assert_equal("cycle", json.decode(lines[1]).message)
end

function T:test_the_output_is_required()
  self:assert_error(function() log.JsonLinesSink({}) end)
end

function T:test_a_message_that_is_not_utf8_is_kept_with_its_bytes_escaped()
  local logger, lines = new_logger()
  logger:informational("bad \xff byte", { a = 1 })
  self:assert_equal(1, #lines)
  self:assert_equal(0, logger:failures())
  local object = json.decode(lines[1])
  self:assert_equal("bad \\xff byte", object.message)
  self:assert_not_nil(object.encoding_error)
end

-- A table nested `levels` deep below the fields, holding a secret at its bottom.
local function nested_secret(levels)
  local leaf = { password = log.Secret("hunter2") }
  for _ = 1, levels do leaf = { child = leaf } end
  return leaf
end

function T:test_a_secret_is_never_rendered_around_the_depth_limit()
  for _, levels in ipairs({ 14, 15, 16, 17, 40 }) do
    local logger, lines = new_logger()
    logger:error("deep", nested_secret(levels))
    self:assert_nil(lines[1]:find("hunter2", 1, true), "secret rendered at " .. levels .. " levels")
  end
end

function T:test_a_table_deeper_than_the_limit_is_truncated_and_a_shallower_one_is_redacted()
  local logger, lines = new_logger()
  logger:error("shallow", nested_secret(14))
  self:assert_not_nil(lines[1]:find("[redacted]", 1, true))
  self:assert_nil(lines[1]:find("[truncated]", 1, true))
  logger:error("deep", nested_secret(17))
  self:assert_not_nil(lines[2]:find("[truncated]", 1, true))
end

-- Documented in website/en/how-to/before-going-to-production.md (Redaction does not read free text).
function T:test_a_table_with_a_metatable_is_written_as_it_is()
  local logger, lines = new_logger({ redact = { "authorization" } })
  logger:error("request", { fields = setmetatable({ authorization = "x" }, {}) })
  local object = json.decode(lines[1])
  self:assert_nil(object.encoding_error)
  self:assert_equal("x", object.fields.fields.authorization)
end

return T
