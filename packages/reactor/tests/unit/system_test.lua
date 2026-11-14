local test = require("harness.test")
local core = require("hecate.core")
local reactor = require("hecate.reactor")
local T = test.Case("SystemTest")

function T:test_system_name_is_a_known_name()
  local name = reactor.system_name()
  self:assert_equal("string", type(name))
  self:assert_true(name ~= "")
  local windows = package.config:sub(1, 1) == "\\"
  if windows then self:assert_true(name:find("^Windows") ~= nil) end
end

function T:test_available_parallelism_is_a_positive_integer()
  local count = reactor.available_parallelism()
  self:assert_equal("integer", math.type(count))
  self:assert_true(count >= 1)
end

function T:test_getenv_reads_a_variable_and_answers_nil_when_it_is_unset()
  local uv = require("luv")
  local name = "HECATE_REACTOR_GETENV_TEST"
  uv.os_setenv(name, "value=1")
  self:assert_equal("value=1", reactor.getenv(name))
  -- On POSIX both read the same environment. On Windows `uv.os_setenv` writes the wide environment of the process,
  -- which the C runtime copy read by `os.getenv` does not see: the very reason `reactor.getenv` exists (OQ-124).
  if package.config:sub(1, 1) == "/" then
    self:assert_equal(os.getenv(name), reactor.getenv(name), "the same value as os.getenv")
  end
  uv.os_unsetenv(name)
  self:assert_nil(reactor.getenv(name))
  self:assert_nil(reactor.getenv(""))
end

function T:test_getenv_reads_a_long_value_whole()
  local uv = require("luv")
  local name = "HECATE_REACTOR_GETENV_LONG"
  local value = ("0123456789"):rep(2000)
  uv.os_setenv(name, value)
  self:assert_equal(value, reactor.getenv(name))
  uv.os_unsetenv(name)
end

function T:test_getenv_rejects_a_name_that_is_not_a_string()
  ---@diagnostic disable-next-line: param-type-mismatch  -- a wrong argument on purpose
  local err = self:assert_error(function() reactor.getenv(42) end)
  self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
end

function T:test_getenv_reads_a_non_ascii_value_as_utf8_on_windows()
  if package.config:sub(1, 1) ~= "\\" then return end -- Windows only: elsewhere the bytes are passed through
  local uv = require("luv")
  local name = "HECATE_REACTOR_GETENV_UTF8"
  local value = "caf\u{E9} \u{65E5}\u{672C}"
  uv.os_setenv(name, value)
  self:assert_equal(value, reactor.getenv(name))
  uv.os_unsetenv(name)
end

function T:test_random_answers_n_bytes()
  for _, n in ipairs({ 0, 1, 16, 1000 }) do
    local bytes = reactor.random(n)
    self:assert_equal("string", type(bytes))
    self:assert_equal(n, #bytes)
  end
end

function T:test_random_answers_different_bytes_each_time()
  self:assert_true(reactor.random(16) ~= reactor.random(16))
end

function T:test_random_needs_no_running_reactor_and_does_not_suspend()
  local co = coroutine.wrap(function() return #reactor.random(8) end)
  self:assert_equal(8, co())
end

function T:test_random_refuses_a_count_that_is_not_a_non_negative_integer()
  for _, bad in ipairs({ -1, 1.5, "8", true, 1 << 30 }) do
    local err = self:assert_error(function() reactor.random(bad) end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
  end
  local err = self:assert_error(function()
    ---@diagnostic disable-next-line: missing-parameter
    reactor.random()
  end)
  self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
end

return T
