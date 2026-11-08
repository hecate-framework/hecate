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
        seen.sni, seen.alpn = tls:requested_server_name(), tls:alpn()
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

function T:test_handshake_defaults_are_10_seconds_to_connect_and_60_to_accept()
  local limits = {}
  local original = reactor.deadline
  reactor.deadline = function(limit, fn, ...)
    if fn ~= nil and type(limit) == "number" then limits[#limits + 1] = limit end
    return original(limit, fn, ...)
  end
  local ok, err = pcall(run, self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local port = listener:local_address().port
    local outcome = serve_once(listener, net.tls.server_config(server_options()), function(tls) tls:shutdown() end)
    local client <close> = net.connect_tls("127.0.0.1", port, { system_roots = false, ca_pem = CA, server_name = "localhost" })
    outcome.future:value()
  end)
  reactor.deadline = original
  self:assert_true(ok, tostring(err))
  -- The server handshake is the first to start (the accepting coroutine), the client's follows.
  table.sort(limits)
  self:assert_equal(10, limits[1])
  self:assert_equal(60, limits[#limits])
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
  return require("luv").os_uname().sysname == "Linux"
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
  return require("luv").os_uname().sysname == "Darwin"
end

--- Makes a throwaway CA and a server certificate for localhost valid for 30 days with the openssl
--- command, for platforms whose system verifier refuses the 100-year fixtures. Returns
--- `{ ca, cert, key }` (PEM strings), or nil and why not. Files go to a temporary prefix and are
--- removed.
---@return { ca: string, cert: string, key: string }?
---@return string? why
local function generate_short_lived_pki()
  local prefix = os.tmpname()
  os.remove(prefix)
  local function sh(command)
    local ok = os.execute(command .. " >/dev/null 2>&1")
    return ok == true or ok == 0
  end
  local function write(path, text)
    local file = assert(io.open(path, "wb"))
    file:write(text)
    file:close()
  end
  local function read(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local text = file:read("a")
    file:close()
    return text
  end
  local files = { "ca.key", "ca.pem", "ca.cnf", "srv.key", "srv.csr", "srv.pem", "srv.cnf", "ca.srl" }
  local function cleanup() for _, name in ipairs(files) do os.remove(prefix .. "." .. name) end end
  local function path(name) return prefix .. "." .. name end
  write(path("ca.cnf"), "[req]\ndistinguished_name=dn\nprompt=no\n[dn]\nCN=Hecate Short Lived CA\n"
    .. "[ext]\nbasicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign\n")
  write(path("srv.cnf"), "basicConstraints=CA:FALSE\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:localhost,IP:127.0.0.1\n")
  local steps = {
    ("openssl ecparam -name prime256v1 -genkey -noout -out '%s'"):format(path("ca.key")),
    ("openssl req -x509 -new -key '%s' -config '%s' -extensions ext -days 30 -out '%s'"):format(path("ca.key"), path("ca.cnf"), path("ca.pem")),
    ("openssl ecparam -name prime256v1 -genkey -noout -out '%s'"):format(path("srv.key")),
    ("openssl req -new -key '%s' -subj /CN=localhost -out '%s'"):format(path("srv.key"), path("srv.csr")),
    ("openssl x509 -req -in '%s' -CA '%s' -CAkey '%s' -CAcreateserial -days 30 -extfile '%s' -out '%s'")
      :format(path("srv.csr"), path("ca.pem"), path("ca.key"), path("srv.cnf"), path("srv.pem")),
  }
  for _, step in ipairs(steps) do
    if not sh(step) then
      cleanup()
      return nil, "the openssl command failed or is missing: " .. step:match("^openssl %S+ %S+")
    end
  end
  local ca, cert, key = read(path("ca.pem")), read(path("srv.pem")), read(path("srv.key"))
  cleanup()
  if not (ca and cert and key) then return nil, "openssl produced no certificate" end
  return { ca = ca, cert = cert, key = key }
end

function T:test_ca_pem_adds_anchors_to_the_system_store()
  local cert, key, ca = SERVER_CERT, SERVER_KEY, CA
  -- macOS applies Apple's 398-day limit to every server certificate, a caller's anchor included, so
  -- the 100-year fixture cannot prove the anchor there: a short-lived chain is generated instead
  -- (HECATE_TLS_GENERATED_PKI=1 does the same on any other Unix, to exercise the generator).
  if on_macos() or os.getenv("HECATE_TLS_GENERATED_PKI") == "1" then
    local pki, why = generate_short_lived_pki()
    if not pki then
      if on_macos() then
        print("# SKIP ca_pem anchor proof on macOS: " .. tostring(why))
        return
      end
      self:fail("cannot generate the short-lived chain: " .. tostring(why))
    end
    assert(pki)
    cert, key, ca = pki.cert, pki.key, pki.ca
    print("# ca_pem proof uses a generated short-lived chain")
  end
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local port = listener:local_address().port
    local outcome = serve_once(listener, net.tls.server_config({ cert_pem = cert, key_pem = key }), function(tls)
      tls:write("ok")
      tls:shutdown()
    end)
    local client <close> = net.connect_tls("127.0.0.1", port, { ca_pem = ca, server_name = "localhost" })
    self:assert_equal("ok", client:read())
    outcome.future:value()
  end)
end

-- Reaches a public server with no option: the operating system's trust store is enough. Needs
-- the network, so CI turns it on with HECATE_NETWORK_TESTS=1.
--
-- The verdict is the handshake: `net.connect_tls` succeeding without any option proves the trust
-- store is enough (RFC 8446 section 4.4.2; service identity, RFC 6125 section 6), and a `TlsError`
-- that is a certificate or trust failure fails the test, is never retried and never skipped. Every
-- other step reaches an endpoint the project does not control, so a refusal, a reset, a stall or an
-- exceeded deadline is infrastructure: it is reported as a skip, with its error class, never as a
-- failure and never left to the harness watchdog.

--- True for a failure that says nothing about trust: a deadline, a transport or network failure, a
--- stream that ended early, or a TLS transport that ended without a verdict (RFC 8446 section 6.1).
--- A `TlsError` of any other reason (untrusted issuer, name mismatch, expiry, an alert...) is a
--- verdict, so it is not infrastructure.
local function is_infrastructure(err)
  local core = require("hecate.core")
  if core.is_instance_of(err, net.TlsError) then
    local reason = err.context and err.context.reason
    return reason == "truncated" or reason == "transport_ended" or reason == "stalled"
  end
  return core.is_instance_of(err, core.DeadlineExceededError) or core.is_instance_of(err, core.NetworkError)
end

local function describe(err)
  local code = type(err) == "table" and err.code or nil
  return ("%s: %s"):format(tostring(code or "error"), (tostring(err):gsub("%s*\nstack traceback:.*$", "")))
end

--- Probes `host:port` over TLS. Must run on a reactor. Returns `{ skip = reason }` when the endpoint
--- cannot give a verdict, otherwise `{ bonus_skip = reason }` (handshake done, the status line not
--- read) or `{ status = line }`. Raises the `TlsError` of a failed handshake and any failure that is
--- not infrastructure. `options`: `connect_options` (for `net.connect_tls`), `attempts` (default 2),
--- `connect_deadline` (30 s, per attempt), `io_deadline` (10 s, for the request and the status
--- line), `total_deadline` (seconds for the whole probe, default 90).
local function probe_trust(host, port, options)
  options = options or {}
  local attempts = options.attempts or 2
  local connect_deadline = options.connect_deadline or 30
  local io_deadline = options.io_deadline or 10
  local total_deadline = options.total_deadline or 90
  local request = options.request or ("HEAD / HTTP/1.1\r\nHost: %s\r\nConnection: close\r\n\r\n"):format(host)
  local core = require("hecate.core")
  local ok, result = pcall(reactor.deadline, total_deadline, function()
    local client, last
    for _ = 1, attempts do
      local attempt_ok, value = pcall(reactor.deadline, connect_deadline, net.connect_tls, host, port, options.connect_options)
      if attempt_ok then
        client = value
        break
      end
      if not is_infrastructure(value) then error(value, 0) end -- a verdict, never retried
      last = value
    end
    if not client then return { skip = ("no handshake after %d attempt(s): %s"):format(attempts, describe(last)) } end
    local stream <close> = client
    -- The handshake succeeded: trust is proven. What follows is a bonus check.
    local line_ok, line = pcall(reactor.deadline, io_deadline, function()
      stream:write(request)
      return stream:reader():read_line()
    end)
    if not line_ok then
      if not is_infrastructure(line) then error(line, 0) end
      return { bonus_skip = "no status line: " .. describe(line) }
    end
    if line == nil then return { bonus_skip = "no status line: the peer closed the connection" } end
    return { status = line }
  end)
  if ok then return result end
  if core.is_instance_of(result, core.DeadlineExceededError) then
    return { skip = ("overall deadline of %s s exceeded: %s"):format(tostring(total_deadline), describe(result)) }
  end
  error(result, 0)
end

-- Below the watchdog of the harness (HECATE_TEST_TIMEOUT, 120 s by default) with a margin, so that the
-- watchdog is never the one to fail the test.
local function overall_deadline()
  local limit = tonumber(os.getenv("HECATE_TEST_TIMEOUT")) or 120
  return math.max(1, math.min(90, limit - 30))
end

local function report(self, outcome)
  if outcome.skip then
    print("# SKIP public server test: " .. outcome.skip)
  elseif outcome.bonus_skip then
    print("# SKIP public server test (status line only; trust proven): " .. outcome.bonus_skip)
  else
    self:assert_true(outcome.status:find("^HTTP/1%.1 %d%d%d") ~= nil, tostring(outcome.status))
  end
end

function T:test_a_public_server_is_trusted_out_of_the_box()
  if os.getenv("HECATE_NETWORK_TESTS") ~= "1" then
    print("# SKIP public server test: set HECATE_NETWORK_TESTS=1")
    return
  end
  run(self, function()
    report(self, probe_trust("github.com", 443, { total_deadline = overall_deadline() }))
  end)
end

-- The bounded part of the test above, proved over loopback: stalls are skips, verdicts still fail.
local LOOPBACK = { system_roots = false, ca_pem = CA, server_name = "localhost" }

local function probe_loopback(port, extra)
  local options = { connect_options = LOOPBACK, connect_deadline = 0.3, io_deadline = 0.3, total_deadline = 5 }
  for k, v in pairs(extra or {}) do options[k] = v end
  return probe_trust("127.0.0.1", port, options)
end

function T:test_probe_returns_the_status_line_after_a_handshake()
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local outcome = serve_once(listener, net.tls.server_config(server_options()), function(tls)
      tls:read()
      tls:write("HTTP/1.1 200 OK\r\n\r\n")
      tls:shutdown()
    end)
    local result = probe_loopback(listener:local_address().port)
    self:assert_equal("HTTP/1.1 200 OK", result.status)
    outcome.future:value()
  end)
end

function T:test_probe_skips_a_peer_that_accepts_and_never_answers()
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local release = reactor.Channel(1)
    reactor.fork(function()
      local first <close> = listener:accept()
      local second <close> = listener:accept() -- the retry
      release:receive()
    end)
    local started = reactor.now and reactor.now() or os.clock()
    local result = probe_loopback(listener:local_address().port)
    self:assert_not_nil(result.skip, "a stalled handshake is a skip")
    self:assert_true(result.skip:find("DeadlineExceededError", 1, true) ~= nil, result.skip)
    self:assert_true(result.skip:find("2 attempt", 1, true) ~= nil, result.skip)
    self:assert_true((reactor.now and reactor.now() or os.clock()) - started < 3)
    release:send(true)
  end)
end

function T:test_probe_skips_a_refused_connection()
  run(self, function()
    local listener = net.listen("127.0.0.1", 0)
    local port = listener:local_address().port
    listener:close() -- nothing listens there any more
    local result = probe_loopback(port)
    self:assert_not_nil(result.skip, "a refused connection is infrastructure")
  end)
end

function T:test_probe_overall_deadline_is_a_skip_not_a_failure()
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local release = reactor.Channel(1)
    reactor.fork(function()
      local raw <close> = listener:accept()
      release:receive()
    end)
    local result = probe_loopback(listener:local_address().port, { connect_deadline = 30, total_deadline = 0.3 })
    self:assert_not_nil(result.skip)
    self:assert_true(result.skip:find("overall deadline", 1, true) ~= nil, result.skip)
    release:send(true)
  end)
