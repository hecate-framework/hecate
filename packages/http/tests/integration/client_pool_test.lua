---@diagnostic disable: missing-fields, param-type-mismatch, need-check-nil, assign-type-mismatch  -- the tests pass invalid arguments on purpose
-- Pool bookkeeping of the client: when a connection is not kept, leases that never leak, isolation of origins, the order of
-- waiters, and the boundary of `max_content` on both sides.
local test = require("harness.test")
local core = require("hecate.core")
local reactor = require("hecate.reactor")
local net = require("hecate.net")
local http = require("hecate.http")
local T = test.Case("ClientPoolTest")

local dir = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):gsub("/[^/]*$", "")
local support = dofile(dir .. "/../fixtures/client.lua")
local run, scripted, read_head, ok, connect, get, with_server = support.run, support.scripted, support.read_head, support.ok,
  support.connect, support.get, support.with_server
local Client, Response = http.Client, http.Response

local function url(server, path) return "http://127.0.0.1:" .. server.port .. (path or "/") end

--- A server that answers every request on a connection with `response(index)` and counts its connections.
local function answering(response)
  return scripted(function(stream, index)
    while read_head(stream) do stream:write(response(index)) end
  end)
end

local NOT_KEPT = {
  ["Connection: close"] = function() return "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 1\r\n\r\nx" end,
  ["HTTP/1.0 without keep-alive"] = function() return "HTTP/1.0 200 OK\r\nContent-Length: 1\r\n\r\nx" end,
  ["a body that ends with the connection"] = function() return "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\nx" end,
}

for label, response in pairs(NOT_KEPT) do
  T["test_a_connection_is_not_pooled_after_" .. label:gsub("[^%w]+", "_")] = function(self)
    run(self, function()
      local server = scripted(function(stream)
        read_head(stream)
        stream:write(response())
      end)
      local client <close> = Client()
      self:assert_equal("x", client:get(url(server)):read_content())
      self:assert_equal(0, client:pool_stats().idle, label)
      client:get(url(server)):close()
      self:assert_equal(2, server.accepted, "a new connection for the next request")
      server.stop()
    end)
  end
end

function T:test_a_request_with_connection_close_is_not_pooled_either()
  run(self, function()
    local server = answering(function() return ok("x") end)
    local client <close> = Client()
    client:get(url(server), { fields = { Connection = "close" } }):read_content()
    self:assert_equal(0, client:pool_stats().idle)
    client:get(url(server)):read_content()
    self:assert_equal(2, server.accepted)
    server.stop()
  end)
end

