---@diagnostic disable: missing-fields, param-type-mismatch, need-check-nil  -- the tests pass invalid arguments on purpose
-- Every limit of the server: it is enforced, and the server stays healthy afterwards (the next request on a new
-- connection is served, and no libuv handle is left open: `with_server` checks). Assertions are order-based; the timeouts
-- are small but never the thing a test measures.
local test = require("harness.test")
local reactor = require("hecate.reactor")
local http = require("hecate.http")
local T = test.Case("ServerLimitsTest")

local dir = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):gsub("/[^/]*$", "")
local support = dofile(dir .. "/../fixtures/client.lua")
local connect, get, with_server = support.connect, support.get, support.with_server
local Response = http.Response

local function ok_action(request) return Response(200, { content = "ok " .. request.path }) end
local function echo_action(request) return Response(200, { content = request:read_content() }) end

--- The server still answers a new connection.
local function healthy(self, port)
  local client <close> = connect(port)
  self:assert_equal("ok /health", client:request(get("/health")).content)
end

-- Limits of the parser ------------------------------------------------------------------------------------------------

local PARSER_CASES = {
  { name = "target", limits = { max_target_size = 64 }, status = 414, text = get("/" .. ("a"):rep(200)) },
  { name = "field value", limits = { max_field_size = 64 }, status = 431, text = get("/", "X-Big: " .. ("a"):rep(200) .. "\r\n") },
  { name = "field name", limits = { max_field_size = 64 }, status = 431, text = get("/", ("X"):rep(200) .. ": 1\r\n") },
  { name = "field count", limits = { max_fields = 5 }, status = 431, text = get("/", ("X-A: 1\r\n"):rep(10)) },
  { name = "head size", limits = { max_head_size = 256 }, status = 431, text = get("/", ("X-A: " .. ("b"):rep(40) .. "\r\n"):rep(10)) },
}

for _, case in ipairs(PARSER_CASES) do
  T["test_the_parser_limit_on_" .. case.name:gsub(" ", "_") .. "_is_enforced_and_the_server_stays_healthy"] = function(self)
    with_server(self, ok_action, { parser = case.limits }, function(port)
      local client <close> = connect(port)
      local response = client:request(case.text)
      self:assert_equal(case.status, response.status)
      self:assert_equal("application/problem+json", response.fields:get("Content-Type"))
      self:assert_equal("close", response.fields:get("Connection"))
      healthy(self, port)
    end)
  end
end

-- Content size ----------------------------------------------------------------------------------------------------------

function T:test_content_size_with_a_length_is_refused_before_the_action_and_the_server_stays_healthy()
  local called = 0
  with_server(self, function(request) called = called + 1; return ok_action(request) end, { max_content = 8 }, function(port)
    local client <close> = connect(port)
    self:assert_equal(413, client:request("POST /e HTTP/1.1\r\nHost: t\r\nContent-Length: 9\r\n\r\n").status)
    healthy(self, port)
  end)
  self:assert_equal(1, called, "only the health check reached the action")
end

function T:test_chunked_content_size_is_enforced_and_the_server_stays_healthy()
  with_server(self, function(request)
    if request.path == "/health" then return ok_action(request) end
    return echo_action(request)
  end, { max_content = 8 }, function(port)
    local client <close> = connect(port)
    self:assert_equal(413, client:request("POST /e HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nabcde\r\n5\r\nfghij\r\n0\r\n\r\n").status)
    healthy(self, port)
  end)
end

-- Deadlines ------------------------------------------------------------------------------------------------------------

function T:test_a_head_dripped_one_byte_at_a_time_is_cut_at_the_head_timeout()
  with_server(self, ok_action, { head_timeout = 0.3, idle_timeout = 30 }, function(port)
    local client <close> = connect(port)
    client:send("GET / HTTP/1.1\r\nHost: t\r\nX-Slow: ")
    local dripping = true
    local dripper = reactor.fork(function()
      while dripping do
        if not pcall(client.send, client, "a") then return end
        reactor.sleep(0.05)
      end
    end)
    local response = client:read_response() -- the 408 arrives although bytes keep coming
    dripping = false
    dripper:cancel()
    self:assert_equal(408, response.status)
    healthy(self, port)
  end)
end