end

function T:test_probe_skips_the_bonus_when_the_status_line_stalls()
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local release = reactor.Channel(1)
    local outcome = serve_once(listener, net.tls.server_config(server_options()), function(tls)
      release:receive() -- handshake done, then silence
    end)
    local started = os.time()
    local result = probe_loopback(listener:local_address().port)
    self:assert_nil(result.skip, "the handshake succeeded: trust is proven")
    self:assert_not_nil(result.bonus_skip)
    self:assert_true(os.time() - started < 4)
    release:send(true)
    outcome.future:value()
  end)
end

function T:test_probe_skips_the_bonus_on_end_of_stream()
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local outcome = serve_once(listener, net.tls.server_config(server_options()), function(tls)
      tls:shutdown()
    end)
    local result = probe_loopback(listener:local_address().port)
    self:assert_nil(result.skip)
    self:assert_not_nil(result.bonus_skip or result.status == nil and "unexpected", tostring(result.status))
    outcome.future:value()
  end)
end

function T:test_probe_still_fails_on_an_untrusted_certificate()
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    serve_once(listener, net.tls.server_config(server_options()), function() end)
    local err = self:assert_error(function()
      probe_loopback(listener:local_address().port,
        { connect_options = { system_roots = false, ca_pem = fixture("other_ca.pem"), server_name = "localhost" } })
    end)
    self:assert_true(require("hecate.core").is_instance_of(err, net.TlsError), tostring(err))
    self:assert_equal("untrusted_issuer", err.context.reason)
  end)
