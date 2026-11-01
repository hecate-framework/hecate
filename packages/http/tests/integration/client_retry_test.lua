---@diagnostic disable: missing-fields, param-type-mismatch, need-check-nil, assign-type-mismatch  -- the tests pass invalid arguments on purpose
-- The retry rule of the client pool: a request is repeated on a new connection only when ALL hold: the connection was
-- reused, it failed before any byte of the response arrived, the method is idempotent, the content can be sent again, the
-- failure is a network one, and it is the first attempt. Scripted servers count the connections they accept.
local test = require("harness.test")
local core = require("hecate.core")
local reactor = require("hecate.reactor")
local net = require("hecate.net")
local http = require("hecate.http")
local T = test.Case("ClientRetryTest")

local dir = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):gsub("/[^/]*$", "")
local support = dofile(dir .. "/../fixtures/client.lua")
local run, scripted, read_head, ok = support.run, support.scripted, support.read_head, support.ok
local Client = http.Client

local function url(server) return "http://127.0.0.1:" .. server.port .. "/" end

--- A server whose first connection answers the first request and then, for the second request, runs `second(stream)`;
--- every later connection runs `later(stream)` (default: answers every request).
local function dying(second, later)
  return scripted(function(stream, index)
    if index == 1 then
      read_head(stream)
      stream:write(ok("one"))
      read_head(stream)
      second(stream)
      return
    end
    if later then return later(stream) end
    while read_head(stream) do stream:write(ok("again")) end
  end)
end

local function silent_close() end

for _, method in ipairs({ "GET", "HEAD", "PUT", "DELETE", "OPTIONS" }) do
  T["test_a_" .. method:lower() .. "_on_a_reused_connection_that_died_is_retried"] = function(self)
    run(self, function()
      local server = dying(silent_close)
      local client <close> = Client()
      client:get(url(server)):read_content()
      local response = client:request(method, url(server), { content = (method == "PUT") and "data" or nil })
      self:assert_equal(200, response.status)
      response:close()
      self:assert_equal(2, server.accepted)
      server.stop()
    end)
  end
end

function T:test_a_post_and_a_patch_are_never_retried()
  for _, method in ipairs({ "POST", "PATCH" }) do
    run(self, function()
      local server = dying(silent_close)
      local client <close> = Client()
      client:get(url(server)):read_content()
      local err = self:assert_error(function() client:request(method, url(server), { content = "data" }) end)
      self:assert_true(core.is_instance_of(err, core.NetworkError), tostring(err))
      self:assert_equal(1, server.accepted, method)
      server.stop()
    end)
  end
end

function T:test_a_get_whose_reused_connection_died_inside_the_response_head_is_not_retried()
  run(self, function()
    local server = dying(function(stream) stream:write("HTTP/1.1 200 OK\r\nContent-Le") end)
    local client <close> = Client()
    client:get(url(server)):read_content()
    local err = self:assert_error(function() client:get(url(server)) end)
    self:assert_true(core.is_instance_of(err, core.NetworkError) or core.is_instance_of(err, core.ProtocolError), tostring(err))
    self:assert_equal(1, server.accepted, "part of the head arrived: the request may have been processed")
    server.stop()
  end)
end

function T:test_a_get_on_a_fresh_connection_closed_before_any_answer_is_not_retried()
  run(self, function()
    local server = scripted(function(stream) read_head(stream) end)
    local client <close> = Client()
    local err = self:assert_error(function() client:get(url(server)) end)
    self:assert_true(core.is_instance_of(err, net.EndOfStreamError), tostring(err))
    self:assert_equal(1, server.accepted, "a fresh connection is not a stale one")
    server.stop()
  end)
end

function T:test_a_put_with_streamed_content_is_not_retried()
  run(self, function()
    local server = dying(silent_close)
    local client <close> = Client()
    client:get(url(server)):read_content()
    local calls = 0
    local err = self:assert_error(function()
      client:put(url(server), function(write) calls = calls + 1; write("streamed") end)
    end)
    self:assert_true(core.is_instance_of(err, core.NetworkError), tostring(err))
    self:assert_equal(1, server.accepted)
    self:assert_true(calls <= 1, "the content function is called at most once")
    server.stop()
  end)
end

function T:test_the_retry_happens_at_most_once()
  run(self, function()
    local server = dying(silent_close, function(stream) read_head(stream) end) -- the retry's connection dies too
    local client <close> = Client()
    client:get(url(server)):read_content()
    local err = self:assert_error(function() client:get(url(server)) end)
    self:assert_true(core.is_instance_of(err, net.EndOfStreamError), tostring(err))
    self:assert_equal(2, server.accepted, "one retry, no more")
    server.stop()
  end)
end

function T:test_a_response_that_does_not_parse_is_not_retried()
  run(self, function()
    local server = dying(function(stream) stream:write("NOT HTTP AT ALL\r\n\r\n") end)
    local client <close> = Client()
    client:get(url(server)):read_content()
    local err = self:assert_error(function() client:get(url(server)) end)
    self:assert_true(core.is_instance_of(err, http.ParseError), tostring(err))
    self:assert_equal(1, server.accepted)
    server.stop()
  end)
end

function T:test_a_deadline_is_not_retried()
  run(self, function()
    local server = dying(function() reactor.sleep(30) end)
    local client <close> = Client({ head_timeout = 0.3 })
    client:get(url(server)):read_content()
    local err = self:assert_error(function() client:get(url(server)) end)
    self:assert_true(core.is_instance_of(err, core.DeadlineExceededError), tostring(err))
    self:assert_equal(1, server.accepted)
    server.stop()
  end)
end

function T:test_the_retry_does_not_reset_the_request_timeout()
  run(self, function()
    local server = dying(function() reactor.sleep(0.5) end, function(stream) read_head(stream); reactor.sleep(30) end)
    local client <close> = Client()
    client:get(url(server)):read_content()
    local started = reactor.now()
    local err = self:assert_error(function() client:get(url(server), { request_timeout = 1.5 }) end)
    local elapsed = reactor.now() - started
    self:assert_true(core.is_instance_of(err, core.DeadlineExceededError), tostring(err))
    self:assert_true(elapsed < 6, "the deadline is for the whole request, retry included: " .. elapsed)
    self:assert_equal(2, server.accepted)
    server.stop()
  end)
end

return T
