---@diagnostic disable: need-check-nil, param-type-mismatch, undefined-field
-- Secrets are wrapped and never rendered (configuration.md, "Secrets"; invariant "secrets are never logged").
local test = require("harness.test")
local config = require("hecate.config")
local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or "."
local fixture = dofile(here .. "/../support/fixture.lua")
local T = test.Case("ConfigSecretsTest")

local VALUE = "s3cr3t-value-9f2"

local function options(extra)
  local o = { secrets = { "database.password" } }
  for k, v in pairs(extra or {}) do o[k] = v end
  return o
end

function T:test_secret_is_wrapped_and_revealed_only_on_demand()
  local configuration = fixture.load({ env = { HECATE_DATABASE__PASSWORD = VALUE }, options = options() })
  local secret = configuration:get("database.password")
  self:assert_equal("[redacted]", tostring(secret))
  self:assert_equal(VALUE, secret:reveal())
  self:assert_equal("[redacted]", tostring(configuration:values().database.password))
end

function T:test_absent_secret_is_nil()
  self:assert_nil(fixture.load({ options = options() }):get("database.password"))
end

function T:test_describe_never_prints_the_value()
  local configuration = fixture.load({ env = { HECATE_DATABASE__PASSWORD = VALUE }, options = options() })
  local text = configuration:describe()
  self:assert_nil(text:find(VALUE, 1, true))
  self:assert_true(text:find("database.password = [redacted] (environment variable HECATE_DATABASE__PASSWORD)", 1, true) ~= nil, text)
  self:assert_true(text:find("database.port = 5432 (schema default)", 1, true) ~= nil, text)
end

function T:test_diagnostics_never_print_the_value()
  local err = fixture.failure({
    env = { HECATE_DATABASE__PASSWORD = VALUE },
    options = options({ properties = { database = require("hecate.schema").object({
      password = require("hecate.schema").string({ min_length = 100 }),
    }) } }),
    files = { ["config/default.lua"] = "return { database = {} }" },
  })
  self:assert_equal("min_length", err.context.violations[1].code)
  self:assert_nil(tostring(err):find(VALUE, 1, true))
  self:assert_nil(require("hecate.core").Error.__tostring(err):find(VALUE, 1, true))
end

function T:test_custom_wrapper_option_is_used()
  local wrapped
  local configuration = fixture.load({
    env = { HECATE_DATABASE__PASSWORD = VALUE },
    options = options({ wrap_secret = function(value) wrapped = value return { marker = true } end }),
  })
  self:assert_equal(VALUE, wrapped)
  self:assert_true(configuration:get("database.password").marker)
end

function T:test_loaded_log_module_is_used_without_a_dependency()
  local Fake = setmetatable({}, { __call = function(_, value) return { fake = value } end })
  local previous = package.loaded["hecate.log"]
  package.loaded["hecate.log"] = { Secret = Fake }
  local ok, configuration = pcall(fixture.load, { env = { HECATE_DATABASE__PASSWORD = VALUE }, options = options() })
  package.loaded["hecate.log"] = previous
  self:assert_true(ok)
  self:assert_equal(VALUE, configuration:get("database.password").fake)
end

function T:test_secret_file_strips_one_line_end()
  local function load_with(text)
    return fixture.load({
      files = { ["/run/secrets/HECATE_DATABASE__PASSWORD"] = text },
      options = options({ secrets_directory = "/run/secrets" }),
    }):get("database.password"):reveal()
  end
  self:assert_equal("abc", load_with("abc\n"))
  self:assert_equal("abc", load_with("abc\r\n"))
  self:assert_equal("abc\n", load_with("abc\n\n"))
  self:assert_equal("abc", load_with("abc"))
end

function T:test_name_file_variable_names_the_file()
  local configuration = fixture.load({
    env = { HECATE_DATABASE__PASSWORD_FILE = "/mnt/pw" },
    files = { ["/mnt/pw"] = VALUE .. "\n" },
    options = options(),
  })
  self:assert_equal(VALUE, configuration:get("database.password"):reveal())
  self:assert_equal("secret file /mnt/pw", configuration:source("database.password"))
