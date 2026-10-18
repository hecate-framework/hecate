-- TLS configuration and the connect path: handshake deadline, default configuration cache,
-- validation order and the unknown-issuer hint. Needs the native module (see tls_test.lua).
local test = require("harness.test")
local core = require("hecate.core")
local reactor = require("hecate.reactor")
local net = require("hecate.net")
local T = test.Case("NetTlsOptionsIntegrationTest")

local available, reason = net.tls.available()
if not available then
  function T:test_skipped_native_module_not_built()
    if os.getenv("HECATE_REQUIRE_TLS") == "1" then
      self:fail("hecate.net TLS option tests cannot run: " .. tostring(reason))
    end
    print("# SKIP hecate.net TLS option tests: " .. tostring(reason))
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

local function run(self, fn)
  local before = reactor.Reactor.open_handles()
  reactor.run(fn)
  self:assert_equal(before, reactor.Reactor.open_handles())
end

--- Counts the calls of a native function while `fn` runs.
local function count_native(name, fn)
  local native = require("hecate.net.tls_native")
  local original = native[name]
  local calls = 0
  native[name] = function(...)
    calls = calls + 1
    return original(...)
  end
  local ok, failure = pcall(fn)
  native[name] = original
  if not ok then error(failure, 0) end
  return calls
end

--- A listener whose accepted connections never speak TLS until `release` is signalled.
local function silent_peer(listener, release)
  return reactor.fork(function()
    local raw <close> = listener:accept()
    release:receive()
  end)
end

function T:test_a_stalled_handshake_expires_after_handshake_deadline_and_closes_the_stream()
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local port = listener:local_address().port
    local release = reactor.Channel(1)
    local peer = silent_peer(listener, release)
    local started = reactor.now()
    local err = self:assert_error(function()
      net.connect_tls("127.0.0.1", port, { system_roots = false, ca_pem = CA, server_name = "localhost", handshake_deadline = 0.05 })
    end)
    self:assert_true(core.is_instance_of(err, core.DeadlineExceededError), tostring(err))
    self:assert_true(reactor.now() - started < 5, "the default of 10 s must not apply")
    release:send(true)
    peer:value()
  end) -- run() asserts that no libuv handle is left: the inner stream was closed
end

function T:test_tls_connect_and_accept_take_handshake_deadline()
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local port = listener:local_address().port
    local release = reactor.Channel(1)
    local peer = silent_peer(listener, release)
    local config = net.tls.client_config({ system_roots = false, ca_pem = CA })
    local raw = net.connect("127.0.0.1", port)
    local err = self:assert_error(function() net.tls.connect(raw, "localhost", config, { handshake_deadline = 0.05 }) end)
    self:assert_true(core.is_instance_of(err, core.DeadlineExceededError), tostring(err))
    self:assert_true(raw:is_closed())
    release:send(true)
    peer:value()

    -- Server side: a client that connects and never speaks.
    local server_config = net.tls.server_config({ cert_pem = SERVER_CERT, key_pem = SERVER_KEY })
    local listener2 <close> = net.listen("127.0.0.1", 0)
    local mute2 <close> = net.connect("127.0.0.1", listener2:local_address().port)
    local accepted = listener2:accept()
    err = self:assert_error(function() net.tls.accept(accepted, server_config, { handshake_deadline = 0.05 }) end)
    self:assert_true(core.is_instance_of(err, core.DeadlineExceededError), tostring(err))
    self:assert_true(accepted:is_closed())
  end)
end

function T:test_a_handshake_that_finishes_in_time_is_unaffected_by_the_deadline()
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local port = listener:local_address().port
    local served = reactor.fork(function()
      local tls <close> = net.tls.accept(listener:accept(), net.tls.server_config({ cert_pem = SERVER_CERT, key_pem = SERVER_KEY }), { handshake_deadline = 5 })
      tls:write("ok")
      tls:shutdown()
    end)
    local client <close> = net.connect_tls("127.0.0.1", port, { system_roots = false, ca_pem = CA, server_name = "localhost", handshake_deadline = 5 })
    self:assert_equal("ok", client:read())
    served:value()
  end)
end