function T:test_a_response_closed_half_read_frees_its_lease_and_the_next_request_succeeds()
  run(self, function()
    local server = answering(function() return ok(("x"):rep(100000)) end)
    local client <close> = Client({ max_connections_per_origin = 1 })
    local response = client:get(url(server))
    response:stream_content():read() -- half read
    response:close()
    self:assert_equal(100000, #client:get(url(server)):read_content(), "the lease was free: not stuck")
    server.stop()
  end)
end

function T:test_a_lease_is_released_when_the_connect_fails()
  run(self, function()
    local listener = net.listen("127.0.0.1", 0)
    local port = listener:local_address().port
    listener:close()
    local client <close> = Client({ max_connections_per_origin = 1, connect_timeout = 5 })
    for _ = 1, 3 do
      local err = self:assert_error(function() client:get("http://127.0.0.1:" .. port .. "/") end)
      self:assert_true(core.is_instance_of(err, core.NetworkError), tostring(err)) -- never stuck behind a leaked lease
    end
  end)
end

function T:test_a_request_that_waits_for_a_lease_ends_at_its_deadline_and_leaks_nothing()
  run(self, function()
    local server = answering(function() return ok("x") end)
    local client <close> = Client({ max_connections_per_origin = 1 })
    local held = client:get(url(server)) -- keeps the only lease
    local err = self:assert_error(function() client:get(url(server), { request_timeout = 0.3 }) end)
    self:assert_true(core.is_instance_of(err, core.DeadlineExceededError), tostring(err))
    held:read_content()
    self:assert_equal("x", client:get(url(server)):read_content(), "the lease came back")
    server.stop()
  end)
end

function T:test_origins_are_isolated()
  run(self, function()
    local first = answering(function() return ok("first") end)
    local second = answering(function() return ok("second") end)
    local client <close> = Client({ max_connections_per_origin = 1 })
    local held = client:get(url(first)) -- the only lease of the first origin
    self:assert_equal("second", client:get(url(second)):read_content(), "another origin is not blocked")
    held:close()
    first.stop(); second.stop()
  end)
end

function T:test_waiters_are_served_in_order_and_a_cancelled_waiter_leaks_nothing()
  run(self, function()
    local server = answering(function() return ok("x") end)
    local client <close> = Client({ max_connections_per_origin = 1 })
    local held = client:get(url(server))
    local order = {}
    local started = reactor.Semaphore(0)
    local function waiter(label)
      return reactor.fork(function()
        started:release()
        client:get(url(server), { fields = { ["X-Label"] = label } }):read_content()
        order[#order + 1] = label
      end)
    end
    local one = waiter("one")
    started:acquire()
    reactor.sleep(0) -- `one` is queued for the lease
    local cancelled = waiter("cancelled")
    started:acquire()
    reactor.sleep(0)
    local three = waiter("three")
    started:acquire()
    reactor.sleep(0)
    cancelled:cancel()
    pcall(function() cancelled:value() end)
    held:read_content()
    one:value(); three:value()
    self:assert_equal("one,three", table.concat(order, ","), "first come, first served; the cancelled one is gone")
    self:assert_equal("x", client:get(url(server)):read_content(), "no lease leaked")
    server.stop()
  end)
end

function T:test_the_client_max_content_boundary()
  run(self, function()
    local server = scripted(function(stream)
      while read_head(stream) do
        stream:write(ok(("x"):rep(100)))
      end
    end)
    local exact <close> = Client({ max_content = 100 })
    self:assert_equal(100, #exact:get(url(server)):read_content(), "exactly the limit is accepted")
    local under <close> = Client({ max_content = 99 })
    local err = self:assert_error(function() under:get(url(server)):read_content() end)
    self:assert_true(core.is_instance_of(err, http.ContentError))
    self:assert_equal("too_large", err.context.reason)
    self:assert_nil(err.context.status)
    local held = under:get(url(server))
    local stream_err = self:assert_error(function() held:stream_content():read_all() end)
    held:close() -- a stream that failed leaves the response to its owner: closing it drops the connection
    self:assert_equal("too_large", stream_err.context.reason)
    self:assert_nil(stream_err.context.status)
    self:assert_error(function() Client({ max_content = -1 }) end)
    self:assert_error(function() Client({ max_content = 1.5 }) end)
    server.stop()
  end)
end

function T:test_the_server_max_content_boundary_and_a_single_oversized_chunk()
  with_server(self, function(request) return Response(200, { content = tostring(#request:read_content()) }) end, { max_content = 10 }, function(port)
    local function post(text)
      local client <close> = connect(port)
      return client:request(text)
    end
    local function with_length(n) return "POST / HTTP/1.1\r\nHost: t\r\nContent-Length: " .. n .. "\r\n\r\n" .. ("a"):rep(n) end
    self:assert_equal("10", post(with_length(10)).content, "exactly the limit is accepted")
    self:assert_equal(413, post(with_length(11)).status)
    local function chunked(n) return ("POST / HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\n\r\n%x\r\n%s\r\n0\r\n\r\n"):format(n, ("a"):rep(n)) end
    self:assert_equal("10", post(chunked(10)).content)
    self:assert_equal(413, post(chunked(11)).status, "a single chunk over the limit")
    self:assert_equal(413, post(chunked(100000)).status)
    self:assert_equal(200, post(with_length(0)).status)
  end)
  self:assert_error(function() http.Server(function() return Response(200) end, { max_content = -1 }) end)
  -- max_content = 0 is "no content at all": a body of one byte is refused.
  with_server(self, function(request) return Response(200, { content = tostring(#request:read_content()) }) end, { max_content = 0 }, function(port)
    local client <close> = connect(port)
    self:assert_equal(413, client:request("POST / HTTP/1.1\r\nHost: t\r\nContent-Length: 1\r\n\r\na").status)
  end)
end

function T:test_unknown_expectations_are_417_and_the_server_port_is_validated()
  with_server(self, function() return Response(200) end, nil, function(port)
    for _, value in ipairs({ "magic", "100-continue, magic", "200-ok", "100-continue;x=1" }) do
      local client <close> = connect(port)
      self:assert_equal(417, client:request(get("/", "Expect: " .. value .. "\r\n")).status, value)
    end
  end)
  local function build(port) return function() http.Server(function() return Response(200) end, { port = port }) end end
  for _, good in ipairs({ 0, 1, 80, 65535 }) do build(good)() end
  for _, bad in ipairs({ -1, 1.5, "80", 65536, 0x7fffffff, true }) do self:assert_error(build(bad)) end
end

return T
