-- Option validation of hecate.net.tls: allow-lists, types and messages. Validation happens in Lua
-- before the native module is touched, so these tests need no native build.
---@diagnostic disable: param-type-mismatch, assign-type-mismatch  -- the tests pass invalid arguments on purpose
local test = require("harness.test")
local core = require("hecate.core")
local net = require("hecate.net")
local T = test.Case("NetTlsOptionsTest")

local PEM = "-----BEGIN CERTIFICATE-----\n-----END CERTIFICATE-----\n"
local KEY = "-----BEGIN PRIVATE KEY-----\n-----END PRIVATE KEY-----\n"

--- Calls `fn`, checks that it raises an `ArgumentError` and returns the message.
local function argument_error(self, fn)
  local err = self:assert_error(fn)
  self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
  self:assert_false(core.is_instance_of(err, net.TlsError), tostring(err))
  return tostring(err)
end

local function contains(self, text, needle)
  self:assert_true(text:find(needle, 1, true) ~= nil, ("%q not found in %q"):format(needle, text))
end

local VERIFICATION_SWITCHES = { "verify", "insecure", "skip_verify", "danger_accept_invalid_certs" }

local ENTRY_POINTS = {
  client_config = function(extra)
    local options = { ca_pem = PEM }
    for k, v in pairs(extra) do options[k] = v end
    return function() net.tls.client_config(options) end
  end,
  server_config = function(extra)
    local options = { cert_pem = PEM, key_pem = KEY }
    for k, v in pairs(extra) do options[k] = v end
    return function() net.tls.server_config(options) end
  end,
  connect_tls = function(extra)
    local options = { ca_pem = PEM }
    for k, v in pairs(extra) do options[k] = v end
    return function() net.connect_tls("127.0.0.1", 1, options) end
  end,
}

function T:test_verification_switches_are_rejected_everywhere()
  for name, build in pairs(ENTRY_POINTS) do
    for _, key in ipairs(VERIFICATION_SWITCHES) do
      local message = argument_error(self, build({ [key] = false }))
      contains(self, message, name)
      contains(self, message, "unknown option " .. key)
      contains(self, message, "verification cannot be disabled")
    end
  end
end

function T:test_typos_are_rejected_and_the_valid_options_are_listed()
  local message = argument_error(self, ENTRY_POINTS.client_config({ system_root = false }))
  contains(self, message, "unknown option system_root")
  contains(self, message, "system_roots")
  message = argument_error(self, ENTRY_POINTS.server_config({ cert = PEM }))
  contains(self, message, "unknown option cert")
  contains(self, message, "client_ca_pem")
  message = argument_error(self, ENTRY_POINTS.connect_tls({ server_nam = "x" }))
  contains(self, message, "unknown option server_nam")
  contains(self, message, "handshake_timeout")
end

function T:test_a_client_option_given_to_a_server_says_which_kind_it_belongs_to()
  for _, key in ipairs({ "ca_pem", "system_roots" }) do
    local message = argument_error(self, ENTRY_POINTS.server_config({ [key] = true }))
    contains(self, message, "ca_pem and system_roots are client options; use client_ca_pem to require client certificates")
  end
end

function T:test_a_server_option_given_to_a_client_says_which_kind_it_belongs_to()
  local message = argument_error(self, ENTRY_POINTS.client_config({ client_ca_pem = PEM }))
  contains(self, message, "client_ca_pem is a server option")
  message = argument_error(self, ENTRY_POINTS.connect_tls({ client_ca_pem = PEM }))
  contains(self, message, "client_ca_pem is a server option")
end

function T:test_non_string_keys_are_rejected()
  local message = argument_error(self, function() net.tls.client_config({ [1] = "x" }) end)
  contains(self, message, "unknown option 1")
end

function T:test_alpn_is_validated_in_lua()
  local bad = {
    "http/1.1", -- a string instead of a list
    {},
    { "" },
    { "h2", 5 },
    { ("x"):rep(256) },
    { name = "h2" },
    { "h2", nil, "http/1.1" },
  }
  for name, build in pairs(ENTRY_POINTS) do
    for _, alpn in ipairs(bad) do
      local message = argument_error(self, build({ alpn = alpn }))
      contains(self, message, name)
      contains(self, message, "alpn")
    end
  end
  argument_error(self, function() net.tls.server_config({ cert_pem = PEM, key_pem = KEY, alpn = "h2" }) end)
