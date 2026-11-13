---@diagnostic disable: missing-fields
-- `kernel.load_configuration` reads the environment through `reactor.getenv` (OQ-124): UTF-8 on Windows.
local test = require("harness.test")
local kernel = require("hecate.kernel")
local reactor = require("hecate.reactor")
local schema = require("hecate.schema")
local T = test.Case("LoadConfigurationTest")

local function options(extra)
  local result = {
    properties = { greeting = schema.default(schema.string(), "none") },
    environment = "development",
    read_file = function(path)
      if path == "config/development.lua" then return "return {}" end
      return nil, "no such file: " .. path, true
    end,
  }
  for key, value in pairs(extra or {}) do result[key] = value end
  return result
end

--- Replaces `reactor.getenv` by `reader` while `fn` runs.
local function with_reader(reader, fn)
  local original = reactor.getenv
  reactor.getenv = reader
  local ok, result = pcall(fn)
  reactor.getenv = original
  if not ok then error(result, 0) end
  return result
end

function T:test_the_environment_is_read_through_the_reactor()
  local names = {}
  local configuration = with_reader(function(name)
    names[#names + 1] = name
    if name == "HECATE_GREETING" then return "from the reactor" end
  end, function() return kernel.load_configuration(options()) end)
  self:assert_equal("from the reactor", configuration:get("greeting"))
  self:assert_true(#names > 0)
end

function T:test_an_explicit_getenv_wins_over_the_reactor()
  local called = false
  local configuration = with_reader(function() called = true end, function()
    return kernel.load_configuration(options({
      getenv = function(name) if name == "HECATE_GREETING" then return "explicit" end end,
    }))
  end)
  self:assert_equal("explicit", configuration:get("greeting"))
  self:assert_false(called, "the reactor reader is not used when the caller gives one")
end

function T:test_a_non_ascii_value_arrives_as_utf8_on_windows()
  if package.config:sub(1, 1) ~= "\\" then return end -- Windows only: elsewhere the bytes are passed through
  local uv = require("luv")
  local value = "caf\u{E9} \u{65E5}\u{672C}"
  uv.os_setenv("HECATE_GREETING", value)
  local ok, result = pcall(kernel.load_configuration, options())
  uv.os_unsetenv("HECATE_GREETING")
  self:assert_true(ok, tostring(result))
  self:assert_equal(value, result:get("greeting"))
end

return T