end

function T:test_probe_still_fails_on_a_name_mismatch()
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    serve_once(listener, net.tls.server_config(server_options()), function() end)
    local err = self:assert_error(function()
      probe_loopback(listener:local_address().port,
        { connect_options = { system_roots = false, ca_pem = CA, server_name = "wrong.example" } })
    end)
    self:assert_equal("name_mismatch", err.context.reason)
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

local function revocation_exchange(self, client_name, crl_pem)
  local worked, failure
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local port = listener:local_address().port
    local config = net.tls.server_config(server_options({ client_ca_pem = fixture("revocation_ca.pem"), client_crl_pem = crl_pem }))
    local outcome = serve_once(listener, config, function(tls)
      tls:write(tls:reader():read_line() .. "!")
      tls:shutdown()
    end)
    -- With TLS 1.3 the rejection of the client certificate may only surface on the first read.
    worked, failure = pcall(function()
      local client <close> = net.connect_tls("127.0.0.1", port, {
        system_roots = false, ca_pem = CA, server_name = "localhost",
        cert_pem = fixture(client_name .. ".pem"), key_pem = fixture(client_name .. ".key"),
      })
      client:write("crl\n")
      local reply = client:read()
      outcome.future:value() -- the server finished while this side is still open
      return reply == "crl!"
    end)
    outcome.future:value()
    if worked then self:assert_true(outcome.ok, tostring(outcome.value)) else self:assert_false(outcome.ok) end
  end)
  return worked, failure
