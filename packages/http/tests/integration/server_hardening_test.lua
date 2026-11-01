---@diagnostic disable: missing-fields, param-type-mismatch, need-check-nil, assign-type-mismatch  -- the tests pass invalid arguments on purpose
-- Findings of the security review of the server: pending-head detection for bare CRLF, a finite total content deadline and a
-- bounded drain, Host validation, absolute-form targets and the validation of the response a action returns.
local test = require("harness.test")
local reactor = require("hecate.reactor")
local http = require("hecate.http")
local T = test.Case("ServerHardeningTest")

local dir = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):gsub("/[^/]*$", "")
local support = dofile(dir .. "/../fixtures/client.lua")
local connect, get, with_server = support.connect, support.get, support.with_server
local Response = http.Response

local function ok_action(request) return Response(200, { content = "ok " .. request.path }) end
local function healthy(self, port)
  local client <close> = connect(port)
  self:assert_equal("ok /health", client:request(get("/health")).content)
end

function T:test_bare_line_breaks_before_a_head_do_not_escape_the_head_timeout()
  with_server(self, ok_action, { head_timeout = 1, idle_timeout = 30 }, function(port)
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

function T:test_the_total_request_timeout_and_the_drain_have_finite_defaults()
  self:assert_equal(300, http.Server.DEFAULTS.request_timeout)
  self:assert_equal(5, http.Server.DEFAULTS.drain_timeout)
  self:assert_equal(300, http.Client.DEFAULTS.request_timeout)
end

function T:test_unread_content_trickled_after_the_response_is_cut_at_the_drain_timeout()
  with_server(self, ok_action, { drain_timeout = 1, content_timeout = 30, request_timeout = 30 }, function(port)
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
  with_server(self, function(request) seen[#seen + 1] = request.path return ok_action(request) end, nil, function(port)
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
    return ok_action(request)
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

function T:test_the_server_logs_where_it_listens_and_hints_at_loopback()
  local log = require("hecate.log")
  local sink = log.MemorySink()
  local logger = log.Logger({ sinks = { sink }, severity = "debug" })
  with_server(self, ok_action, { logger = logger }, function(port)
    healthy(self, port)
  end)
  local record
  for _, r in ipairs(sink:records()) do
    if r.message:find("listening on", 1, true) then record = r end
  end
  self:assert_not_nil(record, "a record at serve start")
  self:assert_equal("http.Server: listening on 127.0.0.1:" .. tostring(record.message:match(":(%d+)")) .. " (loopback only)", record.message)
  self:assert_not_nil(record.fields.hint:find("0.0.0.0", 1, true))
  self:assert_equal("informational", record.severity.name or tostring(record.severity))
end

function T:test_option_errors_name_the_value_and_a_way_out_and_suggest_the_nearest_name()
  local function message(options) return tostring(self:assert_error(function() http.Server(ok_action, options) end)) end
  local host = message({ host = "localhost" })
  self:assert_not_nil(host:find('invalid host "localhost": expected a numeric address. Use "127.0.0.1" (this machine only), "0.0.0.0" (every IPv4 interface) or "::" (every IPv6 interface)', 1, true), host)
  self:assert_not_nil(message({ port = 70000 }):find("invalid port 70000: expected an integer from 0 to 65535", 1, true))
  self:assert_not_nil(message({ head_timeout = "slow" }):find('invalid head_timeout "slow"', 1, true))
  self:assert_not_nil(message({ max_content = ("x"):rep(100) }):find('"' .. ("x"):rep(40) .. '..."', 1, true), "a long value is cut")
  self:assert_nil(message({ host = "a\nb\rc" }):find("[\r\n]"), "control characters are not printed")
  self:assert_not_nil(message({ max_contents = 5 }):find("did you mean max_content?", 1, true))
  self:assert_not_nil(message({ head_timout = 5 }):find("did you mean head_timeout?", 1, true))
  self:assert_nil(message({ zzzzzzzz = 5 }):find("did you mean", 1, true), "nothing close: no suggestion")
  local client = tostring(self:assert_error(function() http.Client({ max_redirect = 3 }) end))
  self:assert_not_nil(client:find("did you mean max_redirects?", 1, true), client)
  self:assert_not_nil(tostring(self:assert_error(function() http.Client({ head_timeout = -1 }) end)):find("invalid head_timeout -1", 1, true))
  local request = tostring(self:assert_error(function() http.Client():get("http://127.0.0.1/", { head_timout = 1 }) end))
  self:assert_not_nil(request:find("did you mean head_timeout?", 1, true), request)
end

function T:test_a_few_messages_say_what_to_do_next()
  self:assert_not_nil(tostring(self:assert_error(function() Response(204, { content = "x" }) end)):find("return a Response without content", 1, true))
  self:assert_not_nil(tostring(self:assert_error(function() http.Request("x") end)):find("http.Request({", 1, true))
  local seen
  reactor.run(function()
    local server = http.Server(ok_action, { port = 0 })
    local listener = server:listen()
    local serving = reactor.fork(server.serve, server, listener)
    reactor.sleep(0)
    seen = tostring(select(2, pcall(server.serve, server, listener)))
    server:shutdown(1)
    serving:value()
  end)
  self:assert_not_nil(seen:find("call shutdown first", 1, true), seen)
end

function T:test_http_available_reports_one_line_and_the_build_command()
  local available, reason = http.available()
  self:assert_true(available)
  self:assert_nil(reason)
end

return T
