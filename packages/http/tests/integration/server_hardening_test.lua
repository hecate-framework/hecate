---@diagnostic disable: missing-fields, param-type-mismatch, need-check-nil, assign-type-mismatch  -- the tests pass invalid arguments on purpose
-- Findings of the security review of the server: pending-head detection for bare CRLF, a finite total content deadline and a
-- bounded drain, Host validation, absolute-form targets and the validation of the response a handler returns.
local test = require("harness.test")
local reactor = require("hecate.reactor")
local http = require("hecate.http")
local T = test.Case("ServerHardeningTest")

local dir = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):gsub("/[^/]*$", "")
local support = dofile(dir .. "/../fixtures/client.lua")
local connect, get, with_server = support.connect, support.get, support.with_server
local Response = http.Response

local function ok_handler(request) return Response(200, { content = "ok " .. request.path }) end
local function healthy(self, port)
  local client <close> = connect(port)
  self:assert_equal("ok /health", client:request(get("/health")).content)
end

function T:test_bare_line_breaks_before_a_head_do_not_escape_the_head_timeout()
  with_server(self, ok_handler, { head_timeout = 1, idle_timeout = 30 }, function(port)
    local client <close> = connect(port)
    local dripping = true
    local dripper = reactor.fork(function()
      while dripping do
        if not pcall(client.send, client, "\r\n") then return end
        reactor.sleep(0.05)
      end
    end)
    local response = client:read_response() -- the 408 (or the close) arrives although bytes keep coming
    dripping = false
    dripper:cancel()
    self:assert_true(response == nil or response.status == 408)
    healthy(self, port)
  end)
end

function T:test_the_total_content_deadline_and_the_drain_have_finite_defaults()
  self:assert_equal(300, http.Server.DEFAULTS.content_deadline)
  self:assert_equal(5, http.Server.DEFAULTS.drain_timeout)
  self:assert_equal(300, http.Client.DEFAULTS.timeout)
end

function T:test_unread_content_trickled_after_the_response_is_cut_at_the_drain_timeout()
  with_server(self, ok_handler, { drain_timeout = 1, content_timeout = 30, content_deadline = 30 }, function(port)
    local client <close> = connect(port)
    client:send("POST /x HTTP/1.1\r\nHost: t\r\nContent-Length: 1000000\r\n\r\n")
    local dripping = true
    local dripper = reactor.fork(function()
      while dripping do
        if not pcall(client.send, client, "a") then return end
        reactor.sleep(0.05)
      end
    end)
    self:assert_equal(200, client:read_response().status)
    self:assert_nil(client:read_response(), "the connection is closed, not held by the trickle")
    dripping = false
    dripper:cancel()
    healthy(self, port)
  end)
end

function T:test_a_host_field_must_be_one_host_with_an_optional_port()
  local seen = {}
  with_server(self, function(request) seen[#seen + 1] = request.path return ok_handler(request) end, nil, function(port)
    for _, host in ipairs({ "a, b", "a/b", "user@h", "h:abc", "h:123456", "h h", "h?x", "[::1", "", "h:80:80", "h\\" }) do
      local client <close> = connect(port)
      local response = client:request("GET / HTTP/1.1\r\nHost: " .. host .. "\r\n\r\n")
      self:assert_equal(400, response.status, "Host: " .. host)
    end
    for _, host in ipairs({ "h", "example.org:8080", "[::1]:80", "[2001:db8::1]", "a-b.c_d~e%41", "H.EXAMPLE:1" }) do
      local client <close> = connect(port)
      self:assert_equal(200, client:request("GET / HTTP/1.1\r\nHost: " .. host .. "\r\n\r\n").status, "Host: " .. host)
    end
  end)
end

function T:test_an_absolute_form_target_is_accepted_when_it_names_the_host_and_refused_otherwise()
  local paths = {}
  with_server(self, function(request)
    paths[#paths + 1] = { request.path, request.query }
    return ok_handler(request)
  end, nil, function(port)
    local client <close> = connect(port)
    self:assert_equal(200, client:request("GET http://Example.org:8080/p/q?x=1 HTTP/1.1\r\nHost: example.org:8080\r\n\r\n").status)
    self:assert_equal("/p/q", paths[1][1])
    self:assert_equal("x=1", paths[1][2])
    self:assert_equal(200, client:request("GET http://example.org HTTP/1.1\r\nHost: example.org\r\n\r\n").status)
    self:assert_equal("/", paths[2][1])
    local mismatch <close> = connect(port)
    self:assert_equal(400, mismatch:request("GET http://evil.example/p HTTP/1.1\r\nHost: example.org\r\n\r\n").status)
    local userinfo <close> = connect(port)
    self:assert_equal(400, userinfo:request("GET http://user@example.org/p HTTP/1.1\r\nHost: example.org\r\n\r\n").status)
    healthy(self, port)
  end)
end

function T:test_a_response_the_server_cannot_send_is_a_500_that_is_reported()
  local reported = {}
  with_server(self, function(request)
    local response = Response(200, { content = "x" })
    if request.path == "/status" then response.status = 99 end
    if request.path == "/big" then response.status = 600 end
    if request.path == "/fields" then response.fields = { ["X"] = "1" } end
    if request.path == "/content" then response.content = 42 end
    if request.path == "/reason" then response.reason = 42 end
    return response
  end, { on_error = function(err) reported[#reported + 1] = err end }, function(port)
    for _, path in ipairs({ "/status", "/big", "/fields", "/content", "/reason" }) do
      local client <close> = connect(port)
      local response = client:request(get(path))
      self:assert_equal(500, response.status, path)
      self:assert_equal("application/problem+json", response.fields:get("Content-Type"))
    end
    self:assert_equal(5, #reported)
  end)
end

return T