function T:test_a_head_arriving_in_pieces_after_a_pipelined_request_is_held_to_the_head_timeout()
  with_server(self, ok_action, { head_timeout = 0.3, idle_timeout = 30 }, function(port)
    local client <close> = connect(port)
    client:send(get("/a") .. "GET /b HTTP/1.1\r\nHo") -- the second head never completes
    self:assert_equal("ok /a", client:read_response().content)
    self:assert_equal(408, client:read_response().status) -- at the head timeout, not the idle timeout (30 s > the test's 25 s)
    healthy(self, port)
  end)
end

function T:test_a_silent_connection_is_closed_at_the_idle_timeout()
  with_server(self, ok_action, { idle_timeout = 0.3 }, function(port)
    local client <close> = connect(port)
    self:assert_equal(200, client:request(get("/a")).status)
    self:assert_nil(client:read_response(), "closed without an answer")
    healthy(self, port)
  end)
end

function T:test_content_stalling_between_reads_is_cut_at_the_content_timeout()
  with_server(self, function(request)
    if request.path == "/health" then return ok_action(request) end
    return echo_action(request)
  end, { content_timeout = 0.3 }, function(port)
    local client <close> = connect(port)
    client:send("POST /e HTTP/1.1\r\nHost: t\r\nContent-Length: 100\r\n\r\nabc")
    self:assert_equal(408, client:read_response().status)
    healthy(self, port)
  end)
end

function T:test_content_dripped_within_the_between_reads_timeout_is_cut_by_the_total_request_timeout()
  with_server(self, function(request)
    if request.path == "/health" then return ok_action(request) end
    return echo_action(request)
  end, { content_timeout = 30, request_timeout = 0.3 }, function(port)
    local client <close> = connect(port)
    client:send("POST /e HTTP/1.1\r\nHost: t\r\nContent-Length: 100000\r\n\r\n")
    local dripping = true
    local dripper = reactor.fork(function()
      while dripping do
        if not pcall(client.send, client, "a") then return end
        reactor.sleep(0.05)
      end
    end)
    local response = client:read_response()
    dripping = false
    dripper:cancel()
    self:assert_equal(408, response.status)
    healthy(self, port)
  end)
end

function T:test_a_reader_that_never_reads_a_large_response_hits_the_write_timeout_and_the_action_is_cancelled()
  local outcome = {}
  with_server(self, function(request)
    if request.path == "/health" then return ok_action(request) end
    return Response(200, { content = function(write)
      local chunk = ("x"):rep(1 << 20)
      local ok, err = pcall(function()
        for _ = 1, 4000 do write(chunk) end -- far more than the socket buffers hold
      end)
      outcome.failed, outcome.error = not ok, err
      if not ok then error(err, 0) end
    end })
  end, { write_timeout = 0.3 }, function(port)
    local client <close> = connect(port)
    client:send(get("/big")) -- and never read
    while outcome.failed == nil do reactor.sleep(0.05) end
    self:assert_true(outcome.failed, "the writer was stopped")
    self:assert_true(require("hecate.core").is_instance_of(outcome.error, require("hecate.core").DeadlineExceededError))
    healthy(self, port)
  end)
end

-- Connections and pipelining -------------------------------------------------------------------------------------

function T:test_max_connections_is_enforced_when_set_and_the_server_stays_healthy()
  with_server(self, ok_action, { max_connections = 2 }, function(port)
    local first <close> = connect(port)
    local second <close> = connect(port)
    self:assert_equal(200, first:request(get("/a")).status)
    self:assert_equal(200, second:request(get("/b")).status)
    local third <close> = connect(port) -- accepted by the kernel, not served
    third:send(get("/c"))
    local served = false
    local waiting = reactor.fork(function() served = third:read_response() ~= nil end)
    reactor.sleep(0.2)
    self:assert_false(served, "no third connection while two are open")
    first:close()
    waiting:value()
    self:assert_true(served)
    second:close()
    healthy(self, port)
  end)
end

function T:test_a_long_pipelined_burst_is_answered_in_order_one_request_at_a_time()
  local running, most, count = 0, 0, 0
  with_server(self, function(request)
    running = running + 1
    most = math.max(most, running)
    count = count + 1
    reactor.sleep(0)
    running = running - 1
    return Response(200, { content = request.path })
  end, nil, function(port)
    local client <close> = connect(port)
    local total = 2000 -- about 90 KB: many reads of 16 KiB
    local parts = {}
    for i = 1, total do parts[i] = get("/" .. i) end
    local sender = reactor.fork(function() client:send(table.concat(parts)) end)
    for i = 1, total do self:assert_equal("/" .. i, client:read_response().content) end
    sender:value()
    self:assert_equal(1, most, "one request at a time on a connection: the server reads the next burst only when it has answered the last")
  end)
end

return T
