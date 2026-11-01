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

local function with_https(self, action, fn)
  local before = reactor.Reactor.open_handles()
  reactor.run(function()
    local server = http.Server(action, { port = 0, tls = TLS })
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

function T:test_a_prebuilt_tls_configuration_is_accepted()
  with_https(self, function() return Response(200, { content = "secure" }) end, function(port)
    local config = net.tls.client_config({ ca_pem = CA, system_roots = false, alpn = { "http/1.1" } })
    local client <close> = http.Client({ tls = config })
    self:assert_equal("secure", client:get("https://127.0.0.1:" .. port .. "/"):read_content())
  end)
end

-- Failures and edge cases of the TLS client --------------------------------------------------------------------------

local dir = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):gsub("/[^/]*$", "")
local support = dofile(dir .. "/../fixtures/client.lua")
local run, scripted, read_head, ok = support.run, support.scripted, support.read_head, support.ok

--- A scripted TLS server: `script(tls, index)` runs for each connection after its handshake.
local function tls_scripted(script, files)
  files = files or { cert = "server.pem", key = "server.key" }
  local config = net.tls.server_config({ cert_pem = fixture(files.cert), key_pem = fixture(files.key) })
  local listener = net.listen("127.0.0.1", 0)
  local state = { accepted = 0, port = listener:local_address().port }
  local loop = reactor.fork(function()
    while true do
      local accepted, raw = pcall(listener.accept, listener)
      if not accepted then return end
      state.accepted = state.accepted + 1
      local index = state.accepted
      reactor.fork(function()
        local handshaken, tls = pcall(net.tls.accept, raw, config)
        if not handshaken then return end
        pcall(script, tls, index)
        tls:close()
      end)
    end
  end)
  function state.stop()
    listener:close()
    loop:cancel()
  end
  return state
end

local function https(port, host) return "https://" .. (host or "127.0.0.1") .. ":" .. port .. "/" end

function T:test_a_certificate_for_another_name_is_a_tls_error()
  run(self, function()
    local server = tls_scripted(function(tls) read_head(tls); tls:write(ok("x")) end, { cert = "localhost_only.pem", key = "localhost_only.key" })
    local client <close> = http.Client({ tls = { ca_pem = fixture("variant_ca.pem"), system_roots = false } })
    local err = self:assert_error(function() client:get(https(server.port)) end) -- the certificate names `localhost`, not 127.0.0.1
    self:assert_true(core.is_instance_of(err, net.TlsError), tostring(err))
    self:assert_equal("name_mismatch", err.context.reason)
    self:assert_equal("x", client:get(https(server.port, "localhost")):read_content(), "the right name is accepted")
    server.stop()
  end)
end

