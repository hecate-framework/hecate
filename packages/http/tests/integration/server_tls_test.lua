---@diagnostic disable: missing-fields, param-type-mismatch, need-check-nil  -- the tests pass invalid arguments on purpose
-- The server over TLS on loopback, against the local test CA of packages/net/tests/fixtures: handshakes run in a
-- forked computation per connection, under a deadline, a byte budget and a concurrency limit.
local test = require("harness.test")
local reactor = require("hecate.reactor")
local net = require("hecate.net")
local log = require("hecate.log")
local http = require("hecate.http")
local T = test.Case("ServerTlsTest")

local available, reason = net.tls.available()
if not available then
  function T:test_skipped_native_module_not_built()
    -- CI must not skip silently: CI sets `CI` (and `HECATE_REQUIRE_TLS=1` when the TLS module is built).
    if os.getenv("HECATE_REQUIRE_TLS") == "1" or os.getenv("CI") then self:fail("TLS tests cannot run: " .. tostring(reason)) end
    print("# SKIP hecate.http TLS tests: " .. tostring(reason))
  end
  return T
end

local Parser = require("hecate.http.parser")
local Server = http.Server
local Response = http.Response

local function fixture(name)
  local path = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):gsub("/[^/]*$", "") .. "/../../../net/tests/fixtures/" .. name
  local f = assert(io.open(path, "rb"), "missing fixture " .. path)
  local s = f:read("a")
  f:close()
  return s
end

local CA = fixture("ca.pem")
local TLS = { cert_pem = fixture("server.pem"), key_pem = fixture("server.key") }

--- A client over TLS: `request(text)` returns `{ status, fields, content }`.
local Client = {}
Client.__index = Client

local function connect_tls(port)
  local stream = net.connect_tls("127.0.0.1", port, { system_roots = false, ca_pem = CA, server_name = "localhost" })
  return setmetatable({ stream = stream, parser = Parser.response(), queue = {} }, Client)
end

