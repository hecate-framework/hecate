---@diagnostic disable: missing-fields, param-type-mismatch  -- the tests pass invalid arguments on purpose
local test = require("harness.test")
local log = require("hecate.log")
local T = test.Case("DefaultLoggerTest")

function T:teardown() log.set_default(nil) end

--- Runs `fn` with the standard error stream replaced by a buffer; returns what was written to it.
local function capture_stderr(fn)
  local original, written = io.stderr, {}
  io.stderr = { write = function(_, text) written[#written + 1] = text end }
  local ok, err = pcall(fn)
  io.stderr = original
  if not ok then error(err, 0) end
  return table.concat(written)
end

function T:test_default_is_one_shared_logger_at_informational()
  local a = log.default()
  self:assert_true(a == log.default())
  self:assert_true(a:severity() == log.Severity.informational)
  self:assert_true(a:is_enabled(log.Severity.error))
  self:assert_false(a:is_enabled(log.Severity.debug))
end

function T:test_set_default_replaces_it_and_nil_restores_the_lazy_one()
  local mine = log.Logger({ name = "mine" })
  log.set_default(mine)
  self:assert_true(log.default() == mine)
  log.set_default(nil)
  self:assert_false(log.default() == mine)
end

function T:test_set_default_refuses_a_value_without_log_methods()
  self:assert_error(function() log.set_default({}) end)
end

function T:test_default_redacts_secret_field_names_case_insensitively()
  local out = capture_stderr(function()
    log.default():error("login", { password = "x", Authorization = "Bearer y", user = "ana" })
  end)
  self:assert_nil(out:find("Bearer y", 1, true))
  self:assert_nil(out:find("password=x", 1, true))
  self:assert_not_nil(out:find("password=[redacted]", 1, true))
  self:assert_not_nil(out:find("Authorization=[redacted]", 1, true))
  self:assert_not_nil(out:find("user=ana", 1, true))
end

function T:test_default_redacts_nested_fields()
  local sink = log.MemorySink()
  local logger = log.default()
  logger:add_sink(sink)
  capture_stderr(function()
    logger:error("request", { headers = { cookie = "c-secret-value", accept = "json" } })
  end)
  local headers = sink:records()[1].fields.headers
  self:assert_equal("[redacted]", tostring(headers.cookie))
  self:assert_equal("json", headers.accept)
end

function T:test_redaction_is_by_field_name_and_never_covers_free_text()
  local out = capture_stderr(function() log.default():error("password=hunter2 failed") end)
  self:assert_not_nil(out:find("password=hunter2", 1, true))
end

function T:test_a_plain_logger_has_no_implicit_redact()
  local sink = log.MemorySink()
  log.Logger({ sinks = { sink } }):error("x", { password = "plain" })
  self:assert_equal("plain", sink:records()[1].fields.password)
end

function T:test_default_redact_lists_the_tier_1_names()
  local names = {}
  for _, name in ipairs(log.DEFAULT_REDACT) do names[name] = true end
  for _, name in ipairs({ "password", "authorization", "cookie", "set-cookie", "access_token", "api_key", "csrf" }) do
    self:assert_true(names[name], name)
  end
end

function T:test_default_does_not_mutate_default_redact()
  local before = #log.DEFAULT_REDACT
  local first = log.DEFAULT_REDACT[1]
  capture_stderr(function() log.default():error("x", { password = "p" }) end)
  self:assert_equal(before, #log.DEFAULT_REDACT)
  self:assert_equal(first, log.DEFAULT_REDACT[1])
end

function T:test_a_user_extends_default_redact_with_table_move()
  local names = table.move(log.DEFAULT_REDACT, 1, #log.DEFAULT_REDACT, 1, {})
  names[#names + 1] = "ssn"
  local sink = log.MemorySink()
  log.Logger({ sinks = { sink }, redact = names }):error("x", { ssn = "1", password = "2" })
  self:assert_equal("[redacted]", tostring(sink:records()[1].fields.ssn))
  self:assert_equal("[redacted]", tostring(sink:records()[1].fields.password))
end

return T