function T:test_the_server_name_is_sent_for_a_name_and_not_for_an_address()
  run(self, function()
    local names = {}
    local server = tls_scripted(function(tls)
      names[#names + 1] = tls:requested_server_name() or "none"
      read_head(tls)
      tls:write(ok("x"))
    end)
    local client <close> = http.Client({ tls = { ca_pem = CA, system_roots = false } })
    client:get(https(server.port, "localhost")):read_content()
    client:get(https(server.port, "127.0.0.1")):close()
    self:assert_equal("localhost", names[1])
    self:assert_equal("none", names[2], "an IP address is not a server name (RFC 6066 section 3)")
    server.stop()
  end)
end

function T:test_the_system_trust_store_alone_refuses_the_test_certificate()
  run(self, function()
    local server = tls_scripted(function(tls) read_head(tls); tls:write(ok("x")) end)
    local client <close> = http.Client() -- system roots, no private CA
    local err = self:assert_error(function() client:get(https(server.port)) end)
    self:assert_true(core.is_instance_of(err, net.TlsError), tostring(err))
    server.stop()
  end)
end

function T:test_a_server_that_never_answers_the_handshake_ends_at_the_connect_timeout()
  run(self, function()
    local server = scripted(function(stream) reactor.sleep(30) end) -- accepts and stays silent
    local client <close> = http.Client({ connect_timeout = 0.5, tls = { ca_pem = CA, system_roots = false } })
    local started = reactor.now()
    local err = self:assert_error(function() client:get(https(server.port)) end)
    self:assert_true(core.is_instance_of(err, core.DeadlineExceededError), tostring(err))
    self:assert_true(reactor.now() - started < 10)
    server.stop()
  end)
end

function T:test_an_https_to_https_redirect_to_another_origin_strips_credentials()
  run(self, function()
    local seen = {}
    local target = tls_scripted(function(tls)
      local head = read_head(tls)
      seen[#seen + 1] = head:lower()
      tls:write(ok("target"))
    end)
    local origin = tls_scripted(function(tls)
      read_head(tls)
      tls:write("HTTP/1.1 302 Found\r\nLocation: " .. https(target.port) .. "\r\nContent-Length: 0\r\n\r\n")
    end)
    local client <close> = http.Client({ tls = { ca_pem = CA, system_roots = false } })
    local fields = { Authorization = "Bearer s3cret", Cookie = "sid=1" }
    self:assert_equal("target", client:get(https(origin.port), { fields = fields }):read_content())
    self:assert_nil(seen[1]:find("authorization", 1, true))
    self:assert_nil(seen[1]:find("cookie", 1, true))
    origin.stop(); target.stop()
  end)
end

function T:test_a_pooled_tls_connection_closed_by_the_peer_is_not_reused()
  run(self, function()
    local server = tls_scripted(function(tls)
      read_head(tls)
      tls:write(ok("x"))
      tls:shutdown() -- close_notify, then the end of the connection
    end)
    local client <close> = http.Client({ tls = { ca_pem = CA, system_roots = false } })
    client:get(https(server.port)):read_content()
    reactor.sleep(0.2) -- the close_notify arrives
    client:get(https(server.port)):read_content()
    self:assert_equal(2, server.accepted, "the closed connection was detected and a new one opened")
    server.stop()
  end)
end

function T:test_a_tls_stream_cut_without_close_notify_inside_the_content_is_an_error_not_a_short_body()
  run(self, function()
    local server = tls_scripted(function(tls)
      read_head(tls)
      tls:write("HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\n0123456789") -- then the transport ends: no close_notify
    end)
    local client <close> = http.Client({ tls = { ca_pem = CA, system_roots = false } })
    local response = client:get(https(server.port))
    local err = self:assert_error(function() return response:read_content() end)
    self:assert_true(core.is_instance_of(err, net.TlsError) or core.is_instance_of(err, net.EndOfStreamError), tostring(err))
    server.stop()
  end)
end

function T:test_the_host_field_of_https_carries_the_port_unless_it_is_443()
  run(self, function()
    local heads = {}
    local server = tls_scripted(function(tls)
      heads[#heads + 1] = read_head(tls)
      tls:write(ok("x"))
    end)
    local client <close> = http.Client({ tls = { ca_pem = CA, system_roots = false } })
    client:get(https(server.port)):read_content()
    self:assert_not_nil(heads[1]:find("Host: 127.0.0.1:" .. server.port .. "\r\n", 1, true))
    self:assert_equal("example.org", http.url.parse("https://example.org:443/x").authority)
    self:assert_equal("example.org:8443", http.url.parse("https://example.org:8443/x").authority)
    self:assert_equal("example.org:80", http.url.parse("https://example.org:80/x").authority)
    self:assert_equal("example.org", http.url.parse("http://example.org:80/x").authority)
    server.stop()
  end)
end

function T:test_allow_downgrade_permits_a_redirect_from_https_to_http()
  run(self, function()
    local plain = scripted(function(stream) read_head(stream); stream:write(ok("plain")) end)
    local origin = tls_scripted(function(tls)
      read_head(tls)
      tls:write("HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1:" .. plain.port .. "/\r\nContent-Length: 0\r\n\r\n")
    end)
    local client <close> = http.Client({ tls = { ca_pem = CA, system_roots = false }, allow_downgrade = true })
    self:assert_equal("plain", client:get(https(origin.port)):read_content())
    plain.stop(); origin.stop()
  end)
end

return T