---@return any
function Client:request(text)
  self.stream:write(text)
  local response
  while true do
    while #self.queue > 0 do
      local event = table.remove(self.queue, 1)
      if event.type == "head" then
        response = { status = event.status, fields = event.fields, content = "" }
      elseif event.type == "data" then
        response.content = response.content .. event.data
      elseif event.type == "complete" then
        return response
      end
    end
    local chunk = reactor.deadline(10, self.stream.read, self.stream, 65536)
    if chunk == nil then return nil end
    local events, err = self.parser:feed(chunk)
    if err then error(err, 0) end
    for _, event in ipairs(events) do self.queue[#self.queue + 1] = event end
  end
end

function Client:close() self.stream:close() end
Client.__close = Client.close

local function get(path) return "GET " .. path .. " HTTP/1.1\r\nHost: localhost\r\n\r\n" end

--- Reads from a raw stream until it ends or fails; returns what arrived.
local function drain(stream)
  local parts = {}
  while true do
    local ok, chunk = pcall(reactor.deadline, 10, stream.read, stream, 65536)
    if not ok or chunk == nil then return table.concat(parts) end
    parts[#parts + 1] = chunk
  end
end

--- Runs `fn(port, server, records)` with a TLS server on port 0; `records()` lists what the server logged.
local function with_tls_server(self, action, options, fn)
  options = options or {}
  options.port = 0
  options.tls = options.tls or TLS
  local sink = log.MemorySink()
  options.logger = log.Logger({ sinks = { sink }, severity = "debug" })
  local before = reactor.Reactor.open_handles()
  reactor.run(function()
    local server = Server(action, options)
    local listener = server:listen()
    local serving = reactor.fork(server.serve, server, listener)
    local ok, err = pcall(reactor.deadline, 30, fn, listener:local_address().port, server, function() return sink:records() end)
    server:shutdown(2)
    serving:value()
    if not ok then error(err, 0) end
  end)
  self:assert_equal(before, reactor.Reactor.open_handles(), "libuv handles left open")
end

local function text_action(request)
  return Response(200, { content = request.method .. " " .. request.path .. " " .. tostring(request:peer_address().ip) })
end

function T:test_an_https_request_is_answered_and_the_connection_stays_alive()
  with_tls_server(self, text_action, nil, function(port)
    local client <close> = connect_tls(port)
    self:assert_equal("GET /a 127.0.0.1", client:request(get("/a")).content)
    self:assert_equal("GET /b 127.0.0.1", client:request(get("/b")).content)
  end)
end

function T:test_a_silent_client_does_not_block_others_and_is_dropped_at_the_handshake_deadline()
  with_tls_server(self, text_action, { handshake_timeout = 1 }, function(port)
    local silent <close> = net.connect("127.0.0.1", port)
    local dropped = reactor.fork(function()
      silent:read() -- nil when the server closes
      return true
    end)
    local client <close> = connect_tls(port) -- served while the silent client holds its handshake
    self:assert_equal(200, client:request(get("/")).status)
    self:assert_false(dropped:done(), "the silent client is not dropped before its deadline")
    self:assert_true(dropped:value())
  end)
end

function T:test_the_handshake_limit_queues_the_excess_until_a_slot_is_free()
  local order = {}
  with_tls_server(self, text_action, { handshake_timeout = 1, max_handshakes = 1 }, function(port)
    local silent <close> = net.connect("127.0.0.1", port) -- takes the only slot
    local first = reactor.fork(function()
      silent:read()
      order[#order + 1] = "silent dropped"
    end)
    local second = reactor.fork(function()
      local client <close> = connect_tls(port) -- accepted by the kernel, not yet by the server
      local status = client:request(get("/")).status
      order[#order + 1] = "served " .. status
    end)
    reactor.join(first, second)
    self:assert_equal("silent dropped", order[1])
    self:assert_equal("served 200", order[2])
  end)
end

function T:test_plain_text_sent_to_a_tls_port_is_dropped_without_detail_and_logged_server_side()
  with_tls_server(self, text_action, nil, function(port, _, records)
    local raw <close> = net.connect("127.0.0.1", port)
    local local_port = raw:local_address().port
    raw:write("GET / HTTP/1.1\r\nHost: localhost\r\n\r\n")
    local received = drain(raw)
    self:assert_nil(received:find("HTTP/1", 1, true), "no HTTP answer on a failed handshake")
    for _, word in ipairs({ "rustls", "TlsError", "handshake", "Hecate", "hecate" }) do
      self:assert_nil(received:find(word, 1, true), word)
    end
    local seen
    for _, record in ipairs(records()) do
      if record.message:find("TLS handshake failed", 1, true) then seen = record end
    end
    self:assert_not_nil(seen, "the failure is logged")
    self:assert_equal("127.0.0.1:" .. local_port, seen.fields.peer)
    self:assert_equal("string", type(seen.fields.reason))
  end)
end

function T:test_a_hello_beyond_the_byte_budget_is_dropped()
  with_tls_server(self, text_action, { max_handshake_bytes = 2048 }, function(port, _, records)
    local raw <close> = net.connect("127.0.0.1", port)
    -- A handshake record header announcing 8192 bytes, then more than the budget.
    pcall(raw.write, raw, "\22\3\1\32\0" .. ("a"):rep(6000))
    local received = drain(raw)
    self:assert_nil(received:find("HTTP/1", 1, true))
    local count = 0
    for _, record in ipairs(records()) do
      if record.message:find("TLS handshake failed", 1, true) then count = count + 1 end
    end
    self:assert_equal(1, count)
    local client <close> = connect_tls(port) -- the server is intact
    self:assert_equal(200, client:request(get("/")).status)
  end)
end

function T:test_shutdown_drops_connections_still_in_their_handshake()
  with_tls_server(self, text_action, { handshake_timeout = 20 }, function(port, server)
    local silent <close> = net.connect("127.0.0.1", port)
    local dropped = reactor.fork(function() silent:read() return true end)
    reactor.sleep(0.1)
    server:shutdown(5)
    self:assert_true(dropped:value())
  end)
end

function T:test_defaults_and_settings_of_tls()
  local d = Server.DEFAULTS
  self:assert_equal(10, d.handshake_timeout)
  self:assert_equal(64, d.max_handshakes)
  self:assert_equal(65536, d.max_handshake_bytes)
  local function bad(options) self:assert_error(function() Server(text_action, options) end) end
  bad({ handshake_timeout = 5 }) -- no tls: nothing to handshake
  bad({ max_handshakes = 4 })
  bad({ max_handshake_bytes = 4096 })
  bad({ tls = "cert.pem" })
  bad({ tls = TLS, max_handshakes = 0 })
  bad({ tls = TLS, max_handshake_bytes = 0 })
  bad({ tls = TLS, handshake_timeout = 0 })
  bad({ tls = { cert_pem = TLS.cert_pem } }) -- no key
  bad({ logger = "log" })
  Server(text_action, { tls = TLS, max_handshakes = 2, handshake_timeout = 1 })
  Server(text_action, { tls = net.tls.server_config(TLS) })
end

return T
