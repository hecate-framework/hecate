---@diagnostic disable: missing-fields, param-type-mismatch, need-check-nil, assign-type-mismatch  -- the tests pass invalid arguments on purpose
-- Injection through the client and the server: every refusal has an error class AND nothing reaches the wire.
local test = require("harness.test")
local core = require("hecate.core")
local reactor = require("hecate.reactor")
local http = require("hecate.http")
local json = require("hecate.json")
local T = test.Case("InjectionTest")

local dir = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):gsub("/[^/]*$", "")
local support = dofile(dir .. "/../fixtures/client.lua")
local run, scripted, read_head, with_server = support.run, support.scripted, support.read_head, support.with_server
local Client, Response = http.Client, http.Response

--- Runs `attempt(client, url)` against a server that records every byte it receives; asserts the error class and that
--- the server saw no connection and no byte.
local function refused(self, label, attempt, class)
  run(self, function()
    local received = {}
    local server = scripted(function(stream)
      while true do
        local chunk = stream:read()
        if chunk == nil then return end
        received[#received + 1] = chunk
      end
    end)
    local client <close> = Client()
    local err = self:assert_error(function() attempt(client, "http://127.0.0.1:" .. server.port .. "/") end)
    self:assert_true(core.is_instance_of(err, class or core.ArgumentError), label .. ": " .. tostring(err))
    reactor.sleep(0.05)
    self:assert_equal(0, server.accepted, label .. ": no connection was opened")
    self:assert_equal(0, #received, label .. ": no byte reached the wire")
    server.stop()
  end)
end

local BAD_VALUES = { "a\rb", "a\nb", "a\0b", "a\r\n b", "a\r\nX-Injected: yes", "a\1b", "a\127b", "line\nfeed", "ok\r\n\r\nGET /evil HTTP/1.1" }

function T:test_field_values_with_line_breaks_nul_folds_or_controls_are_refused_before_any_byte()
  for index, value in ipairs(BAD_VALUES) do
    refused(self, "value " .. index, function(client, url) client:get(url, { fields = { ["X-Test"] = value } }) end)
  end
end

function T:test_field_names_that_are_not_tokens_are_refused_before_any_byte()
  for _, name in ipairs({ "X:Y", "X Y", "", "X\r\nInjected", "X\n", "na\0me", "(paren)", "a,b", "a/b" }) do
    refused(self, "name " .. name:gsub("%c", "?"), function(client, url) client:get(url, { fields = { [name] = "v" } }) end)
  end
end

function T:test_a_method_that_is_not_a_token_is_refused_before_any_byte()
  for _, method in ipairs({ "GET\r\nX: y", "GE T", "", "G\nT", "GET /evil HTTP/1.1\r\n" }) do
    refused(self, "method", function(client, url) client:request(method, url) end)
  end
end

function T:test_urls_that_could_split_the_request_line_are_refused_before_any_byte()
  for _, tail in ipairs({ "\r\nX-Injected: yes", " HTTP/1.1\r\nHost: evil", "\n", "\0", "a b", "\127", "é" }) do
    refused(self, "url", function(client, url) client:get(url .. "path" .. tail) end)
  end
  refused(self, "userinfo", function(client, url) client:get((url:gsub("//", "//user:pw@"))) end)
end

function T:test_content_that_is_not_a_string_a_table_or_a_function_is_refused()
  refused(self, "number", function(client, url) client:post(url, 42) end)
  refused(self, "form pair", function(client, url) client:post(url, nil, { form = { { "a" } } }) end)
  refused(self, "multipart", function(client, url) client:post(url, nil, { multipart = { { name = "a\0", content = "x" } } }) end)
end

function T:test_a_streamed_content_with_line_breaks_cannot_end_its_chunk_framing_early()
  local calls = {}
  with_server(self, function(request)
    calls[#calls + 1] = request.path
    return Response(200, { content = request:read_content() })
  end, nil, function(port)
    local client <close> = Client()
    local evil = "x\r\n0\r\n\r\nGET /smuggled HTTP/1.1\r\nHost: a\r\n\r\n"
    local response = client:post("http://127.0.0.1:" .. port .. "/one", function(write) write(evil); write("\r\n") end)
    self:assert_equal(evil .. "\r\n", response:read_content(), "the server saw the bytes as content, one chunk each")
    self:assert_equal(1, #calls, "no second request was smuggled")
    self:assert_equal("/one", calls[1])
  end)
end

function T:test_form_values_with_line_breaks_are_percent_encoded_on_the_wire()
  local seen = {}
  with_server(self, function(request)
    local names = {}
    for name in request.fields:lines() do names[#names + 1] = string.lower(name) end
    seen[#seen + 1] = { names = " " .. table.concat(names, " ") .. " ", form = request:read_form() }
    return Response(200)
  end, nil, function(port)
    local client <close> = Client()
    client:post("http://127.0.0.1:" .. port .. "/", nil, { form = { { "a", "x\r\nInjected: y" }, { "b\r\nc", "v" } } }):close()
    self:assert_equal("x\r\nInjected: y", seen[1].form:get("a"), "the value arrives intact, as content")
    self:assert_nil(seen[1].names:find(" injected ", 1, true), "and never as a field")
  end)
end

function T:test_a_set_cookie_cannot_inject_a_field_or_split_the_response()
  local SetCookie = http.SetCookie
  for _, value in ipairs({ "x\r\nSet-Cookie: evil=1", "x\nY: z", "x\0y", "a;b", "a b", 'a"b', "a,b" }) do
    local err = self:assert_error(function() SetCookie({ name = "sid", value = value }):format() end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
  end
  for _, name in ipairs({ "s\r\nid", "s id", "s;id", "" }) do
    self:assert_error(function() SetCookie({ name = name, value = "v" }):format() end)
  end
  self:assert_error(function() SetCookie({ name = "sid", value = "v", path = "/;\r\nSet-Cookie: evil=1" }):format() end)
  self:assert_error(function() SetCookie({ name = "sid", value = "v", domain = "a.example\r\nX: y" }):format() end)
  local response = Response(200)
  self:assert_error(function() response.fields:add("Set-Cookie", "a=b\r\nSet-Cookie: evil=1") end)
  self:assert_error(function() response:set_cookie(SetCookie({ name = "sid", value = "ok\r\nX: y" })) end)
  self:assert_equal(0, response.fields:count(), "nothing was added")
end

function T:test_an_action_that_sets_a_field_with_a_line_break_gets_a_500_and_no_split()
  with_server(self, function()
    local response = Response(200, { content = "x" })
    response.fields:add("X-Fine", "ok")
    local ok, err = pcall(response.fields.add, response.fields, "X-Evil", "v\r\nSet-Cookie: pwned=1")
    if not ok then error(err, 0) end -- the action fails: the server answers with problem details
    return response
  end, nil, function(port)
    local client <close> = support.connect(port)
    local response = client:request(support.get("/"))
    self:assert_equal(500, response.status)
    self:assert_nil(response.fields:get("Set-Cookie"))
    self:assert_nil(response.fields:get("X-Evil"))
    local second = support.connect(port)
    self:assert_equal(500, second:request(support.get("/")).status)
    second:close()
  end)
end

return T
