-- TLS over loopback against the local test CA of tests/fixtures (see its README). Skips with a
-- message when the native module is not built (`lua tools/run.lua build-native`).
local test = require("harness.test")
local reactor = require("hecate.reactor")
local net = require("hecate.net")
local T = test.Case("NetTlsTest")

local available, reason = net.tls.available()
if not available then
  function T:test_skipped_native_module_not_built()
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

--- Runs `serve(stream)` on one accepted connection, in a forked task.
local function serve_once(listener, config, serve)
  local outcome = {}
  reactor.fork(function()
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
  reactor.run(function()
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
    local client <close> = net.connect_tls("127.0.0.1", port, { ca_pem = CA, server_name = "localhost", alpn = { "http/1.1" } })
    self:assert_equal("http/1.1", client:alpn())
    self:assert_equal("TLSv1.3", client:version())
    client:write("hello\n")
    local reader = client:reader()
    self:assert_equal("echo:hello", reader:read_line())
    self:assert_nil(reader:read_line()) -- close_notify: a clean end
    reactor.sleep(0.05)
    self:assert_true(outcome.ok, tostring(outcome.value))
    self:assert_equal("localhost", seen.sni)
    self:assert_equal("http/1.1", seen.alpn)
  end)
  self:assert_equal(before, reactor.Reactor.open_handles())
end

function T:test_large_payload_round_trip()
  reactor.run(function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local port = listener:local_address().port
    local payload = ("0123456789abcdef"):rep(40000) -- 640 KB: many records, back-pressure
    local outcome = serve_once(listener, net.tls.server_config(server_options()), function(tls)
      local reader = tls:reader()
      tls:write(reader:read_exact(#payload))
      tls:shutdown()
    end)
    local client <close> = net.connect_tls("127.0.0.1", port, { ca_pem = CA, server_name = "localhost" })
    reactor.fork(function() client:write(payload) end)
    local reader = client:reader()
    self:assert_true(reader:read_exact(#payload) == payload)
    reactor.sleep(0.05)
    self:assert_true(outcome.ok, tostring(outcome.value))
  end)
end

function T:test_untrusted_certificate_is_rejected_by_default()
  reactor.run(function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local port = listener:local_address().port
    serve_once(listener, net.tls.server_config(server_options()), function() end)
    local err = self:assert_error(function()
      net.connect_tls("127.0.0.1", port, { ca_pem = fixture("other_ca.pem"), server_name = "localhost" })
    end)
    self:assert_true(require("hecate.core").is_instance_of(err, net.TlsError), tostring(err))
  end)
end

function T:test_name_mismatch_is_rejected()
  reactor.run(function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local port = listener:local_address().port
    serve_once(listener, net.tls.server_config(server_options()), function() end)
    local err = self:assert_error(function()
      net.connect_tls("127.0.0.1", port, { ca_pem = CA, server_name = "wrong.example" })
    end)
    self:assert_true(require("hecate.core").is_instance_of(err, net.TlsError), tostring(err))
  end)
end

function T:test_connect_tls_requires_trust_anchors_and_ignores_no_switch()
  reactor.run(function()
    local err = self:assert_error(function()
      ---@diagnostic disable-next-line: missing-fields
      net.connect_tls("127.0.0.1", 1, {})
    end)
    self:assert_true(require("hecate.core").is_instance_of(err, require("hecate.core").ArgumentError), tostring(err))
    -- There is no option that disables verification: an unknown key is a transport option.
    self:assert_equal("function", type(net.tls.client_config))
  end)
end

function T:test_truncation_without_close_notify_is_an_error()
  reactor.run(function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local port = listener:local_address().port
    serve_once(listener, net.tls.server_config(server_options()), function(tls)
      tls:write("partial") -- then closes the TCP stream without close_notify
    end)
    local client <close> = net.connect_tls("127.0.0.1", port, { ca_pem = CA, server_name = "localhost" })
    self:assert_equal("partial", client:read())
    local err = self:assert_error(function() client:read() end)
    self:assert_true(require("hecate.core").is_instance_of(err, net.TlsError), tostring(err))
  end)
end

function T:test_mutual_tls_requires_a_trusted_client_certificate()
  reactor.run(function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local port = listener:local_address().port
    local config = net.tls.server_config(server_options({ client_ca_pem = CA }))
    local outcome = serve_once(listener, config, function(tls)
      tls:write(tls:reader():read_line() .. "!")
      tls:shutdown()
    end)
    local client <close> = net.connect_tls("127.0.0.1", port, {
      ca_pem = CA, server_name = "localhost", cert_pem = fixture("client.pem"), key_pem = fixture("client.key"),
    })
    client:write("mtls\n")
    self:assert_equal("mtls!", client:read())
    reactor.sleep(0.05)
    self:assert_true(outcome.ok, tostring(outcome.value))
  end)
end

function T:test_deadline_cancelling_a_read_keeps_the_stream()
  reactor.run(function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local port = listener:local_address().port
    serve_once(listener, net.tls.server_config(server_options()), function(tls)
      reactor.sleep(0.2)
      tls:write("late")
      tls:shutdown()
    end)
    local client <close> = net.connect_tls("127.0.0.1", port, { ca_pem = CA, server_name = "localhost" })
    local ok = pcall(reactor.deadline, 0.05, function() return client:read() end)
    self:assert_false(ok)
    self:assert_equal("late", client:read())
  end)
end

function T:test_streams_are_closable()
  reactor.run(function()
    local listener <close> = net.listen("127.0.0.1", 0)
    local port = listener:local_address().port
    serve_once(listener, net.tls.server_config(server_options()), function(tls) tls:read() end)
    local client = net.connect_tls("127.0.0.1", port, { ca_pem = CA, server_name = "localhost" })
    self:assert_false(client:is_closed())
    client:close()
    client:close()
    self:assert_true(client:is_closed())
  end)
end

return T