function T:test_a_bad_transport_option_is_rejected_before_the_configuration_is_built()
  run(self, function()
    local calls = count_native("client_config", function()
      local err = self:assert_error(function() net.connect_tls("127.0.0.1", 1, { nodelay = "yes" }) end)
      self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
      err = self:assert_error(function() net.connect_tls("127.0.0.1", 1, { verify = false }) end)
      self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
    end)
    self:assert_equal(0, calls)
  end)
end

function T:test_the_default_client_configuration_is_built_once_per_alpn_list()
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local port = listener:local_address().port
    local release = reactor.Channel(1)
    local function attempt(options)
      options.handshake_deadline = 0.02
      options.server_name = "localhost"
      local peer = silent_peer(listener, release)
      local err = self:assert_error(function() net.connect_tls("127.0.0.1", port, options) end)
      self:assert_true(core.is_instance_of(err, core.DeadlineExceededError), tostring(err))
      release:send(true)
      peer:value()
    end
    local calls = count_native("client_config", function()
      attempt({})
      attempt({})
      attempt({ alpn = { "h2" } })
      attempt({ alpn = { "h2" } })
      attempt({ alpn = { "h2", "http/1.1" } })
    end)
    -- One build per distinct default (no alpn, { h2 }, { h2, http/1.1 }); an explicit ca_pem is never cached.
    self:assert_equal(3, calls)
    calls = count_native("client_config", function()
      attempt({ ca_pem = CA })
      attempt({ ca_pem = CA })
    end)
    self:assert_equal(2, calls)
  end)
end

function T:test_a_prebuilt_configuration_is_reused_without_building()
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local config = net.tls.client_config({ system_roots = false, ca_pem = CA })
    local release = reactor.Channel(1)
    local calls = count_native("client_config", function()
      for _ = 1, 2 do
        local peer = silent_peer(listener, release)
        local err = self:assert_error(function()
          net.connect_tls("127.0.0.1", listener:local_address().port, { tls_config = config, server_name = "localhost", handshake_deadline = 0.02 })
        end)
        self:assert_true(core.is_instance_of(err, core.DeadlineExceededError), tostring(err))
        release:send(true)
        peer:value()
      end
    end)
    self:assert_equal(0, calls)
  end)
end

function T:test_an_untrusted_issuer_carries_the_reason_and_a_platform_neutral_hint()
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local port = listener:local_address().port
    local served = reactor.fork(function()
      pcall(function()
        local tls <close> = net.tls.accept(listener:accept(), net.tls.server_config({ cert_pem = SERVER_CERT, key_pem = SERVER_KEY }))
        tls:read()
      end)
    end)
    -- The system store is trusted by default; on Linux it rejects the fixture CA with a known reason.
    local ok, err = pcall(net.connect_tls, "127.0.0.1", port, { server_name = "localhost" })
    self:assert_false(ok)
    self:assert_true(core.is_instance_of(err, net.TlsError), tostring(err))
    if err.context.reason == "untrusted_issuer" then
      local text = tostring(err)
      self:assert_true(text:find("system trust store", 1, true) ~= nil, text)
      self:assert_true(text:find("ca_pem", 1, true) ~= nil, text)
      self:assert_true(text:find("macOS", 1, true) ~= nil, text) -- platform-neutral wording
      self:assert_true(core.is_instance_of(err.cause, net.TlsError))
    end
    served:value()
  end)
end

function T:test_the_hint_is_not_added_when_system_roots_is_off()
  run(self, function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local port = listener:local_address().port
    local served = reactor.fork(function()
      pcall(function()
        local tls <close> = net.tls.accept(listener:accept(), net.tls.server_config({ cert_pem = SERVER_CERT, key_pem = SERVER_KEY }))
        tls:read()
      end)
    end)
    local err = self:assert_error(function()
      net.connect_tls("127.0.0.1", port, { system_roots = false, ca_pem = fixture("other_ca.pem"), server_name = "localhost" })
    end)
    self:assert_true(core.is_instance_of(err, net.TlsError), tostring(err))
    self:assert_equal("untrusted_issuer", err.context.reason)
    self:assert_true(tostring(err):find("system trust store", 1, true) == nil, tostring(err))
    served:value()
  end)
end

return T
