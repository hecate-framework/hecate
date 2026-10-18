-- TLS over loopback against the local test CA of tests/fixtures (see its README). Skips with a
-- message when the native module is not built (`lua tools/run.lua build-native`).
local test = require("harness.test")
local reactor = require("hecate.reactor")
local net = require("hecate.net")
local T = test.Case("NetTlsTest")

local available, reason = net.tls.available()
if not available then
  function T:test_skipped_native_module_not_built()
    -- CI sets HECATE_REQUIRE_TLS=1: a missing module must fail there, never skip silently.
    if os.getenv("HECATE_REQUIRE_TLS") == "1" then
      self:fail("hecate.net TLS tests cannot run: " .. tostring(reason))
    end
    print("# SKIP hecate.net TLS tests: " .. tostring(reason))
  end
  return T
end

local function fixture(name)
  local path = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):gsub("/[^/]*$", "") .. "/../fixtures/" .. name
  local f = assert(io.open(path, "rb"), "missing fixture " .. path)
  local s = f:read("a")
  f:close()
  return s
end

local CA, SERVER_CERT, SERVER_KEY = fixture("ca.pem"), fixture("server.pem"), fixture("server.key")

--- Runs `fn` on a reactor and checks that no libuv handle is left open afterwards, failure paths
--- (rejected handshakes, cancelled connects) included.
local function run(self, fn)
  local before = reactor.Reactor.open_handles()
  reactor.run(fn)
  self:assert_equal(before, reactor.Reactor.open_handles())
end

--- Runs `serve(stream)` on one accepted connection, in a forked coroutine.
local function serve_once(listener, config, serve)
  local outcome = {}
  outcome.future = reactor.fork(function()
    local raw = listener:accept()
    local ok, result = pcall(function()
      local tls <close> = net.tls.accept(raw, config)
      return serve(tls)
    end)
    outcome.ok, outcome.value = ok, result
  end)
  return outcome
end

local function server_options(extra)
  local options = { cert_pem = SERVER_CERT, key_pem = SERVER_KEY }
  for k, v in pairs(extra or {}) do options[k] = v end
  return options
end

function T:test_echo_with_sni_alpn_and_buffered_lines()
  local before = reactor.Reactor.open_handles()
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local port = listener:local_address().port
    local seen = {}
    local outcome = serve_once(listener, net.tls.server_config(server_options({ alpn = { "h2", "http/1.1" } })),
      function(tls)
        seen.sni, seen.alpn = tls:server_name(), tls:alpn()
        local reader = tls:reader()
        local line = reader:read_line()
        tls:write("echo:" .. line .. "\n")
        tls:shutdown()
      end)
    local client <close> = net.connect_tls("127.0.0.1", port, { system_roots = false, ca_pem = CA, server_name = "localhost", alpn = { "http/1.1" } })
    self:assert_equal("http/1.1", client:alpn())
    self:assert_equal("TLSv1.3", client:version())
    client:write("hello\n")
    local reader = client:reader()
    self:assert_equal("echo:hello", reader:read_line())
    self:assert_nil(reader:read_line()) -- close_notify: a clean end
    outcome.future:value() -- the server finished
    self:assert_true(outcome.ok, tostring(outcome.value))
    self:assert_equal("localhost", seen.sni)
    self:assert_equal("http/1.1", seen.alpn)
  end)
  self:assert_equal(before, reactor.Reactor.open_handles())
end

