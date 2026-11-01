-- The native TLS module is the security boundary: it must refuse by itself what the Lua layer refuses, because it
-- can be called without that layer. Needs the native module (see tls_test.lua).
local test = require("harness.test")
local net = require("hecate.net")
local T = test.Case("NetTlsNativeTest")

local available, reason = net.tls.available()
if not available then
  function T:test_skipped_native_module_not_built()
    if os.getenv("HECATE_REQUIRE_TLS") == "1" then
      self:fail("hecate.net native TLS tests cannot run: " .. tostring(reason))
    end
    print("# SKIP hecate.net native TLS tests: " .. tostring(reason))
  end
  return T
end

local native = require("hecate.net.tls_native")

local function fixture(name)
  local path = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):gsub("/[^/]*$", "") .. "/../fixtures/" .. name
  local f = assert(io.open(path, "rb"), "missing fixture " .. path)
  local s = f:read("a")
  f:close()
  return s
end

function T:test_a_revocation_list_without_client_anchors_is_refused_not_ignored()
  local ok, err = pcall(native.server_config, {
    cert_pem = fixture("server.pem"), key_pem = fixture("server.key"), client_crl_pem = fixture("revoked.crl.pem"),
  })
  self:assert_false(ok, "a server with revocation lists but no client anchors would check nothing")
  self:assert_true(tostring(err):find("client_crl_pem", 1, true) ~= nil, tostring(err))
  self:assert_true(tostring(err):find("client_ca_pem", 1, true) ~= nil, tostring(err))
end

function T:test_a_revocation_list_with_client_anchors_is_accepted()
  local config = native.server_config({
    cert_pem = fixture("server.pem"), key_pem = fixture("server.key"),
    client_ca_pem = fixture("revocation_ca.pem"), client_crl_pem = fixture("revoked.crl.pem"),
  })
  self:assert_true(config ~= nil)
end

function T:test_a_pem_without_a_revocation_list_is_refused()
  local ok, err = pcall(native.server_config, {
    cert_pem = fixture("server.pem"), key_pem = fixture("server.key"),
    client_ca_pem = fixture("revocation_ca.pem"), client_crl_pem = fixture("ca.pem"),
  })
  self:assert_false(ok)
  self:assert_true(tostring(err):find("revocation list", 1, true) ~= nil, tostring(err))
end

return T
