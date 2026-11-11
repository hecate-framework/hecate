---@diagnostic disable: missing-fields, param-type-mismatch, assign-type-mismatch  -- the tests pass invalid arguments on purpose
-- The server over a real loopback socket, inside the reactor, with a client written here over hecate.net.
local test = require("harness.test")
local core = require("hecate.core")
local json = require("hecate.json")
local reactor = require("hecate.reactor")
local net = require("hecate.net")
local http = require("hecate.http")
local log = require("hecate.log")
local Server = require("hecate.http.server")
local Parser = require("hecate.http.parser")
-- Without a logger the server writes to the standard error stream (OQ-79): tests keep it quiet.
local QUIET <const> = require("hecate.log").Logger({ sinks = { require("hecate.log").MemorySink() }, severity = "debug" })
local T = test.Case("ServerBehaviourTest")

local Response = http.Response

-- Client ----------------------------------------------------------------------------------------------------------

local Client = {}
Client.__index = Client

local function connect(port)
  local stream = net.connect("127.0.0.1", port)
  return setmetatable({ stream = stream, parser = Parser.response(), queue = {}, eof = false }, Client)
end

function Client:send(data) self.stream:write(data) end

---@return any
--- Reads one response (interim ones included): `{ status, fields, content, version }`; nil at the end of the connection.
function Client:read_response()
  local response
  while true do
    while #self.queue > 0 do
      local event = table.remove(self.queue, 1)
      if event.type == "head" then
        response = { status = event.status, fields = event.fields, version = event.version, content = "" }
      elseif event.type == "data" then
        response.content = response.content .. event.data
      elseif event.type == "complete" then
        return response
      end
    end
    if self.eof then
      if response then return response end
      return nil
    end
    local chunk = reactor.deadline(5, self.stream.read, self.stream, 65536)
    local events, err
    if chunk == nil then
      self.eof = true
      events, err = self.parser:finish()
    else
      events, err = self.parser:feed(chunk)
    end
    if err then error(err, 0) end
    for _, event in ipairs(events) do self.queue[#self.queue + 1] = event end
  end
end

--- The raw bytes until the peer closes (or the deadline).
function Client:read_until_close()
  local parts = {}
  while true do
    local chunk = reactor.deadline(5, self.stream.read, self.stream, 65536)
    if chunk == nil then return table.concat(parts) end
    parts[#parts + 1] = chunk
  end
end

function Client:request(text)
  self:send(text)
  return self:read_response()
end

function Client:close() self.stream:close() end
Client.__close = Client.close

local function get(path, extra)
  return "GET " .. path .. " HTTP/1.1\r\nHost: test\r\n" .. (extra or "") .. "\r\n"
end

--- Runs `fn(port, server)` in the reactor with a serving server; shuts down at the end and checks the serve ended.
--- `options.action` is the action; the other keys are the options of the server.
local function with_server(self, options, fn)
  local action = options.action
  options.action = nil
  options.port = 0
  local use_default = options.use_default_logger -- the one test of the default logger
  options.use_default_logger = nil
  if not use_default then options.logger = options.logger or QUIET end
  local before = reactor.Reactor.open_handles()
  reactor.run(function()
    local server = Server(action, options)
    local listener = server:listen()
    local serving = reactor.fork(server.serve, server, listener)
    local ok, err = pcall(reactor.deadline, 20, fn, listener:local_address().port, server)
    server:shutdown(2)
    serving:value()
    if not ok then error(err, 0) end
  end)
  self:assert_equal(before, reactor.Reactor.open_handles(), "libuv handles left open")
end

local function text_action(request)
  return Response(200, { content = request.method .. " " .. request.path })
end

-- Basics ----------------------------------------------------------------------------------------------------------

function T:test_the_request_carries_target_fields_peer_and_its_own_scope()
  local seen = {}
  with_server(self, {
    action = function(request)
      seen[#seen + 1] = {
        target = request.target, query = request.query, host = request.fields:get("Host"), scope = request.scope,
        peer = request:peer_address(), version = request.version, thread = coroutine.running(),
      }
      return Response(204)
    end,
  }, function(port)
    local client <close> = connect(port)
    client:request(get("/a?b=c"))
    client:request(get("/a?b=c"))
  end)
  self:assert_equal(2, #seen)
  self:assert_equal("/a?b=c", seen[1].target)
  self:assert_equal("b=c", seen[1].query)
  self:assert_equal("test", seen[1].host)
  self:assert_equal("127.0.0.1", seen[1].peer.ip)
  self:assert_not_nil(seen[1].scope)
  self:assert_true(seen[1].scope ~= seen[2].scope, "one scope per request")
  self:assert_true(seen[1].thread ~= seen[2].thread, "one coroutine per request")
end

function T:test_a_forked_computation_of_a_action_is_owned_by_the_request_scope()
  local order = {}
  with_server(self, {
    action = function()
      reactor.fork(function()
        reactor.sleep(0.05)
        order[#order + 1] = "child"
      end)
      return Response(200, { content = "x" })
    end,
  }, function(port, server)
    local client <close> = connect(port)
    client:request(get("/"))
    client:close()
    server:shutdown(2) -- drains: the request scope waits for its child
  end)
  self:assert_equal("child", order[1])
end

function T:test_keep_alive_serves_several_requests_then_connection_close_ends_it()
  with_server(self, { action = text_action }, function(port)
    local client <close> = connect(port)
    self:assert_equal("GET /a", client:request(get("/a")).content)
    self:assert_equal("GET /b", client:request(get("/b")).content)
    local last = client:request(get("/c", "Connection: close\r\n"))
    self:assert_equal("close", last.fields:get("Connection"))
    self:assert_nil(client:read_response())
  end)
end

function T:test_http_1_0_closes_unless_keep_alive_is_asked()
  with_server(self, { action = text_action }, function(port)
    local closing <close> = connect(port)
    local response = closing:request("GET /a HTTP/1.0\r\n\r\n")
    self:assert_equal(200, response.status) -- HTTP/1.0 needs no Host
    self:assert_equal("close", response.fields:get("Connection"))
    self:assert_nil(closing:read_response())
    local persistent <close> = connect(port)
    local kept = persistent:request("GET /a HTTP/1.0\r\nConnection: keep-alive\r\n\r\n")
    self:assert_equal("keep-alive", kept.fields:get("Connection"))
    self:assert_equal(200, persistent:request("GET /b HTTP/1.0\r\nConnection: keep-alive\r\n\r\n").status)
  end)
end

-- Host and malformed requests ---------------------------------------------------------------------------------------

function T:test_a_malformed_request_is_a_400_problem_without_the_parser_text()
  with_server(self, { action = text_action }, function(port)
    local client <close> = connect(port)
    local response = client:request("GET / HTTP/1.1\r\nHost: a\r\nContent-Length: 1\r\nTransfer-Encoding: chunked\r\n\r\n")
    self:assert_equal(400, response.status)
    local body = json.decode(response.content)
    self:assert_equal("The request is malformed.", body.detail)
    self:assert_nil(client:read_response())
  end)
end

function T:test_limits_of_the_parser_map_to_414_and_431()
  with_server(self, { action = text_action, parser = { max_target_size = 64, max_field_size = 64 } }, function(port)
    local long = connect(port)
    self:assert_equal(414, long:request(get("/" .. ("a"):rep(200))).status)
    long:close()
    local wide = connect(port)
    self:assert_equal(431, wide:request(get("/", "X-Big: " .. ("a"):rep(200) .. "\r\n")).status)
    wide:close()
  end)
end

function T:test_a_request_with_an_upgrade_is_refused_with_501()
  with_server(self, { action = text_action }, function(port)
    local client <close> = connect(port)
    local response = client:request(get("/ws", "Connection: Upgrade\r\nUpgrade: websocket\r\n"))
    self:assert_equal(501, response.status)
    self:assert_nil(client:read_response())
  end)
end

-- Content ---------------------------------------------------------------------------------------------------------

local function echo_action(request)
  return Response(200, { content = request:read_content() })
end

function T:test_chunked_request_content_is_read_whole_and_streamed()
  local chunks = {}
  with_server(self, {
    action = function(request)
      local reader = request:stream_content()
      while true do
        local chunk = reader:read()
        if chunk == nil then break end
        chunks[#chunks + 1] = chunk
      end
      return Response(200, { content = table.concat(chunks, "|") })
    end,
  }, function(port)
    local client <close> = connect(port)
    client:send("POST /e HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nabc\r\n")
    reactor.sleep(0) -- the server reads the first chunk before the rest is sent
    client:send("2\r\nde\r\n0\r\n\r\n")
    local response = client:read_response()
    self:assert_equal(200, response.status)
    self:assert_equal("abc|de", response.content)
  end)
end

function T:test_content_over_the_limit_is_a_413_before_the_action_runs()
  local called = false
  with_server(self, {
    max_content = 10,
    action = function() called = true; return Response(200) end,
  }, function(port)
    local client <close> = connect(port)
    local response = client:request("POST /e HTTP/1.1\r\nHost: t\r\nContent-Length: 11\r\n\r\n")
    self:assert_equal(413, response.status)
    self:assert_equal("close", response.fields:get("Connection"))
  end)
  self:assert_false(called)
end

function T:test_chunked_content_over_the_limit_is_a_413_from_the_action_read()
  with_server(self, { max_content = 4, action = echo_action }, function(port)
    local client <close> = connect(port)
    local response = client:request("POST /e HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nabcde\r\n0\r\n\r\n")
    self:assert_equal(413, response.status)
    self:assert_equal("application/problem+json", response.fields:get("Content-Type"))
    self:assert_nil(client:read_response())
  end)
end

function T:test_unread_content_is_drained_so_the_next_request_is_served()
  with_server(self, { action = text_action }, function(port)
    local client <close> = connect(port)
    client:send("POST /a HTTP/1.1\r\nHost: t\r\nContent-Length: 4\r\n\r\nabcd" .. get("/b"))
    self:assert_equal("POST /a", client:read_response().content)
    self:assert_equal("GET /b", client:read_response().content)
  end)
end

function T:test_expect_100_continue_is_sent_when_the_action_reads()
  with_server(self, { action = echo_action }, function(port)
    local client <close> = connect(port)
    client:send("POST /e HTTP/1.1\r\nHost: t\r\nContent-Length: 3\r\nExpect: 100-continue\r\n\r\n")
    local interim = client:read_response()
    self:assert_equal(100, interim.status)
    client:send("xyz")
    local final = client:read_response()
    self:assert_equal(200, final.status)
    self:assert_equal("xyz", final.content)
  end)
end

function T:test_expect_100_continue_is_not_sent_when_the_action_does_not_read_and_the_connection_closes()
  with_server(self, { action = text_action }, function(port)
    local client <close> = connect(port)
    client:send("POST /e HTTP/1.1\r\nHost: t\r\nContent-Length: 3\r\nExpect: 100-continue\r\n\r\n")
    local response = client:read_response()
    self:assert_equal(200, response.status)
    self:assert_equal("close", response.fields:get("Connection"))
  end)
end

-- Responses -------------------------------------------------------------------------------------------------------

function T:test_a_function_without_length_is_sent_chunked()
  with_server(self, {
    action = function()
      return Response(200, { content = function(write, flush_content)
        write("one,")
        flush_content()
        write("")
        write("two")
      end })
    end,
  }, function(port)
    local client <close> = connect(port)
    local response = client:request(get("/"))
    self:assert_equal("chunked", response.fields:get("Transfer-Encoding"))
    self:assert_nil(response.fields:get("Content-Length"))
    self:assert_equal("one,two", response.content)
    self:assert_equal(200, client:request(get("/")).status) -- the connection is intact
  end)
end

function T:test_a_function_with_a_declared_length_is_sent_raw()
  with_server(self, {
    action = function()
      local fields = http.Fields({ { "Content-Length", "6" } })
      return Response(200, { fields = fields, content = function(write, flush_content) write("abc"); write("def") end })
    end,
  }, function(port)
    local client <close> = connect(port)
    local response = client:request(get("/"))
    self:assert_equal("6", response.fields:get("Content-Length"))
    self:assert_nil(response.fields:get("Transfer-Encoding"))
    self:assert_equal("abcdef", response.content)
  end)
end

function T:test_a_writer_that_breaks_its_declared_length_closes_the_connection()
  with_server(self, {
    action = function()
      return Response(200, { fields = http.Fields({ { "Content-Length", "6" } }), content = function(write, flush_content) write("abc") end })
    end,
  }, function(port)
    local client <close> = connect(port)
    client:send(get("/"))
    local raw = client:read_until_close()
    self:assert_not_nil(raw:find("Content%-Length: 6"))
  end)
end

function T:test_a_table_is_an_error_answered_with_the_generic_500_and_logged()
  -- OQ-76 a: http never serialises; a table reaching the server (set after construction) is a failure of the action, not JSON.
  local sink = log.MemorySink()
  local reported = {}
  with_server(self, {
    action = function()
      local response = Response(200)
      response.content = { id = 42, secret = "hunter2" } -- bypasses the constructor
      return response
    end,
    logger = log.Logger({ sinks = { sink }, severity = "debug" }),
    on_error = function(err) reported[#reported + 1] = err end,
  }, function(port)
    local client <close> = connect(port)
    local response = client:request(get("/"))
    self:assert_equal(500, response.status)
    self:assert_equal("application/problem+json", response.fields:get("Content-Type"))
    self:assert_nil(response.content:find("hunter2", 1, true))
    self:assert_equal(500, client:request(get("/")).status) -- the connection stays usable
  end)
  self:assert_equal(2, #reported)
  local failures = {}
  for _, record in ipairs(sink:records()) do
    if record.message:find("the action failed", 1, true) then failures[#failures + 1] = record end
  end
  self:assert_equal(2, #failures)
  self:assert_equal("error", failures[1].severity.name or tostring(failures[1].severity))
  self:assert_equal("GET", failures[1].fields.method)
  self:assert_equal("/", failures[1].fields.path)
end

function T:test_without_a_logger_the_server_logs_through_the_default_logger_and_an_explicit_logger_replaces_it()
  local default_sink, own_sink = log.MemorySink(), log.MemorySink()
  local previous = log.default()
  log.set_default(log.Logger({ sinks = { default_sink }, severity = "debug" }))
  local function boom() error("boom") end
  local ok, err = pcall(function()
    with_server(self, { action = boom, use_default_logger = true }, function(port)
      local client <close> = connect(port)
      self:assert_equal(500, client:request(get("/x")).status)
    end)
    with_server(self, { action = boom, logger = log.Logger({ sinks = { own_sink }, severity = "debug" }) }, function(port)
      local client <close> = connect(port)
      self:assert_equal(500, client:request(get("/y")).status)
    end)
  end)
  log.set_default(previous)
  if not ok then error(err, 0) end
  local function messages(sink, needle)
    local found = {}
    for _, record in ipairs(sink:records()) do
      if record.message:find(needle, 1, true) then found[#found + 1] = record end
    end
    return found
  end
  -- the default logger got the listening address and the error of the first server, and nothing of the second
  self:assert_equal(1, #messages(default_sink, "listening on"))
  local failed = messages(default_sink, "the action failed")
  self:assert_equal(1, #failed)
  self:assert_equal("/x", failed[1].fields.path)
  self:assert_equal(1, #messages(own_sink, "listening on"))
  self:assert_equal("/y", messages(own_sink, "the action failed")[1].fields.path)
end

function T:test_head_has_no_content_but_the_length_of_the_representation()
  with_server(self, { action = function() return Response(200, { content = "hello" }) end }, function(port)
    local client <close> = connect(port)
    client.parser:skip_content()
    local response = client:request("HEAD / HTTP/1.1\r\nHost: t\r\n\r\n")
    self:assert_equal("5", response.fields:get("Content-Length"))
    self:assert_equal("", response.content)
    self:assert_equal(200, client:request(get("/")).status) -- no stray bytes after the head
  end)
end

function T:test_204_and_304_carry_neither_content_nor_framing_of_their_own()
  with_server(self, {
    action = function(request)
      if request.path == "/204" then return Response(204) end
      local response = Response(304)
      response.content = "must not be sent"
      response.fields:set("Transfer-Encoding", "chunked")
      return response
    end,
  }, function(port)
    local client <close> = connect(port)
    local none = client:request(get("/204"))
    self:assert_equal(204, none.status)
    self:assert_nil(none.fields:get("Content-Length"))
    self:assert_nil(none.fields:get("Transfer-Encoding"))
    local not_modified = client:request(get("/304"))
    self:assert_equal(304, not_modified.status)
    self:assert_equal("", not_modified.content)
    self:assert_nil(not_modified.fields:get("Transfer-Encoding"))
    self:assert_equal(204, client:request(get("/204")).status)
  end)
end

function T:test_a_action_cannot_inject_framing_fields_or_a_reason_with_line_breaks()
  with_server(self, {
    action = function()
      local response = Response(200, { content = "ok", reason = "OK\r\nX-Evil: 1" })
      response.fields:set("Content-Length", "999")
      response.fields:set("Transfer-Encoding", "chunked")
      return response
    end,
  }, function(port)
    local client <close> = connect(port)
    local response = client:request(get("/"))
    self:assert_equal("2", response.fields:get("Content-Length"))
    self:assert_nil(response.fields:get("X-Evil"))
    self:assert_equal("ok", response.content)
  end)
end

-- Errors ----------------------------------------------------------------------------------------------------------

function T:test_a_action_error_is_a_generic_problem_and_the_connection_stays_usable()
  with_server(self, {
    action = function(request)
      if request.path == "/boom" then error("database password is hunter2 at /srv/app/secret.lua:12") end
      return Response(200, { content = "fine" })
    end,
  }, function(port)
    local client <close> = connect(port)
    local response = client:request(get("/boom"))
    self:assert_equal(500, response.status)
    self:assert_equal("application/problem+json", response.fields:get("Content-Type"))
    self:assert_nil(response.content:find("hunter2", 1, true))
    self:assert_nil(response.content:find("secret", 1, true))
    self:assert_equal("fine", client:request(get("/ok")).content)
  end)
end

function T:test_a_transport_error_of_a_action_never_reaches_the_client()
  with_server(self, {
    action = function()
      error(reactor.TransportError({
        message = "net.connect: connect to db.internal:5432 failed: ECONNREFUSED (tried 10.1.2.3, 10.1.2.4)",
        context = { errno = "ECONNREFUSED", host = "db.internal", port = 5432,
          attempts = { { address = "10.1.2.3", errno = "ECONNREFUSED" } } },
      }), 0)
    end,
  }, function(port)
    local client <close> = connect(port)
    local response = client:request(get("/"))
    self:assert_equal(500, response.status)
    local detail = json.decode(response.content).detail
    self:assert_equal("A network operation of the server failed.", detail)
    for _, secret in ipairs({ "10.1.2", "ECONNREFUSED", "db.internal", "5432", "attempts" }) do
      self:assert_nil(response.content:find(secret, 1, true), secret)
    end
  end)
end

function T:test_a_action_that_returns_nothing_or_a_string_is_a_500()
  with_server(self, {
    action = function(request)
      if request.path == "/string" then return "text" end
    end,
  }, function(port)
    local client <close> = connect(port)
    self:assert_equal(500, client:request(get("/string")).status)
    self:assert_equal(500, client:request(get("/nothing")).status)
  end)
end

-- Timeouts, limits of connections and shutdown ---------------------------------------------------------------------

function T:test_an_idle_connection_is_closed_after_the_idle_timeout()
  with_server(self, { action = text_action, idle_timeout = 0.3 }, function(port)
    local client <close> = connect(port)
    self:assert_equal(200, client:request(get("/")).status)
    self:assert_nil(client:read_response()) -- closed by the server, without a response
  end)
end

function T:test_a_head_that_does_not_complete_is_a_408_after_the_head_timeout()
  with_server(self, { action = text_action, head_timeout = 0.1 }, function(port)
    local client <close> = connect(port)
    client:send("GET / HTTP/1.1\r\nHost: t\r\nX-Slow: ")
    local response = client:read_response()
    self:assert_equal(408, response.status)
    self:assert_equal("close", response.fields:get("Connection"))
  end)
end

function T:test_stalled_request_content_is_a_408_after_the_content_timeout()
  with_server(self, { action = echo_action, content_timeout = 0.1 }, function(port)
    local client <close> = connect(port)
    client:send("POST /e HTTP/1.1\r\nHost: t\r\nContent-Length: 10\r\n\r\nabc")
    self:assert_equal(408, client:read_response().status)
  end)
end

function T:test_connections_beyond_the_maximum_wait_in_the_backlog()
  local started = {}
  with_server(self, {
    max_connections = 1,
    action = function(request)
      started[#started + 1] = request.path
      return Response(200, { content = request.path })
    end,
  }, function(port)
    local first <close> = connect(port)
    self:assert_equal("/one", first:request(get("/one")).content)
    local second <close> = connect(port) -- accepted by the kernel, not yet by the server
    second:send(get("/two"))
    reactor.sleep(0.1)
    self:assert_equal(1, #started)
    first:close()
    self:assert_equal("/two", second:read_response().content)
  end)
end

function T:test_shutdown_stops_accepting_closes_idle_connections_and_drains_requests_in_flight()
  local release = reactor.Semaphore(0)
  local entered = reactor.Semaphore(0) -- released when the slow action has started
  local order = {}
  with_server(self, {
    action = function(request)
      if request.path == "/slow" then
        order[#order + 1] = "start"
        entered:release()
        release:acquire()
        order[#order + 1] = "finish"
      end
      return Response(200, { content = request.path })
    end,
  }, function(port, server)
    local idle <close> = connect(port)
    self:assert_equal(200, idle:request(get("/idle")).status)
    local busy <close> = connect(port)
    busy:send(get("/slow"))
    entered:acquire() -- the action runs
    local stopping = reactor.fork(server.shutdown, server, 5)
    reactor.sleep(0) -- the shutdown starts
    self:assert_true(server:is_stopping())
    self:assert_nil(idle:read_response(), "an idle connection is closed at once")
    local refused = pcall(function()
      local late = net.connect("127.0.0.1", port)
      late:close()
    end)
    self:assert_false(refused, "the listener is closed")
    release:release()
    local response = busy:read_response()
    self:assert_equal("/slow", response.content)
    self:assert_equal("close", response.fields:get("Connection"))
    stopping:value()
    self:assert_equal("finish", order[2])
  end)
end

function T:test_shutdown_cancels_requests_still_running_after_the_grace()
  local cancelled = false
  local entered = reactor.Semaphore(0)
  with_server(self, {
    action = function()
      entered:release()
      local ok, err = pcall(reactor.sleep, 30)
      cancelled = not ok and core.is_instance_of(err, core.CancellationError)
      error(err, 0)
    end,
  }, function(port, server)
    local client <close> = connect(port)
    client:send(get("/"))
    entered:acquire()
    local started = reactor.now()
    server:shutdown(0.1)
    self:assert_true(reactor.now() - started < 3)
  end)
  self:assert_true(cancelled)
end

-- Parser lifecycle and chunk size -----------------------------------------------------------------------------------

function T:test_the_parser_is_closed_when_the_connection_ends_and_fed_chunks_within_the_read_buffer()
  local closed, largest = 0, 0
  local close, feed = Parser.close, Parser.feed
  Parser.close = function(parser) closed = closed + 1; return close(parser) end
  Parser.feed = function(parser, chunk)
    if parser._kind == "request" and #chunk > largest then largest = #chunk end
    return feed(parser, chunk)
  end
  local ok, err = pcall(with_server, self, { action = echo_action, max_content = 1 << 20 }, function(port)
    for _ = 1, 2 do
      local client <close> = connect(port)
      local content = ("x"):rep(200000)
      client:send("POST /e HTTP/1.1\r\nHost: t\r\nContent-Length: " .. #content .. "\r\n\r\n" .. content)
      self:assert_equal(#content, #client:read_response().content)
    end
  end) -- `with_server` returns when every connection has ended, so the parsers are closed by now
  Parser.close, Parser.feed = close, feed
  if not ok then error(err, 0) end
  self:assert_true(largest > 0 and largest <= 16384, "largest chunk fed: " .. largest)
  self:assert_true(closed >= 2, "parsers closed: " .. closed)
end

function T:test_a_burst_of_pipelined_requests_filling_the_read_buffer_is_answered_in_order()
  with_server(self, { action = function(request) return Response(200, { content = request.path }) end }, function(port)
    local client <close> = connect(port)
    local burst, count = {}, 499 -- about 16 KiB: one read of the server holds hundreds of messages
    for i = 1, count do burst[i] = get("/" .. i) end
    local text = table.concat(burst)
    self:assert_true(#text >= 14000 and #text <= 16384, "burst of " .. #text .. " bytes")
    client:send(text)
    for i = 1, count do self:assert_equal("/" .. i, client:read_response().content) end
  end)
end

-- Settings --------------------------------------------------------------------------------------------------------

function T:test_defaults_are_the_documented_values()
  local d = Server.DEFAULTS
  self:assert_equal("127.0.0.1", d.host)
  self:assert_nil(d.max_connections, "no limit on connections by default")
  self:assert_equal(1048576, d.max_content)
  self:assert_equal(60, d.head_timeout)
  self:assert_equal(75, d.idle_timeout)
  self:assert_equal(60, d.content_timeout)
  self:assert_equal(60, d.write_timeout)
end

--- A listener whose first `failures[i]` accepts raise EMFILE, each burst ending after the next success.
local function flaky(real, bursts)
  local fake = { calls = 0, failed = 0, bursts = bursts, successes = 0 }
  function fake.accept()
    fake.calls = fake.calls + 1
    local burst = fake.bursts[fake.successes + 1]
    if burst and fake.failed < burst then
      fake.failed = fake.failed + 1
      error(reactor.TransportError({
        message = "net.TcpListener.accept: EMFILE too many open files at 10.0.0.1",
        context = { errno = "EMFILE", operation = "accept" },
      }), 0)
    end
    fake.failed = 0
    fake.successes = fake.successes + 1
    return real:accept()
  end
  function fake.close() real:close() end
  function fake.is_closed() return real:is_closed() end
  function fake.local_address() return real:local_address() end
  return fake
end

function T:test_the_accept_loop_survives_descriptor_exhaustion_and_logs_once_per_burst()
  local sink = log.MemorySink()
  local before = reactor.Reactor.open_handles()
  local fake
  reactor.run(function()
    local real = net.listen("127.0.0.1", 0)
    -- Burst of 3 failures before the first connection, then 2 before the second.
    fake = flaky(real, { 3, 2 })
    local server = Server(text_action, { logger = log.Logger({ sinks = { sink }, severity = "debug" }) })
    local serving = reactor.fork(server.serve, server, fake)
    local port = real:local_address().port
    local started = reactor.now()
    local first <close> = connect(port)
    self:assert_equal("GET /a", first:request(get("/a")).content) -- served after the failures
    self:assert_true(reactor.now() - started >= 0.1, "the loop backed off instead of spinning")
    local second <close> = connect(port)
    self:assert_equal("GET /b", second:request(get("/b")).content)
    self:assert_equal("GET /c", first:request(get("/c")).content) -- existing connections kept serving
    server:shutdown(2)
    serving:value()
  end)
  self:assert_equal(before, reactor.Reactor.open_handles())
  local logged = 0
  for _, record in ipairs(sink:records()) do
    if record.message:find("accept failed", 1, true) then
      logged = logged + 1
      self:assert_nil(tostring(record.fields.peer or ""):find("10.0.0.1", 1, true))
      self:assert_equal("EMFILE", record.fields.reason)
    end
  end
  self:assert_equal(2, logged, "one record per burst, not per failure")
  self:assert_true(fake.calls <= 8, "no spinning: " .. fake.calls .. " accepts")
end

function T:test_the_default_host_is_numeric_loopback()
  reactor.run(function()
    local server = Server(text_action, { port = 0, logger = QUIET })
    local listener = server:listen()
    self:assert_equal("127.0.0.1", listener:local_address().ip)
    listener:close()
  end)
end

function T:test_settings_are_validated()
  local function bad(options) self:assert_error(function() Server(text_action, options) end) end
  self:assert_error(function() Server() end)
  self:assert_error(function() Server("no") end)
  bad({ host = "localhost" })
  bad({ host = "example.org" })
  bad({ host = "999.1.1.1" })
  bad({ host = "" })
  bad({ port = 70000 })
  bad({ max_connections = 0 })
  bad({ max_content = -1 })
  bad({ head_timeout = 0 })
  bad({ idle_timeout = math.huge })
  bad({ write_timeout = "1" })
  bad({ parser = { max_fields = 0 } })
  bad({ unknown = true })
  bad({ tls = {} })
  Server(text_action, { host = "::1" })
  Server(text_action, { host = "0.0.0.0" })
  Server(text_action, { host = "::" })
end

-- on_response (OQ-81) ----------------------------------------------------------------------------------------------

function T:test_on_response_reports_each_answer_with_status_bytes_and_duration()
  local seen = {}
  with_server(self, { action = text_action, on_response = function(info) seen[#seen + 1] = info end }, function(port)
    local client <close> = connect(port)
    self:assert_equal("GET /a", client:request(get("/a?token=x")).content)
  end)
  self:assert_equal(1, #seen)
  self:assert_equal("GET", seen[1].method)
  self:assert_equal("/a?token=x", seen[1].target)
  self:assert_equal(200, seen[1].status)
  self:assert_true(seen[1].bytes > #"GET /a")
  self:assert_true(seen[1].duration >= 0)
  self:assert_equal(false, seen[1].failed)
  self:assert_equal(false, seen[1].refused)
end

function T:test_on_response_marks_the_answers_sent_before_any_action_runs()
  local seen = {}
  local ran = false
  local action = function() ran = true; return Response(200) end
  with_server(self, { action = action, on_response = function(info) seen[#seen + 1] = info end }, function(port)
    local client <close> = connect(port)
    client:send("GET / HTTP/1.1\r\n\r\n") -- no Host field: 400
    client:read_response()
  end)
  self:assert_false(ran)
  self:assert_equal(1, #seen)
  self:assert_equal(400, seen[1].status)
  self:assert_equal(true, seen[1].refused)
end

function T:test_a_failing_on_response_hook_does_not_affect_the_response()
  with_server(self, { action = text_action, on_response = function() error("boom") end }, function(port)
    local client <close> = connect(port)
    self:assert_equal("GET /a", client:request(get("/a")).content)
    self:assert_equal("GET /b", client:request(get("/b")).content)
  end)
end

function T:test_on_response_must_be_a_function()
  self:assert_error(function() Server(text_action, { on_response = 1 }) end)
end

return T
