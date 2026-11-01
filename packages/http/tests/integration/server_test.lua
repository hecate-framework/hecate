-- The HTTP/1.1 server over a loopback listener: keep-alive, pipelining, Host, Expect, HEAD, chunked, shutdown.
local test = require("harness.test")
local reactor = require("hecate.reactor")
local net = require("hecate.net")
local http = require("hecate.http")
local T = test.Case("HttpServerTest")

function T:assert_match(pattern, text)
  self:assert_true(string.find(text, pattern) ~= nil, "expected " .. string.format("%q", text) .. " to match " .. pattern)
end

local function echo(request)
  return http.Response(200, { content = request.method .. " " .. request.target .. " " .. (request.content or "") })
end

-- Runs a server with `handler`, calls fn(port, server), then shuts down.
local function with_server(handler, options, fn)
  reactor.run(function()
    local listener = net.listen("127.0.0.1", 0)
    local port = listener:local_address().port
    local server = http.Server(handler, options)
    local serving = reactor.fork(function() server:serve(listener) end)
    local ok, err = pcall(fn, port, server)
    server:shutdown()
    reactor.join(serving)
    if not ok then error(err, 0) end
  end)
end

-- Sends `text`, half-closes, and reads until the server closes.
local function exchange(port, text)
  local stream <close> = net.connect("127.0.0.1", port)
  stream:write(text)
  stream:shutdown()
  local parts = {}
  while true do
    local chunk = stream:read()
    if chunk == nil then break end
    parts[#parts + 1] = chunk
  end
  return table.concat(parts)
end

local function count(text, pattern)
  local n = 0
  for _ in string.gmatch(text, pattern) do n = n + 1 end
  return n
end

function T:test_simple_request()
  with_server(echo, nil, function(port)
    local out = exchange(port, "GET /a HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
    self:assert_match("^HTTP/1.1 200 OK\r\n", out)
    self:assert_match("Content%-Length: 7\r\n", out)
    self:assert_match("Date: ", out)
    self:assert_match("Connection: close\r\n", out)
    self:assert_match("GET /a $", out)
  end)
end

function T:test_keep_alive_and_pipelining_answer_in_order()
  with_server(echo, nil, function(port)
    local out = exchange(port, "GET /1 HTTP/1.1\r\nHost: x\r\n\r\nPOST /2 HTTP/1.1\r\nHost: x\r\nContent-Length: 2\r\n\r\nhiGET /3 HTTP/1.1\r\nHost: x\r\n\r\n")
    self:assert_equal(3, count(out, "HTTP/1.1 200 OK"))
    local a, b, c = string.find(out, "GET /1", 1, true), string.find(out, "POST /2 hi", 1, true), string.find(out, "GET /3", 1, true)
    self:assert_true(a < b and b < c)
  end)
end

function T:test_chunked_request_content()
  with_server(echo, nil, function(port)
    local out = exchange(port, "POST /c HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nabc\r\n2\r\nde\r\n0\r\n\r\n")
    self:assert_match("POST /c abcde$", out)
  end)
end

function T:test_missing_or_duplicate_host_is_400()
  with_server(echo, nil, function(port)
    self:assert_match("^HTTP/1.1 400 ", exchange(port, "GET / HTTP/1.1\r\n\r\n"))
    self:assert_match("^HTTP/1.1 400 ", exchange(port, "GET / HTTP/1.1\r\nHost: a\r\nHost: b\r\n\r\n"))
  end)
end

function T:test_http_1_0_needs_no_host_and_closes()
  with_server(echo, nil, function(port)
    local out = exchange(port, "GET / HTTP/1.0\r\n\r\n")
    self:assert_match("^HTTP/1.1 200 ", out)
  end)
end

function T:test_expect_100_continue()
  with_server(echo, nil, function(port)
    local out = exchange(port, "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 1\r\nExpect: 100-continue\r\n\r\nz")
    self:assert_match("^HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 200 OK", out)
    self:assert_match("^HTTP/1.1 417 ", exchange(port, "GET / HTTP/1.1\r\nHost: x\r\nExpect: nonsense\r\n\r\n"))
  end)
end

function T:test_head_has_no_content()
  with_server(echo, nil, function(port)
    local out = exchange(port, "HEAD /h HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
    self:assert_match("Content%-Length: %d+\r\n", out)
    self:assert_match("\r\n\r\n$", out)
  end)
end

function T:test_function_content_is_chunked()
  local handler = function()
    return http.Response(200, { content = function(write) write("ab"); write("cde") end })
  end
  with_server(handler, nil, function(port)
    local out = exchange(port, "GET / HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
    self:assert_match("Transfer%-Encoding: chunked\r\n", out)
    self:assert_match("\r\n2\r\nab\r\n3\r\ncde\r\n0\r\n\r\n$", out)
  end)
end

function T:test_handler_failure_is_a_generic_500()
  local seen
  local handler = function() error("secret detail 10.0.0.1") end
  with_server(handler, { on_error = function(err) seen = err end }, function(port)
    local out = exchange(port, "GET / HTTP/1.1\r\nHost: x\r\n\r\n")
    self:assert_match("^HTTP/1.1 500 ", out)
    self:assert_nil(string.find(out, "secret", 1, true))
    self:assert_not_nil(seen)
  end)
end

function T:test_content_over_the_limit_is_413()
  with_server(echo, { max_content = 4 }, function(port)
    self:assert_match("^HTTP/1.1 413 ", exchange(port, "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\n\r\nhello"))
    self:assert_match("^HTTP/1.1 413 ", exchange(port, "POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n0\r\n\r\n"))
  end)
end

function T:test_malformed_request_gets_the_parser_status()
  with_server(echo, nil, function(port)
    self:assert_match("^HTTP/1.1 400 ", exchange(port, "GET / HTTP/1.1\r\nHost: x\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\n"))
    self:assert_match("^HTTP/1.1 414 ", exchange(port, "GET /" .. string.rep("a", 9000) .. " HTTP/1.1\r\nHost: x\r\n\r\n"))
  end)
end

function T:test_shutdown_lets_the_running_request_finish_and_closes_idle_connections()
  with_server(function(request)
    reactor.sleep(0.05)
    return http.Response(200, { content = "done" })
  end, nil, function(port, server)
    local busy <close> = net.connect("127.0.0.1", port)
    busy:write("GET / HTTP/1.1\r\nHost: x\r\n\r\n")
    local idle <close> = net.connect("127.0.0.1", port)
    reactor.sleep(0.01)
    server:shutdown()
    local text = busy:read()
    self:assert_match("done", text)
    self:assert_match("Connection: close", text)
  end)
end

function T:test_arguments_are_checked()
  self:assert_error(function() http.Server("no") end)
  self:assert_error(function() http.Server(echo, { nope = 1 }) end)
  self:assert_error(function() http.Server(echo, { max_content = -1 }) end)
end

return T
