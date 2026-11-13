---@diagnostic disable: missing-fields, param-type-mismatch, need-check-nil, assign-type-mismatch  -- the tests pass invalid arguments on purpose
-- Findings of the security review of the server: pending-head detection for bare CRLF, a finite total content deadline and a
-- bounded drain, Host validation, absolute-form targets and the validation of the response a action returns.
local test = require("harness.test")
local reactor = require("hecate.reactor")
local http = require("hecate.http")
-- Without a logger the server writes to the standard error stream (OQ-79): tests keep it quiet.
local QUIET <const> = require("hecate.log").Logger({ sinks = { require("hecate.log").MemorySink() }, severity = "debug" })
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
  with_server(self, ok_action, { head_timeout = 0.3, idle_timeout = 30 }, function(port)
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
  with_server(self, ok_action, { drain_timeout = 0.3, content_timeout = 30, request_timeout = 30 }, function(port)
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
    local server = http.Server(ok_action, { port = 0, logger = QUIET })
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

-- Findings of the Phase 2 gate review --------------------------------------------------------------------------------

-- H-1: whitespace-heavy heads within the default limits are parsed in linear time, so they do not delay a plain request
-- on another connection (the quadratic trim took about 0.5 s per head on the reactor thread).
function T:test_whitespace_heavy_heads_do_not_delay_a_request_on_another_connection()
  with_server(self, ok_action, nil, function(port)
    local value = "a" .. (" "):rep(8000) .. "b"
    local lines = { "GET /slow HTTP/1.1\r\nHost: t\r\nExpect: 100-continue" .. (" "):rep(8000) .. "\r\n" }
    for i = 1, 6 do lines[#lines + 1] = ("X%d: %s\r\n"):format(i, value) end
    lines[#lines + 1] = "\r\n"
    local head = table.concat(lines)
    local attackers = {}
    for i = 1, 3 do attackers[i] = connect(port) end
    local victim <close> = connect(port)
    local started = reactor.now()
    for i = 1, 3 do attackers[i]:send(head) end
    reactor.sleep(0.01)
    self:assert_equal("ok /fast", victim:request(get("/fast")).content)
    local elapsed = reactor.now() - started
    self:assert_true(elapsed < 0.5, ("the plain request waited %.2f s"):format(elapsed))
    for i = 1, 3 do
      self:assert_equal(200, attackers[i]:read_response().status)
      attackers[i]:close()
    end
  end)
end

-- H-5: several Host lines are a 400 whatever the version (RFC 9112, section 3.2: one Host; RFC 9110, section 5.3: Host is
-- not a list). HTTP/1.0 without a Host is still served.
function T:test_several_host_lines_are_refused_for_every_version()
  local served = 0
  with_server(self, function(request) served = served + 1 return ok_action(request) end, nil, function(port)
    for _, version in ipairs({ "HTTP/1.0", "HTTP/1.1" }) do
      local client <close> = connect(port)
      self:assert_equal(400, client:request("GET / " .. version .. "\r\nHost: a\r\nHost: b\r\n\r\n").status, version)
      local same <close> = connect(port)
      self:assert_equal(400, same:request("GET / " .. version .. "\r\nHost: a\r\nHost: a\r\n\r\n").status, version)
    end
    self:assert_equal(0, served)
    local bare <close> = connect(port)
    self:assert_equal(200, bare:request("GET / HTTP/1.0\r\n\r\n").status)
    local invalid <close> = connect(port)
    self:assert_equal(400, invalid:request("GET / HTTP/1.0\r\nHost: a/b\r\n\r\n").status)
  end)
end

-- H-6: request-target forms (RFC 9112, section 3.2). The asterisk-form is for OPTIONS only (section 3.2.4), and no form
-- carries a fragment (sections 3.2.1 and 3.2.2: origin-form and absolute-form have none; RFC 9110, section 7.1).
local TARGET_VECTORS = {
  { "OPTIONS * HTTP/1.1", 200, "asterisk-form with OPTIONS (section 3.2.4)" },
  { "GET * HTTP/1.1", 400, "asterisk-form with GET" },
  { "POST * HTTP/1.1", 400, "asterisk-form with POST" },
  { "HEAD * HTTP/1.1", 400, "asterisk-form with HEAD" },
  { "OPTIONS * HTTP/1.0", 200, "asterisk-form with OPTIONS in HTTP/1.0" },
  { "OPTIONS /a HTTP/1.1", 200, "origin-form with OPTIONS" },
  { "GET /a#x HTTP/1.1", 400, "origin-form with a fragment" },
  { "GET /a?q=1#x HTTP/1.1", 400, "origin-form with a query and a fragment" },
  { "GET /# HTTP/1.1", 400, "origin-form with an empty fragment" },
  { "OPTIONS *#x HTTP/1.1", 400, "asterisk-form with a fragment" },
  { "GET http://t/a#x HTTP/1.1", 400, "absolute-form with a fragment" },
  { "GET /a?q=%23 HTTP/1.1", 200, "a percent-encoded number sign is data" },
}

function T:test_request_target_forms_follow_rfc_9112_section_3_2()
  local seen = {}
  with_server(self, function(request) seen[#seen + 1] = request.target return ok_action(request) end, nil, function(port)
    for _, vector in ipairs(TARGET_VECTORS) do
      local client <close> = connect(port)
      local response = client:request(vector[1] .. "\r\nHost: t\r\n\r\n")
      self:assert_equal(vector[2], response and response.status, vector[3])
    end
  end)
  for _, target in ipairs(seen) do self:assert_nil(string.find(target, "#", 1, true), target) end
  self:assert_equal(4, #seen)
end

-- H-7: a 205 goes out with `Content-Length: 0` and no content, even when a hand-made response carries some (RFC 9110,
-- section 15.3.6), and the connection stays usable.
function T:test_a_205_response_has_a_zero_length_and_no_content()
  with_server(self, function(request)
    local response = http.Response(205)
    if request.path == "/smuggled" then response.content = "should not be sent" end
    return response
  end, nil, function(port)
    local client <close> = connect(port)
    client:send("GET /plain HTTP/1.1\r\nHost: t\r\n\r\n")
    local raw = ""
    while not string.find(raw, "\r\n\r\n", 1, true) do raw = raw .. client.stream:read(65536) end
    self:assert_not_nil(string.find(raw, "\r\nContent-Length: 0\r\n", 1, true), raw)
    self:assert_nil(string.find(raw, "Transfer-Encoding", 1, true), raw)
    local again <close> = connect(port)
    local response = again:request("GET /smuggled HTTP/1.1\r\nHost: t\r\n\r\n")
    self:assert_equal(205, response.status)
    self:assert_equal("", response.content)
    self:assert_equal("0", response.fields:get("Content-Length"))
    self:assert_equal(205, again:request(get("/next")).status, "the connection stays in step")
  end)
end

return T
