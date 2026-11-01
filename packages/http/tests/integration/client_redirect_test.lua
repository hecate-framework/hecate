---@diagnostic disable: missing-fields, param-type-mismatch, need-check-nil, assign-type-mismatch  -- the tests pass invalid arguments on purpose
-- Redirects of the client: credentials, origins, methods, bad locations and caps.
local test = require("harness.test")
local core = require("hecate.core")
local reactor = require("hecate.reactor")
local http = require("hecate.http")
local T = test.Case("ClientRedirectTest")

local dir = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):gsub("/[^/]*$", "")
local support = dofile(dir .. "/../fixtures/client.lua")
local run, scripted, read_head = support.run, support.scripted, support.read_head
local Response, Client = http.Response, http.Client

local function base(port, path) return "http://127.0.0.1:" .. port .. (path or "/") end
local function redirect(status, location) return Response(status, { fields = http.Fields({ { "Location", location } }) }) end

--- Starts a server inside the running reactor; returns its port and a function that stops it.
local function start(action)
  local server = http.Server(action, { port = 0 })
  local listener = server:listen()
  local serving = reactor.fork(server.serve, server, listener)
  return listener:local_address().port, function()
    server:shutdown(2)
    serving:value()
  end
end

--- What a request carried: method, content and the lowercase names of its fields.
local function record(into)
  return function(request)
    local names = {}
    for name in request.fields:lines() do names[#names + 1] = string.lower(name) end
    into[#into + 1] = { method = request.method, path = request.path, names = " " .. table.concat(names, " ") .. " ", content = request:read_content() }
    return Response(200, { content = "recorded" })
  end
end

local function has(entry, name) return entry.names:find(" " .. name .. " ", 1, true) ~= nil end

local CREDENTIALS = { Authorization = "Bearer s3cret", Cookie = "sid=1", ["Proxy-Authorization"] = "Basic x" }

function T:test_proxy_authorization_and_every_credential_is_stripped_on_a_cross_origin_redirect()
  run(self, function()
    local seen = {}
    local target, stop_target = start(record(seen))
    local origin, stop_origin = start(function() return redirect(302, base(target, "/t")) end)
    local client <close> = Client()
    client:get(base(origin, "/"), { fields = CREDENTIALS }):read_content()
    self:assert_equal(1, #seen)
    for _, name in ipairs({ "authorization", "cookie", "proxy-authorization" }) do self:assert_false(has(seen[1], name), name) end
    client:close()
    stop_target(); stop_origin()
  end)
end

function T:test_another_port_on_the_same_host_is_another_origin()
  run(self, function()
    local seen = {}
    local second, stop_second = start(record(seen))
    local first, stop_first = start(function() return redirect(302, "http://127.0.0.1:" .. second .. "/t") end)
    self:assert_true(first ~= second)
    local client <close> = Client()
    client:get(base(first, "/"), { fields = CREDENTIALS }):read_content()
    self:assert_false(has(seen[1], "authorization"), "same host, other port: credentials are stripped")
    client:close()
    stop_second(); stop_first()
  end)
end

function T:test_credentials_stay_stripped_when_a_later_hop_returns_to_the_original_origin()
  run(self, function()
    local seen = {}
    local other, stop_other
    local origin, stop_origin = start(function(request)
      if request.path == "/start" then return redirect(302, base(other, "/mid")) end
      seen[#seen + 1] = { names = " " .. (request.fields:has("Authorization") and "authorization" or "") .. " " }
      return Response(200, { content = "back" })
    end)
    other, stop_other = start(function() return redirect(302, base(origin, "/back")) end)
    local client <close> = Client()
    self:assert_equal("back", client:get(base(origin, "/start"), { fields = CREDENTIALS }):read_content())
    self:assert_false(has(seen[1], "authorization"), "a credential once dropped is not restored")
    client:close()
    stop_other(); stop_origin()
  end)
end

function T:test_a_post_redirected_with_301_302_or_303_to_another_origin_drops_content_entity_fields_and_credentials()
  for _, status in ipairs({ 301, 302, 303 }) do
    run(self, function()
      local seen = {}
      local target, stop_target = start(record(seen))
      local origin, stop_origin = start(function() return redirect(status, base(target, "/t")) end)
      local client <close> = Client()
      client:post(base(origin, "/"), "secret body", { fields = { Authorization = "a", ["Content-Type"] = "text/plain" } }):read_content()
      self:assert_equal("GET", seen[1].method, tostring(status))
      self:assert_equal("", seen[1].content)
      for _, name in ipairs({ "authorization", "content-type", "content-length", "transfer-encoding" }) do
        self:assert_false(has(seen[1], name), status .. " " .. name)
      end
      client:close()
      stop_target(); stop_origin()
    end)
  end
end

local BAD_LOCATIONS = {
  "", "http://", "http://user:pw@127.0.0.1/", "ftp://127.0.0.1/x", "javascript:alert(1)", "http://127.0.0.1/a b",
  "http://127.0.0.1/\195\169", "http://[::1/", "http://127.0.0.1:99999/", "//", "http:///path",
}

function T:test_unusable_locations_are_bad_location_and_free_the_connection()
  for index, location in ipairs(BAD_LOCATIONS) do
    run(self, function()
      local server = scripted(function(stream)
        while read_head(stream) do
          stream:write("HTTP/1.1 302 Found\r\nLocation: " .. location .. "\r\nContent-Length: 0\r\n\r\n")
        end
      end)
      local client <close> = Client({ max_connections_per_origin = 1 })
      local err = self:assert_error(function() client:get(base(server.port)) end)
      self:assert_true(core.is_instance_of(err, core.ProtocolError), index .. ": " .. tostring(err))
      self:assert_equal("bad_location", err.context.reason, index .. ": " .. tostring(location))
      -- The response was closed and its lease released: with one connection allowed, the next request is not stuck.
      local raw = client:get(base(server.port), { redirects = false })
      self:assert_equal(302, raw.status)
      raw:close()
      client:close()
      server.stop()
    end)
  end
end

function T:test_max_redirects_zero_refuses_the_first_redirect_and_redirects_false_returns_it()
  run(self, function()
    local port, stop = start(function(request)
      if request.path == "/final" then return Response(200, { content = "final" }) end
      return redirect(302, "/final")
    end)
    local client <close> = Client({ max_redirects = 0 })
    local err = self:assert_error(function() client:get(base(port, "/start")) end)
    self:assert_equal("too_many_redirects", err.context.reason)
    local raw = client:get(base(port, "/start"), { redirects = false })
    self:assert_equal(302, raw.status)
    raw:close()
    self:assert_equal("final", client:get(base(port, "/final")):read_content(), "no redirect, no limit")
    self:assert_equal("final", client:get(base(port, "/start"), { max_redirects = 1 }):read_content(), "per request")
    client:close()
    stop()
  end)
end

function T:test_cross_origin_307_options_and_extra_fields_to_strip()
  run(self, function()
    local seen = {}
    local target, stop_target = start(record(seen))
    local origin, stop_origin = start(function() return redirect(307, base(target, "/t")) end)
    local client <close> = Client()
    local returned = client:post(base(origin, "/"), "body")
    self:assert_equal(307, returned.status, "a 307 that would replay content to another origin is returned")
    returned:close()
    self:assert_equal(0, #seen)
    local following = client:post(base(origin, "/"), "body", { cross_origin_redirects = true })
    following:read_content()
    self:assert_equal("POST", seen[1].method)
    self:assert_equal("body", seen[1].content)
    local custom <close> = Client({ strip_on_redirect = { "X-Tenant" } })
    custom:get(base(origin, "/"), { fields = { ["X-Tenant"] = "t", ["X-Keep"] = "k" } }):read_content()
    self:assert_false(has(seen[#seen], "x-tenant"))
    self:assert_true(has(seen[#seen], "x-keep"))
    self:assert_error(function() Client({ strip_on_redirect = { "bad name" } }) end)
    self:assert_error(function() Client({ strip_on_redirect = "X-Tenant" }) end)
    client:close(); custom:close()
    stop_target(); stop_origin()
  end)
end

function T:test_expect_continue_sends_the_content_only_after_the_interim_response()
  run(self, function()
    local early
    local server = scripted(function(stream)
      local head = read_head(stream)
      early = head:match("\r\n\r\n(.*)$") -- bytes that came with the head
      local ok, extra = pcall(reactor.deadline, 0.3, stream.read, stream) -- nothing may arrive before the 100
      early = early .. (ok and (extra or "") or "")
      stream:write("HTTP/1.1 100 Continue\r\n\r\n")
      local length = tonumber(head:match("Content%-Length: (%d+)"))
      local received = ""
      while #received < length do received = received .. stream:read() end
      stream:write(support.ok(received))
    end)
    local client <close> = Client()
    self:assert_equal("payload", client:post(base(server.port), "payload", { expect_continue = true }):read_content())
    self:assert_equal("", early, "no content byte before the 100 Continue")
    server.stop()
  end)
end

return T