end

function T:test_unreadable_named_secret_file_is_an_error()
  local err = fixture.failure({ env = { HECATE_DATABASE__PASSWORD_FILE = "/mnt/missing" }, options = options() })
  self:assert_equal("hecate.core.ConfigurationError", err.code)
  self:assert_equal("/mnt/missing", err.context.file)
end

function T:test_secret_files_exist_for_secret_keys_only()
  local configuration = fixture.load({
    files = { ["/run/secrets/HECATE_DATABASE__HOST"] = "evil" },
    env = { HECATE_DATABASE__HOST_FILE = "/run/secrets/HECATE_DATABASE__HOST" },
    options = options({ secrets_directory = "/run/secrets" }),
  })
  self:assert_equal("localhost", configuration:get("database.host"))
end

function T:test_secret_from_a_config_file_is_wrapped_too()
  local configuration = fixture.load({
    files = { ["config/default.lua"] = "return { database = { password = 'dev' } }" },
    options = options(),
  })
  self:assert_equal("[redacted]", tostring(configuration:get("database.password")))
end

function T:test_fallback_secret_class_has_the_interface()
  local secret = config.Secret(VALUE)
  self:assert_equal("[redacted]", tostring(secret))
  self:assert_equal(VALUE, secret:reveal())
  self:assert_equal("[redacted]", config.Secret.REDACTED)
end

local function without_value(self, err)
  self:assert_nil(tostring(err):find(VALUE, 1, true), tostring(err))
  for _, violation in ipairs(err.context.violations or {}) do
    for _, field in pairs(violation) do self:assert_nil(tostring(field):find(VALUE, 1, true), tostring(field)) end
  end
end