end

function T:test_pem_options_must_be_strings()
  contains(self, argument_error(self, ENTRY_POINTS.client_config({ ca_pem = 5 })), "ca_pem")
  contains(self, argument_error(self, ENTRY_POINTS.client_config({ cert_pem = 5, key_pem = KEY })), "cert_pem")
  contains(self, argument_error(self, ENTRY_POINTS.server_config({ client_ca_pem = 5 })), "client_ca_pem")
  contains(self, argument_error(self, ENTRY_POINTS.server_config({ key_pem = {} })), "key_pem")
end

function T:test_client_certificate_and_key_come_together()
  contains(self, argument_error(self, ENTRY_POINTS.client_config({ cert_pem = PEM })), "cert_pem and key_pem")
  contains(self, argument_error(self, ENTRY_POINTS.client_config({ key_pem = KEY })), "cert_pem and key_pem")
end

function T:test_transport_options_are_validated_by_connect_tls_before_anything_else()
  local cases = {
    { nodelay = "yes" }, { keepalive = 1 }, { keepalive_delay = 0 }, { keepalive_delay = "10" },
    { family = "ipx" }, { backlog = 5 }, { reuseport = true },
  }
  for _, extra in ipairs(cases) do
    local message = argument_error(self, ENTRY_POINTS.connect_tls(extra))
    contains(self, message, "connect_tls")
  end
end

function T:test_connect_tls_validates_host_and_port()
  contains(self, argument_error(self, function() net.connect_tls("", 443) end), "connect_tls")
  contains(self, argument_error(self, function() net.connect_tls("example.org", "443") end), "connect_tls")
  contains(self, argument_error(self, function() net.connect_tls("example.org", 70000) end), "connect_tls")
end

function T:test_handshake_timeout_must_be_a_positive_number()
  local stream = { read = function() end, write = function() end, close = function() end }
  for _, value in ipairs({ 0, -1, "5", true, math.huge, 0 / 0 }) do
    local message = argument_error(self, ENTRY_POINTS.connect_tls({ handshake_timeout = value }))
    contains(self, message, "handshake_timeout")
    -- tls.connect and tls.accept take the same option (a userdata stands in for the configuration).
    message = argument_error(self, function() net.tls.connect(stream, "localhost", io.stdout, { handshake_timeout = value }) end)
    contains(self, message, "handshake_timeout")
  end
  contains(self, argument_error(self, function() net.tls.accept(stream, io.stdout, { handshake_timeout = 0 }) end), "handshake_timeout")
end

function T:test_tls_connect_and_accept_reject_unknown_options_and_non_streams()
  local stream = { read = function() end, write = function() end, close = function() end }
  contains(self, argument_error(self, function() net.tls.connect(stream, "localhost", io.stdout, { verify = false }) end), "unknown option verify")
  contains(self, argument_error(self, function() net.tls.accept(stream, io.stdout, { timeout = 1 }) end), "unknown option timeout")
  for _, bad in ipairs({ "text", {}, { read = function() end } }) do
    contains(self, argument_error(self, function() net.tls.connect(bad, "localhost", io.stdout) end), "stream")
    contains(self, argument_error(self, function() net.tls.accept(bad, io.stdout) end), "stream")
  end
  contains(self, argument_error(self, function() net.tls.accept(nil, io.stdout) end), "stream")
end

function T:test_tls_failures_carry_the_reason_derived_from_a_native_kind()
  local errors = require("hecate.net.errors")
  local err = errors.tls_failure({ kind = "name_mismatch", message = "something unrecognisable" })
  self:assert_equal("name_mismatch", err.context.reason)
  self:assert_equal("something unrecognisable", err.message)
  err = errors.tls_failure({ kind = "no_such_kind", message = "certificate expired" }) -- unknown kind: the text fallback
  self:assert_equal("expired", err.context.reason)
  err = errors.tls_failure("received fatal alert")
  self:assert_nil(err.context.reason)
end

return T
