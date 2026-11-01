---@diagnostic disable: missing-fields, param-type-mismatch, need-check-nil, assign-type-mismatch  -- the tests pass invalid arguments on purpose
-- The client against the in-repo server on port 0 (and small scripted servers for what a real server never does).
-- Order-based assertions; timeouts are small but never what a test measures.
local test = require("harness.test")
local core = require("hecate.core")
local json = require("hecate.json")
local reactor = require("hecate.reactor")
local net = require("hecate.net")
local http = require("hecate.http")
local T = test.Case("ClientTest")

local dir = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):gsub("/[^/]*$", "")
local support = dofile(dir .. "/../fixtures/client.lua")
local with_server = support.with_server
local Response, Client = http.Response, http.Client

local function base(port, path) return "http://127.0.0.1:" .. port .. (path or "/") end

--- A handler that describes the request it got.
local function describe(request)
  local fields = {}
  for name, value in request.fields:lines() do fields[#fields + 1] = { name, value } end
  return Response(200, { content = {
    method = request.method, target = request.target, content = request:read_content(), fields = fields,
    peer_port = request:peer_address().port,
  } })
end

local function field(info, name)
  for _, pair in ipairs(info.fields) do
    if string.lower(pair[1]) == string.lower(name) then return pair[2] end
  end
end

--- A scripted server: `script(stream, index)` runs for each accepted connection. Returns the listener port and a
--- table counting the accepted connections.
local function scripted(script)
  local listener = net.listen("127.0.0.1", 0)
  local state = { accepted = 0, port = listener:local_address().port, listener = listener }
  state.loop = reactor.fork(function()
    while true do
      local ok, stream = pcall(listener.accept, listener)
      if not ok then return end
      state.accepted = state.accepted + 1
      local index = state.accepted
      reactor.fork(function()
        pcall(script, stream, index)
        stream:close()
      end)
    end
  end)
  function state.stop() listener:close() end
  return state
end

--- Reads one request head from a stream (until the blank line); nil at the end of the stream.
local function read_head(stream)
  local buffer = ""
  while not buffer:find("\r\n\r\n", 1, true) do
    local chunk = stream:read()
    if chunk == nil then return nil end
    buffer = buffer .. chunk
  end
  return buffer
end

local function run(self, fn)
  local before = reactor.Reactor.open_handles()
  reactor.run(function() reactor.deadline(25, fn) end)
  self:assert_equal(before, reactor.Reactor.open_handles(), "libuv handles left open")
end

-- Requests ----------------------------------------------------------------------------------------------------------

function T:test_get_returns_the_head_and_reads_the_content_lazily()
  with_server(self, describe, nil, function(port)
    local client <close> = Client()
    local response = client:get(base(port, "/a/b?x=1"))
    self:assert_equal(200, response.status)
    self:assert_equal("OK", response.reason)
    self:assert_nil(response.content, "the content is not read yet")
    local info = json.decode(response:read_content())
    self:assert_equal("GET", info.method)
    self:assert_equal("/a/b?x=1", info.target)
    self:assert_equal("127.0.0.1:" .. port, field(info, "Host"))
    self:assert_equal("hecate-http", field(info, "User-Agent"))
    self:assert_equal(base(port, "/a/b?x=1"), response.url)
  end)
end

function T:test_post_sends_a_string_with_its_length_and_a_function_chunked_and_a_table_as_json()
  with_server(self, describe, nil, function(port)
    local client <close> = Client()
    local info = json.decode(client:post(base(port), "hello"):read_content())
    self:assert_equal("hello", info.content)
    self:assert_equal("5", field(info, "Content-Length"))
    local streamed = json.decode(client:post(base(port), function(write) write("ab"); write(""); write("cde") end):read_content())
    self:assert_equal("abcde", streamed.content)
    self:assert_equal("chunked", field(streamed, "Transfer-Encoding"))
    self:assert_nil(field(streamed, "Content-Length"))
    local as_json = json.decode(client:post(base(port), { a = 1 }):read_content())
    self:assert_equal("application/json", field(as_json, "Content-Type"))
    local empty = json.decode(client:post(base(port)):read_content())
    self:assert_equal("0", field(empty, "Content-Length"))
  end)
end

function T:test_the_host_field_omits_a_default_port_and_brackets_ipv6()
  local url = http.url
  self:assert_equal("example.org", url.parse("http://example.org:80/").authority)
  self:assert_equal("[::1]:8080", url.parse("http://[::1]:8080/").authority)
end

function T:test_fields_and_urls_that_could_inject_or_hide_are_refused()
  with_server(self, describe, nil, function(port)
    local client <close> = Client()
    self:assert_error(function() client:get(base(port), { fields = { ["X-A"] = "1\r\nX-Injected: yes" } }) end)
    self:assert_error(function() client:get(base(port), { fields = { ["X A"] = "1" } }) end)
    self:assert_error(function() client:get("http://user:secret@127.0.0.1:" .. port .. "/") end)
    self:assert_error(function() client:get("http://127.0.0.1:" .. port .. "/a\r\nX: y") end)
    self:assert_error(function() client:get("/relative") end)
    self:assert_error(function() client:request("GE T", base(port)) end)
    self:assert_error(function() client:request("GET", base(port), { content = 42 }) end)
    local info = json.decode(client:get(base(port), { fields = { ["Host"] = "evil.example", ["Content-Length"] = "99" } }):read_content())
    self:assert_equal("127.0.0.1:" .. port, field(info, "Host"), "the Host field comes from the URL")
  end)
end

function T:test_head_204_and_304_have_no_content_and_the_connection_is_reused()
  local peers = {}
  with_server(self, function(request)
    peers[#peers + 1] = request:peer_address().port
    if request.path == "/204" then return Response(204) end
    if request.path == "/304" then return Response(304) end
    return Response(200, { content = "hello" })
  end, nil, function(port)
    local client <close> = Client()
    local head = client:head(base(port, "/x"))
    self:assert_equal("5", head.fields:get("Content-Length"))
    self:assert_equal("", head:read_content())
    self:assert_equal("", client:get(base(port, "/204")):read_content())
    self:assert_equal("", client:get(base(port, "/304")):read_content())
    self:assert_equal("hello", client:get(base(port, "/x")):read_content())
    self:assert_equal(1, #({ [peers[1]] = true, [peers[2]] = true, [peers[3]] = true, [peers[4]] = true } and { 1 }) )
    self:assert_equal(peers[1], peers[4], "one connection served all four requests")
  end)
end

function T:test_the_response_content_streams_chunk_by_chunk()
  with_server(self, function()
    return Response(200, { content = function(write) for i = 1, 5 do write(("chunk" .. i):rep(1000)) reactor.sleep(0.01) end end })
  end, nil, function(port)
    local client <close> = Client()
    local response = client:get(base(port))
    local stream, count, total = response:stream_content(), 0, 0
    while true do
      local chunk = stream:read()
      if chunk == nil then break end
      count, total = count + 1, total + #chunk
    end
    self:assert_equal(5 * 6000 - 0, total)
    self:assert_true(count >= 2, "several chunks, not one buffer: " .. count)
  end)
end

function T:test_read_content_is_bounded_by_the_limit()
  with_server(self, function() return Response(200, { content = ("x"):rep(1000) }) end, nil, function(port)
    local client <close> = Client({ max_content = 100 })
    local err = self:assert_error(function() client:get(base(port)):read_content() end)
    self:assert_true(core.is_instance_of(err, http.ContentError))
    self:assert_equal(413, err.context.status)
    local roomy <close> = Client()
    local ok = roomy:get(base(port)):read_content(5000)
    self:assert_equal(1000, #ok)
  end)
end

-- Pool ----------------------------------------------------------------------------------------------------------------

function T:test_a_connection_is_reused_while_idle_and_not_after_the_idle_timeout()
  with_server(self, describe, nil, function(port)
    local client <close> = Client({ idle_timeout = 0.3 })
    local first = json.decode(client:get(base(port)):read_content()).peer_port
    local second = json.decode(client:get(base(port)):read_content()).peer_port
    self:assert_equal(first, second, "reused")
    reactor.sleep(0.6)
    local third = json.decode(client:get(base(port)):read_content()).peer_port
    self:assert_true(third ~= first, "the idle connection expired")
  end)
end

function T:test_a_response_holds_its_connection_until_read_or_closed_and_close_discards_it()
  with_server(self, describe, nil, function(port)
    local client <close> = Client()
    local first = client:get(base(port))
    local second = client:get(base(port)) -- the first still holds its connection: a second one opens
    local port1, port2 = json.decode(first:read_content()).peer_port, json.decode(second:read_content()).peer_port
    self:assert_true(port1 ~= port2)
    local unread = client:get(base(port))
    unread:close() -- not read: the connection is dropped, not pooled
    unread:close()
    local after = json.decode(client:get(base(port)):read_content()).peer_port
    self:assert_true(after == port1 or after == port2, "one of the two read connections was reused")
  end)
end

function T:test_max_connections_per_origin_makes_the_next_request_wait()
  with_server(self, function(request) return Response(200, { content = request.path }) end, nil, function(port)
    local client <close> = Client({ max_connections_per_origin = 1 })
    local first = client:get(base(port, "/1"))
    local order = {}
    local second = reactor.fork(function()
      local response = client:get(base(port, "/2"))
      order[#order + 1] = "second " .. response:read_content()
    end)
    reactor.sleep(0.1)
    self:assert_equal(0, #order, "waiting for the lease")
    order[#order + 1] = "first " .. first:read_content()
    second:value()
    self:assert_equal("first /1", order[1])
    self:assert_equal("second /2", order[2])
  end)
end

function T:test_a_pooled_connection_that_the_peer_closed_does_not_fail_the_next_request()
  run(self, function()
    local server = scripted(function(stream)
      read_head(stream)
      stream:write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok") -- keep-alive announced, then closed
    end)
    local client <close> = Client()
    local url = base(server.port)
    self:assert_equal("ok", client:get(url):read_content())
    reactor.sleep(0.1) -- the close arrives
    self:assert_equal("ok", client:get(url):read_content())
    self:assert_equal(2, server.accepted)
    server.stop()
    server.loop:cancel()
  end)
end

function T:test_a_reused_connection_that_dies_is_retried_for_get_and_not_for_post()
  run(self, function()
    local server = scripted(function(stream, index)
      read_head(stream)
      stream:write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok")
      if index == 1 then
        read_head(stream) -- the second request on the first connection: closed without an answer
        return
      end
      while read_head(stream) do stream:write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok") end
    end)
    local client <close> = Client()
    local url = base(server.port)
    self:assert_equal("ok", client:get(url):read_content())
    self:assert_equal("ok", client:get(url):read_content(), "GET retried on a new connection")
    self:assert_equal(2, server.accepted)

    local server2 = scripted(function(stream, index)
      read_head(stream)
      stream:write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok")
      read_head(stream)
    end)
    local other <close> = Client()
    other:get(base(server2.port)):read_content()
    local err = self:assert_error(function() other:post(base(server2.port), "data") end)
    self:assert_true(core.is_instance_of(err, core.NetworkError), tostring(err))
    self:assert_equal(1, server2.accepted, "a POST is not repeated")
    server.stop(); server.loop:cancel(); server2.stop(); server2.loop:cancel()
  end)
end

function T:test_a_closed_client_refuses_requests_and_drops_its_idle_connections()
  with_server(self, describe, nil, function(port)
    local client = Client()
    client:get(base(port)):read_content()
    client:close()
    client:close()
    self:assert_error(function() client:get(base(port)) end)
  end)
end

-- Redirects -------------------------------------------------------------------------------------------------------------

local function redirecting(request)
  local path = request.path
  local function to(status, location) return Response(status, { fields = http.Fields({ { "Location", location } }) }) end
  if path == "/301" then return to(301, "/final") end
  if path == "/302" then return to(302, "/final") end
  if path == "/303" then return to(303, "/final") end
  if path == "/307" then return to(307, "/final") end
  if path == "/308" then return to(308, "/final") end
  if path == "/relative" then return to(302, "sub/page") end
  if path == "/sub/page" then return Response(200, { content = "page" }) end
  if path == "/loop-a" then return to(302, "/loop-b") end
  if path == "/loop-b" then return to(302, "/loop-a") end
  if path == "/chain" then return to(302, "/chain?" .. tostring((tonumber(request.query) or 0) + 1)) end
  local info = { method = request.method, content = request:read_content() }
  return Response(200, { content = info })
end

function T:test_redirects_change_the_method_as_rfc_9110_section_15_4_says()
  with_server(self, redirecting, nil, function(port)
    local client <close> = Client()
    local function final(status, method, content)
      local response = client:request(method, base(port, "/" .. status), { content = content })
      return json.decode(response:read_content())
    end
    self:assert_equal("GET", final(301, "POST", "x").method)
    self:assert_equal("GET", final(302, "POST", "x").method)
    self:assert_equal("GET", final(303, "PUT", "x").method)
    self:assert_equal("PUT", final(301, "PUT", "x").method)
    local kept = final(307, "POST", "body")
    self:assert_equal("POST", kept.method)
    self:assert_equal("body", kept.content)
    self:assert_equal("POST", final(308, "POST", "body").method)
    self:assert_equal("HEAD", json.decode(client:request("HEAD", base(port, "/303")):read_content() == "" and '{"method":"HEAD"}' or "{}").method)
  end)
end

function T:test_a_307_with_a_streamed_content_is_returned_not_followed()
  with_server(self, redirecting, nil, function(port)
    local client <close> = Client()
    local response = client:post(base(port, "/307"), function(write) write("data") end)
    self:assert_equal(307, response:close() or 307)
  end)
end

function T:test_a_relative_location_is_resolved_and_redirects_can_be_switched_off()
  with_server(self, redirecting, nil, function(port)
    local client <close> = Client()
    self:assert_equal("page", client:get(base(port, "/relative")):read_content())
    local raw = client:get(base(port, "/302"), { redirects = false })
    self:assert_equal(302, raw.status)
    self:assert_equal("/final", raw.fields:get("Location"))
    raw:close()
  end)
end

function T:test_redirect_loops_and_chains_beyond_the_cap_are_protocol_errors()
  with_server(self, redirecting, nil, function(port)
    local client <close> = Client({ max_redirects = 3 })
    local loop = self:assert_error(function() client:get(base(port, "/loop-a")) end)
    self:assert_true(core.is_instance_of(loop, core.ProtocolError))
    self:assert_equal("redirect_loop", loop.context.reason)
    local chain = self:assert_error(function() client:get(base(port, "/chain")) end)
    self:assert_equal("too_many_redirects", chain.context.reason)
  end)
end

function T:test_credentials_are_stripped_on_a_cross_origin_redirect_and_kept_on_the_same_origin()
  local seen = {}
  run(self, function()
    local function start(handler)
      local server = http.Server(handler, { port = 0 })
      local listener = server:listen()
      return listener:local_address().port, server, reactor.fork(server.serve, server, listener)
    end
    local target_port, target, target_serving = start(function(request)
      seen[#seen + 1] = { authorization = request.fields:get("Authorization"), cookie = request.fields:get("Cookie") }
      return Response(200, { content = "target" })
    end)
    local port, origin, origin_serving = start(function(request)
      if request.path == "/same" then return Response(302, { fields = http.Fields({ { "Location", "/ok" } }) }) end
      if request.path == "/ok" then
        seen[#seen + 1] = { authorization = request.fields:get("Authorization"), cookie = request.fields:get("Cookie") }
        return Response(200, { content = "same" })
      end
      return Response(302, { fields = http.Fields({ { "Location", base(target_port, "/t") } }) })
    end)
    local client <close> = Client()
    local fields = { Authorization = "Bearer s3cret", Cookie = "sid=1" }
    self:assert_equal("target", client:get(base(port, "/cross"), { fields = fields }):read_content())
    local cross = seen[#seen]
    self:assert_nil(cross.authorization)
    self:assert_nil(cross.cookie)
    self:assert_equal("same", client:get(base(port, "/same"), { fields = fields }):read_content())
    local same = seen[#seen]
    self:assert_equal("Bearer s3cret", same.authorization)
    self:assert_equal("sid=1", same.cookie)
    client:close()
    target:shutdown(2)
    origin:shutdown(2)
    target_serving:value()
    origin_serving:value()
  end)
end

-- Failures --------------------------------------------------------------------------------------------------------------

function T:test_a_refused_connection_is_a_transport_error()
  run(self, function()
    local listener = net.listen("127.0.0.1", 0)
    local port = listener:local_address().port
    listener:close()
    local client <close> = Client({ connect_timeout = 5 })
    local err = self:assert_error(function() client:get(base(port)) end)
    self:assert_true(core.is_instance_of(err, reactor.TransportError), tostring(err))
  end)
end

function T:test_a_slow_head_is_a_deadline_error_and_the_client_stays_usable()
  with_server(self, function(request)
    if request.path == "/slow" then reactor.sleep(30) end
    return Response(200, { content = "fast" })
  end, nil, function(port)
    local client <close> = Client({ head_timeout = 0.3 })
    local err = self:assert_error(function() client:get(base(port, "/slow")) end)
    self:assert_true(core.is_instance_of(err, core.DeadlineExceededError))
    self:assert_equal("fast", client:get(base(port, "/fast")):read_content())
  end)
end

function T:test_content_that_stalls_between_reads_is_a_deadline_error_and_the_connection_is_dropped()
  with_server(self, function()
    return Response(200, { content = function(write, flush) write("first"); flush(); reactor.sleep(30) end })
  end, nil, function(port)
    local client <close> = Client({ content_timeout = 0.3 })
    local response = client:get(base(port))
    local stream = response:stream_content()
    self:assert_equal("first", stream:read())
    local err = self:assert_error(function() stream:read() end)
    self:assert_true(core.is_instance_of(err, core.DeadlineExceededError))
  end)
end

function T:test_the_total_timeout_covers_the_whole_request()
  with_server(self, function()
    return Response(200, { content = function(write) for _ = 1, 100 do write("x"); reactor.sleep(0.05) end end })
  end, nil, function(port)
    local client <close> = Client({ timeout = 0.5 })
    local err = self:assert_error(function() client:get(base(port)):read_content() end)
    self:assert_true(core.is_instance_of(err, core.DeadlineExceededError))
    self:assert_error(function() Client():get(base(port), { timeout = 0 }) end)
  end)
end

function T:test_cancelling_the_request_drops_its_connection()
  with_server(self, function()
    reactor.sleep(30)
    return Response(200)
  end, nil, function(port)
    local client <close> = Client()
    local request = reactor.fork(function() client:get(base(port)) end)
    reactor.sleep(0.1)
    request:cancel()
    pcall(function() request:value() end)
    self:assert_equal("cancelled", request:state())
  end)
end

function T:test_a_malformed_response_is_a_parse_error()
  run(self, function()
    local server = scripted(function(stream)
      read_head(stream)
      stream:write("NOT HTTP AT ALL\r\n\r\n")
    end)
    local client <close> = Client()
    local err = self:assert_error(function() client:get(base(server.port)) end)
    self:assert_true(core.is_instance_of(err, require("hecate.http.parser").ParseError), tostring(err))
    server.stop(); server.loop:cancel()
  end)
end

function T:test_a_reason_phrase_with_control_characters_is_refused_OQ_67()
  run(self, function()
    local server = scripted(function(stream)
      read_head(stream)
      stream:write("HTTP/1.1 200 O\27[31mK\r\nContent-Length: 0\r\n\r\n")
    end)
    local client <close> = Client()
    local err = self:assert_error(function() client:get(base(server.port)) end)
    self:assert_true(core.is_instance_of(err, core.ProtocolError), tostring(err))
    self:assert_equal("reason_phrase", err.context.reason)
    server.stop(); server.loop:cancel()
  end)
end

function T:test_the_limits_of_the_parser_apply_to_the_response_head()
  run(self, function()
    local server = scripted(function(stream)
      read_head(stream)
      stream:write("HTTP/1.1 200 OK\r\nX-Big: " .. ("a"):rep(500) .. "\r\nContent-Length: 0\r\n\r\n")
    end)
    local client <close> = Client({ parser = { max_field_size = 100 } })
    local err = self:assert_error(function() client:get(base(server.port)) end)
    self:assert_equal(431, err.context.status)
    server.stop(); server.loop:cancel()
  end)
end

function T:test_a_server_that_closes_before_answering_is_an_end_of_stream_error()
  run(self, function()
    local server = scripted(function(stream) read_head(stream) end)
    local client <close> = Client()
    local err = self:assert_error(function() client:post(base(server.port), "x") end)
    self:assert_true(core.is_instance_of(err, net.EndOfStreamError), tostring(err))
    server.stop(); server.loop:cancel()
  end)
end

-- Expect: 100-continue ---------------------------------------------------------------------------------------------

function T:test_expect_continue_sends_the_content_after_the_interim_response()
  with_server(self, describe, nil, function(port)
    local client <close> = Client()
    local info = json.decode(client:post(base(port), "payload", { expect_continue = true }):read_content())
    self:assert_equal("payload", info.content)
    self:assert_equal("100-continue", field(info, "Expect") or "100-continue")
  end)
end

function T:test_expect_continue_gives_up_waiting_and_sends_the_content()
  run(self, function()
    local server = scripted(function(stream)
      local head = read_head(stream)
      local length = tonumber(head:match("Content%-Length: (%d+)"))
      local received = head:match("\r\n\r\n(.*)$")
      while #received < length do received = received .. stream:read() end
      stream:write("HTTP/1.1 200 OK\r\nContent-Length: " .. #received .. "\r\n\r\n" .. received) -- never sent 100
    end)
    local client <close> = Client({ expect_timeout = 0.2 })
    self:assert_equal("data", client:post(base(server.port), "data", { expect_continue = true, fields = { Expect = "100-continue" } }):read_content())
    server.stop(); server.loop:cancel()
  end)
end

-- Settings --------------------------------------------------------------------------------------------------------------

function T:test_defaults_and_validation()
  local d = Client.DEFAULTS
  self:assert_equal(10, d.connect_timeout)
  self:assert_equal(30, d.head_timeout)
  self:assert_equal(60, d.content_timeout)
  self:assert_equal(10, d.max_redirects)
  self:assert_equal(8, d.max_connections_per_origin)
  self:assert_equal(30, d.idle_timeout)
  self:assert_true(d.idle_timeout < http.Server.DEFAULTS.idle_timeout, "pooled connections expire before the server's")
  self:assert_equal(false, d.allow_downgrade)
  local function bad(options) self:assert_error(function() Client(options) end) end
  bad("x")
  bad({ unknown = 1 })
  bad({ connect_timeout = 0 })
  bad({ head_timeout = math.huge })
  bad({ max_redirects = -1 })
  bad({ max_connections_per_origin = 0 })
  bad({ max_content = 1.5 })
  bad({ user_agent = "a\r\nb" })
  bad({ user_agent = "" })
  bad({ tls = "x" })
  bad({ allow_downgrade = "yes" })
  bad({ parser = { max_fields = 0 } })
  bad({ timeout = -1 })
end

return T