end

function T:test_a_crl_rejects_a_revoked_client_certificate_and_accepts_the_others()
  local crl = fixture("revoked.crl.pem")
  local ok, err = revocation_exchange(self, "valid_client", crl)
  self:assert_true(ok, tostring(err))
  local revoked_ok, failure = revocation_exchange(self, "revoked_client", crl)
  self:assert_false(revoked_ok)
  local core = require("hecate.core")
  self:assert_true(core.is_instance_of(failure, net.TlsError) or core.is_instance_of(failure, core.NetworkError), tostring(failure))
end

function T:test_without_a_crl_a_revoked_client_certificate_is_accepted_the_documented_limit()
  local ok, err = revocation_exchange(self, "revoked_client", nil)
  self:assert_true(ok, tostring(err))
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
    self:assert_equal("expired", err.context.reason) -- the path with only the given anchors (system_roots = false) is the same everywhere
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
    -- The same error as a closed TcpStream: TransportError, errno EBADF, a stable operation.
    for _, operation in ipairs({ "read", "write", "shutdown" }) do
      local err = self:assert_error(function()
        if operation == "write" then client:write("x") elseif operation == "read" then client:read() else client:shutdown() end
      end)
      self:assert_true(require("hecate.core").is_instance_of(err, reactor.TransportError), tostring(err))
      self:assert_equal("EBADF", err.context.errno)
      self:assert_equal(operation, err.context.operation)
    end
    local err = self:assert_error(function() client:read(0) end)
    self:assert_true(require("hecate.core").is_instance_of(err, require("hecate.core").ArgumentError), tostring(err))
  end)
end

return T