function T:test_pattern_and_enum_violations_of_a_secret_do_not_print_the_value()
  local schema = require("hecate.schema")
  for _, property in ipairs({ schema.string({ pattern = "^[0-9]+$" }), schema.enumeration({ "alpha", "beta" }) }) do
    local err = fixture.failure({
      env = { HECATE_DATABASE__PASSWORD = VALUE },
      options = options({ properties = { database = schema.object({ password = property }) } }),
    })
    self:assert_equal(1, #err.context.violations)
    without_value(self, err)
    self:assert_equal("database.password", err.context.violations[1].path)
  end
end

function T:test_type_violation_of_a_secret_in_a_file_does_not_print_the_value()
  local schema = require("hecate.schema")
  local err = fixture.failure({
    files = { ["config/default.lua"] = "return { database = { password = { '" .. VALUE .. "' } } }" },
    options = options({ properties = { database = schema.object({ password = schema.string() }) } }),
  })
  without_value(self, err)
end

function T:test_coercion_failure_of_a_secret_integer_does_not_print_the_value()
  local schema = require("hecate.schema")
  local err = fixture.failure({
    env = { HECATE_PIN = VALUE },
    options = { properties = { pin = schema.integer() }, secrets = { "pin" } },
  })
  self:assert_equal(1, #err.context.violations)
  without_value(self, err)
  local from_file = fixture.failure({
    files = { ["/mnt/pin"] = VALUE .. "\n" }, env = { HECATE_PIN_FILE = "/mnt/pin" },
    options = { properties = { pin = schema.integer() }, secrets = { "pin" } },
  })
  without_value(self, from_file)
end

function T:test_syntax_error_of_a_file_does_not_print_the_value()
  -- The Lua message ends with `near '<token>'`, and the token is text of the file.
  local token = "s3cr3tvalue9f2"
  local text = "return { password = 'x' " .. token .. " }"
  local plain = select(2, load(text, "@config/default.lua", "t", {}))
  self:assert_true(plain:find(token, 1, true) ~= nil, "the fixture must reproduce the leak: " .. plain)
  local err = fixture.failure({ files = { ["config/default.lua"] = text } })
  self:assert_nil(tostring(err):find(token, 1, true), tostring(err))
  self:assert_true(tostring(err):find("config/default.lua:1:", 1, true) ~= nil, tostring(err))
  self:assert_equal("config/default.lua", err.context.file)
end

-- Documented in website/en/how-to/before-going-to-production.md (Secrets).
-- `describe()` prints an unlisted key in full and a listed one as `[redacted]`. A validation error quotes neither value:
-- the messages of `hecate.schema` never contain the value, so the only difference is that the message of a violation
-- at a listed key is replaced, while an unlisted key keeps the message of its schema.
function T:test_an_unlisted_key_is_printed_in_full_and_a_listed_one_never()
  local schema = require("hecate.schema")
  local PLAIN = "plain-host-value-7c1"
  local configuration = fixture.load({
    env = { HECATE_DATABASE__HOST = PLAIN, HECATE_DATABASE__PASSWORD = VALUE },
    options = options(),
  })
  local text = configuration:describe()
  self:assert_true(text:find(('database.host = "%s" (environment variable HECATE_DATABASE__HOST)'):format(PLAIN), 1, true) ~= nil, text)
  self:assert_true(text:find("database.password = [redacted] (environment variable HECATE_DATABASE__PASSWORD)", 1, true) ~= nil, text)
  self:assert_nil(text:find(VALUE, 1, true), text)

  local err = fixture.failure({
    env = { HECATE_DATABASE__HOST = PLAIN, HECATE_DATABASE__PASSWORD = VALUE },
    options = options({ properties = { database = schema.object({
      host = schema.string({ pattern = "^[0-9]+$" }),
      password = schema.string({ pattern = "^[0-9]+$" }),
    }) } }),
  })
  self:assert_equal(2, #err.context.violations)
  local by_path = {}
  for _, violation in ipairs(err.context.violations) do by_path[violation.path] = violation end
  self:assert_equal("pattern", by_path["database.host"].code)
  self:assert_equal("the string does not match the pattern", by_path["database.host"].message)
  self:assert_equal("pattern", by_path["database.password"].code)
  self:assert_equal("the value of a secret key does not conform to its schema (it is not shown)",
    by_path["database.password"].message)
  local message = tostring(err)
  self:assert_nil(message:find(VALUE, 1, true), message)
  -- Real behaviour: the schema message does not quote the value of the unlisted key either.
  self:assert_nil(message:find(PLAIN, 1, true), message)
end

-- Documented in website/en/how-to/before-going-to-production.md (Logging and redaction).
function T:test_without_wrap_secret_the_loaded_log_secret_is_used_else_the_config_secret()
  local core = require("hecate.core")
  local FakeSecret = core.class("FakeLogSecret")
  function FakeSecret:init(value) self.value = value end
  FakeSecret = core.finalise(FakeSecret)
  local previous = package.loaded["hecate.log"]
  local ok, failure = pcall(function()
    package.loaded["hecate.log"] = { Secret = FakeSecret }
    local with_log = fixture.load({ env = { HECATE_DATABASE__PASSWORD = VALUE }, options = options() })
    local secret = with_log:get("database.password")
    self:assert_true(core.is_instance_of(secret, FakeSecret), tostring(secret))
    self:assert_false(core.is_instance_of(secret, config.Secret))
    self:assert_equal(VALUE, secret.value)

    package.loaded["hecate.log"] = nil
    local without_log = fixture.load({ env = { HECATE_DATABASE__PASSWORD = VALUE }, options = options() })
    local fallback = without_log:get("database.password")
    self:assert_true(core.is_instance_of(fallback, config.Secret), tostring(fallback))
    self:assert_equal("[redacted]", tostring(fallback))
    self:assert_equal(VALUE, fallback:reveal())
  end)
  package.loaded["hecate.log"] = previous
  if not ok then error(failure, 0) end
end

return T
