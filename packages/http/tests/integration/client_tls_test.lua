---@diagnostic disable: missing-fields, param-type-mismatch, need-check-nil  -- the tests pass invalid arguments on purpose
-- The client over TLS against the in-repo server, with the local test CA of packages/net/tests/fixtures.
local test = require("harness.test")
local core = require("hecate.core")
local reactor = require("hecate.reactor")
local net = require("hecate.net")
local http = require("hecate.http")
local T = test.Case("ClientTlsTest")

local available, reason = net.tls.available()
if not available then
  function T:test_skipped_native_module_not_built()
    if os.getenv("HECATE_REQUIRE_TLS") == "1" then self:fail("TLS tests cannot run: " .. tostring(reason)) end
    print("# SKIP hecate.http client TLS tests: " .. tostring(reason))
  end
  return T
end

local function fixture(name)
  local path = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):gsub("/[^/]*$", "") .. "/../../../net/tests/fixtures/" .. name
  local f = assert(io.open(path, "rb"), "missing fixture " .. path)
  local s = f:read("a")
  f:close()
  return s
end

local CA = fixture("ca.pem")
local TLS = { cert_pem = fixture("server.pem"), key_pem = fixture("server.key") }
local Response = http.Response

local function with_https(self, handler, fn)
  local before = reactor.Reactor.open_handles()
  reactor.run(function()
    local server = http.Server(handler, { port = 0, tls = TLS })
    local listener = server:listen()
    local serving = reactor.fork(server.serve, server, listener)
    local ok, err = pcall(reactor.deadline, 25, fn, listener:local_address().port)
    server:shutdown(2)
    serving:value()
    if not ok then error(err, 0) end
  end)
  self:assert_equal(before, reactor.Reactor.open_handles(), "libuv handles left open")
end

function T:test_https_request_with_a_private_ca_reuses_the_connection()
  with_https(self, function(request) return Response(200, { content = tostring(request:peer_address().port) }) end, function(port)
    local client <close> = http.Client({ tls = { ca_pem = CA, system_roots = false } })
    local url = "https://127.0.0.1:" .. port .. "/"
    local first = client:get(url):read_content()
    local second = client:get(url):read_content()
    self:assert_equal(first, second, "one TLS connection")
  end)
end

function T:test_an_untrusted_server_certificate_is_a_tls_error()
  with_https(self, function() return Response(200) end, function(port)
    local client <close> = http.Client({ tls = { system_roots = false, ca_pem = fixture("other_ca.pem") } })
    local err = self:assert_error(function() client:get("https://127.0.0.1:" .. port .. "/") end)
    self:assert_true(core.is_instance_of(err, net.TlsError), tostring(err))
  end)
end

function T:test_a_redirect_from_https_to_http_is_refused_unless_allowed()
  with_https(self, function()
    return Response(302, { fields = http.Fields({ { "Location", "http://127.0.0.1:1/" } }) })
  end, function(port)
    local client <close> = http.Client({ tls = { ca_pem = CA, system_roots = false } })
    local err = self:assert_error(function() client:get("https://127.0.0.1:" .. port .. "/") end)
    self:assert_true(core.is_instance_of(err, core.ProtocolError))
    self:assert_equal("downgrade", err.context.reason)
  end)
end

return T