function T:test_large_payload_round_trip()
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local port = listener:local_address().port
    local payload = ("0123456789abcdef"):rep(40000) -- 640 KB: many records, back-pressure
    local outcome = serve_once(listener, net.tls.server_config(server_options()), function(tls)
      local reader = tls:reader()
      tls:write(reader:read_exact(#payload))
      tls:shutdown()
    end)
    local client <close> = net.connect_tls("127.0.0.1", port, { system_roots = false, ca_pem = CA, server_name = "localhost" })
    reactor.fork(function() client:write(payload) end)
    local reader = client:reader()
    self:assert_true(reader:read_exact(#payload) == payload)
    outcome.future:value() -- the server finished
    self:assert_true(outcome.ok, tostring(outcome.value))
  end)
end

function T:test_untrusted_certificate_is_rejected_by_default()
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local port = listener:local_address().port
    serve_once(listener, net.tls.server_config(server_options()), function() end)
    local err = self:assert_error(function()
      net.connect_tls("127.0.0.1", port, { system_roots = false, ca_pem = fixture("other_ca.pem"), server_name = "localhost" })
    end)
    self:assert_true(require("hecate.core").is_instance_of(err, net.TlsError), tostring(err))
  end)
end

function T:test_name_mismatch_is_rejected()
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local port = listener:local_address().port
    serve_once(listener, net.tls.server_config(server_options()), function() end)
    local err = self:assert_error(function()
      net.connect_tls("127.0.0.1", port, { system_roots = false, ca_pem = CA, server_name = "wrong.example" })
    end)
    self:assert_true(require("hecate.core").is_instance_of(err, net.TlsError), tostring(err))
    self:assert_equal("name_mismatch", err.context.reason)
  end)
end

function T:test_without_system_roots_the_given_anchors_are_required()
  run(self, function()
    local core = require("hecate.core")
    local err = self:assert_error(function()
      net.connect_tls("127.0.0.1", 1, { system_roots = false })
    end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
    self:assert_true(tostring(err):find("ca_pem is required when system_roots is false", 1, true) ~= nil, tostring(err))
    ---@diagnostic disable-next-line: assign-type-mismatch
    err = self:assert_error(function() net.connect_tls("127.0.0.1", 1, { system_roots = "no" }) end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
  end)
end

--- True on Linux, where the system verifier is webpki and its failures carry the names `reason`
--- recognises; the operating system's verifiers elsewhere report many failures as plain text.
local function on_linux()
  if package.config:sub(1, 1) == "\\" then return false end
  local pipe = io.popen("uname -s 2>/dev/null")
  if not pipe then return false end
  local name = pipe:read("l")
  pipe:close()
  return name == "Linux"
end

function T:test_the_system_store_rejects_the_test_ca_and_says_how_to_trust_it()
  run(self, function()
    local core = require("hecate.core")
    local listener <close> = net.listen("127.0.0.1", 0)
    local port = listener:local_address().port
    local outcome = serve_once(listener, net.tls.server_config(server_options()), function() end)
    -- No option: the operating system's store does not know the fixture CA.
    local err = self:assert_error(function() net.connect_tls("127.0.0.1", port, { server_name = "localhost" }) end)
    self:assert_true(core.is_instance_of(err, net.TlsError), tostring(err))
    if on_linux() then
      self:assert_equal("untrusted_issuer", err.context.reason)
      self:assert_true(tostring(err):find("system trust store", 1, true) ~= nil, tostring(err)) -- says how to fix it
    end
    outcome.future:value()
  end)
end

--- True on macOS, whose system verifier applies Apple's limits on the validity of a server
--- certificate (398 days) even to one issued by a CA the caller added: the 100-year fixture is
--- refused there (ADR 0024, "Consequences").
local function on_macos()
  if package.config:sub(1, 1) == "\\" then return false end
  local pipe = io.popen("uname -s 2>/dev/null")
  if not pipe then return false end
  local name = pipe:read("l")
  pipe:close()
  return name == "Darwin"
end

function T:test_ca_pem_adds_anchors_to_the_system_store()
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local port = listener:local_address().port
    local outcome = serve_once(listener, net.tls.server_config(server_options()), function(tls)
      tls:write("ok")
      tls:shutdown()
    end)
    local ok, result = pcall(function()
      local client <close> = net.connect_tls("127.0.0.1", port, { ca_pem = CA, server_name = "localhost" })
      return client:read()
    end)
    if on_macos() then
      -- Either the CA is accepted, or Apple's validity policy refuses the 100-year certificate.
      if not ok then
        self:assert_true(tostring(result):find("not standards compliant", 1, true) ~= nil, tostring(result))
      end
    else
      self:assert_true(ok, tostring(result))
      self:assert_equal("ok", result)
    end
    outcome.future:value()
  end)
end

-- Reaches a public server with no option: the operating system's trust store is enough. Needs
-- the network, so CI turns it on with HECATE_NETWORK_TESTS=1.
function T:test_a_public_server_is_trusted_out_of_the_box()
  if os.getenv("HECATE_NETWORK_TESTS") ~= "1" then
    print("# SKIP public server test: set HECATE_NETWORK_TESTS=1")
    return
  end
  run(self, function()
    local client <close> = reactor.deadline(30, net.connect_tls, "github.com", 443)
    client:write("HEAD / HTTP/1.1\r\nHost: github.com\r\nConnection: close\r\n\r\n")
    local status = client:reader():read_line()
    self:assert_true(status ~= nil and status:find("^HTTP/1%.1 %d%d%d") ~= nil, tostring(status))
  end)
end

function T:test_no_option_disables_verification()
  run(self, function()
    local core = require("hecate.core")
    -- Keys that would disable verification elsewhere are not options: they are rejected.
    local err = self:assert_error(function()
      net.connect_tls("127.0.0.1", 1, { system_roots = false, ca_pem = CA, server_name = "localhost", verify = false })
    end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
  end)
end

function T:test_connect_tls_rejects_inconsistent_options()
  run(self, function()
    local core = require("hecate.core")
    local config = net.tls.client_config({ system_roots = false, ca_pem = CA })
    local function rejected(options)
      local err = self:assert_error(function() net.connect_tls("127.0.0.1", 1, options) end)
      self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
    end
    rejected({ tls_config = config, ca_pem = CA })
    rejected({ ca_pem = CA, cert_pem = SERVER_CERT })
    rejected({ system_roots = false, ca_pem = CA, server_name = "" })
  end)
end

function T:test_tls_connect_and_accept_validate_the_configuration()
  run(self, function()
    local core = require("hecate.core")
    local listener <close> = net.listen("127.0.0.1", 0)
    local port = listener:local_address().port
    local raw <close> = net.connect("127.0.0.1", port)
    local err = self:assert_error(function() net.tls.connect(raw, "localhost", {} --[[@as userdata]]) end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
    self:assert_false(raw:is_closed()) -- the caller keeps the stream on an argument error
    err = self:assert_error(function() net.tls.accept(raw, {} --[[@as userdata]]) end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
  end)
end

function T:test_truncation_without_close_notify_is_an_error()
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local port = listener:local_address().port
    serve_once(listener, net.tls.server_config(server_options()), function(tls)
      tls:write("partial") -- then closes the TCP stream without close_notify
    end)
    local client <close> = net.connect_tls("127.0.0.1", port, { system_roots = false, ca_pem = CA, server_name = "localhost" })
    self:assert_equal("partial", client:read())
    local err = self:assert_error(function() client:read() end)
    self:assert_true(require("hecate.core").is_instance_of(err, net.TlsError), tostring(err))
  end)
end

function T:test_mutual_tls_requires_a_trusted_client_certificate()
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local port = listener:local_address().port
    local config = net.tls.server_config(server_options({ client_ca_pem = CA }))
    local outcome = serve_once(listener, config, function(tls)
      tls:write(tls:reader():read_line() .. "!")
      tls:shutdown()
    end)
    local client <close> = net.connect_tls("127.0.0.1", port, {
      system_roots = false, ca_pem = CA, server_name = "localhost", cert_pem = fixture("client.pem"), key_pem = fixture("client.key"),
    })
    client:write("mtls\n")
    self:assert_equal("mtls!", client:read())
    outcome.future:value() -- the server finished
    self:assert_true(outcome.ok, tostring(outcome.value))
  end)
end

function T:test_mutual_tls_rejects_a_client_without_a_certificate()
  run(self, function()
    local core = require("hecate.core")
    local listener <close> = net.listen("127.0.0.1", 0)
    local port = listener:local_address().port
    local config = net.tls.server_config(server_options({ client_ca_pem = CA }))
    local outcome = serve_once(listener, config, function(tls) tls:read() end)
    -- With TLS 1.3 the client finishes its handshake before the server has checked the client
    -- certificate (RFC 8446 section 4.4), so the rejection may only surface on the first read.
    local ok, err = pcall(function()
      local client <close> = net.connect_tls("127.0.0.1", port, { system_roots = false, ca_pem = CA, server_name = "localhost" })
      client:write("hello\n")
      client:read()
    end)
    self:assert_false(ok)
    -- The client sees the server's alert as a TlsError, or, when the server closes first (Windows
    -- resets the connection and drops the alert), the reset as a TransportError.
    self:assert_true(core.is_instance_of(err, net.TlsError) or core.is_instance_of(err, core.NetworkError), tostring(err))
    outcome.future:value()
    self:assert_false(outcome.ok) -- the server side failed its handshake too
  end)
end

function T:test_the_server_identity_can_be_an_ip_address()
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local port = listener:local_address().port
    local outcome = serve_once(listener, net.tls.server_config(server_options()), function(tls)
      tls:write("ok")
      tls:shutdown()
    end)
    -- No server_name: the host, an address, is the identity and the certificate has it as an IP SAN.
    local client <close> = net.connect_tls("127.0.0.1", port, { system_roots = false, ca_pem = CA })
    self:assert_equal("ok", client:read())
    outcome.future:value()
  end)
end

function T:test_an_expired_certificate_is_rejected()
  run(self, function()
    local core = require("hecate.core")
    local listener <close> = net.listen("127.0.0.1", 0)
    local port = listener:local_address().port
    local config = net.tls.server_config({ cert_pem = fixture("expired.pem"), key_pem = fixture("expired.key") })
    local outcome = serve_once(listener, config, function() end)
    local err = self:assert_error(function()
      net.connect_tls("127.0.0.1", port, { system_roots = false, ca_pem = fixture("expired_ca.pem"), server_name = "localhost" })
    end)
    self:assert_true(core.is_instance_of(err, net.TlsError), tostring(err))
    self:assert_true(tostring(err):lower():find("expired", 1, true) ~= nil, tostring(err))
    self:assert_equal("expired", err.context.reason) -- the closed-trust path is the same everywhere
    outcome.future:value()
  end)
end

function T:test_an_alpn_mismatch_fails_the_handshake()
  run(self, function()
    local core = require("hecate.core")
    local listener <close> = net.listen("127.0.0.1", 0)
    local port = listener:local_address().port
    local outcome = serve_once(listener, net.tls.server_config(server_options({ alpn = { "h2" } })), function() end)
    local err = self:assert_error(function()
      net.connect_tls("127.0.0.1", port, { system_roots = false, ca_pem = CA, server_name = "localhost", alpn = { "http/1.1" } })
    end)
    -- The server's alert, or (where the connection is reset first) the reset.
    self:assert_true(core.is_instance_of(err, net.TlsError) or core.is_instance_of(err, core.NetworkError), tostring(err))
    if core.is_instance_of(err, net.TlsError) then self:assert_equal("alpn_mismatch", err.context.reason) end
    outcome.future:value()
    self:assert_false(outcome.ok)
  end)
end

function T:test_cancelling_a_stalled_handshake_releases_everything()
  run(self, function()
    local core = require("hecate.core")
    local listener <close> = net.listen("127.0.0.1", 0)
    local port = listener:local_address().port
    local release = reactor.Channel(1)
    -- A peer that accepts the connection and never speaks TLS.
    reactor.fork(function()
      local raw <close> = listener:accept()
      release:receive()
    end)
    local ok, err = pcall(reactor.deadline, 0.2, net.connect_tls, "127.0.0.1", port,
      { system_roots = false, ca_pem = CA, server_name = "localhost" })
    self:assert_false(ok)
    self:assert_true(core.is_instance_of(err, core.DeadlineExceededError), tostring(err))
    release:send(true)
  end)
end

function T:test_deadline_cancelling_a_read_keeps_the_stream()
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local port = listener:local_address().port
    local release = reactor.Channel(1)
    local outcome = serve_once(listener, net.tls.server_config(server_options()), function(tls)
      release:receive() -- silent until the deadline has expired
      tls:write("late")
      tls:shutdown()
    end)
    local client <close> = net.connect_tls("127.0.0.1", port, { system_roots = false, ca_pem = CA, server_name = "localhost" })
    local ok = pcall(reactor.deadline, 0.05, function() return client:read() end)
    self:assert_false(ok)
    self:assert_false(client:is_closed())
    release:send(true)
    self:assert_equal("late", client:read())
    outcome.future:value()
  end)
end

function T:test_streams_are_closable()
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local port = listener:local_address().port
    serve_once(listener, net.tls.server_config(server_options()), function(tls) tls:read() end)
    local client = net.connect_tls("127.0.0.1", port, { system_roots = false, ca_pem = CA, server_name = "localhost" })
    self:assert_false(client:is_closed())
    client:close()
    client:close()
    self:assert_true(client:is_closed())
    local err = self:assert_error(function() client:write("x") end)
    self:assert_true(require("hecate.core").is_instance_of(err, require("hecate.core").Error), tostring(err))
    err = self:assert_error(function() client:read(0) end)
    self:assert_true(require("hecate.core").is_instance_of(err, require("hecate.core").ArgumentError), tostring(err))
  end)
end

return T
