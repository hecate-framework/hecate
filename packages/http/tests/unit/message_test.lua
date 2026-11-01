---@diagnostic disable: missing-fields, param-type-mismatch  -- the tests pass invalid arguments on purpose
local test = require("harness.test")
local http = require("hecate.http")
local T = test.Case("MessageTest")

function T:test_request_splits_the_target()
  local r = http.Request({ method = "GET", target = "/users/42?expand=orders" })
  self:assert_equal("/users/42", r.path)
  self:assert_equal("expand=orders", r.query)
  self:assert_equal("/users/42?expand=orders", r.target)
  self:assert_equal("HTTP/1.1", r.version)
  local plain = http.Request({ target = "/a" })
  self:assert_equal("GET", plain.method)
  self:assert_nil(plain.query)
  self:assert_equal("", http.Request({ target = "/a?" }).query)
end

function T:test_request_has_the_four_parameter_keys()
  local r = http.Request({ target = "/" })
  for _, key in ipairs({ "path", "query", "fields", "cookies" }) do self:assert_equal("table", type(r.parameters[key])) end
end

function T:test_request_rejects_invalid_method_and_target()
  self:assert_error(function() http.Request({ method = "GE T", target = "/" }) end)
  self:assert_error(function() http.Request({ target = "" }) end)
  self:assert_error(function() http.Request({ target = "/a b" }) end)
  self:assert_error(function() http.Request({ target = "/a\r\nX: y" }) end)
  self:assert_error(function() http.Request({}) end)
end

function T:test_request_cookies_and_media_type()
  local f = http.Fields({ { "Cookie", "a=1; b=2" }, { "cookie", "a=9; c=3" }, { "Content-Type", "application/json; charset=utf-8" } })
  local r = http.Request({ target = "/", fields = f, peer_address = { ip = "127.0.0.1" } })
  local cookies = r:cookies()
  self:assert_equal("1", cookies.a)
  self:assert_equal("3", cookies.c)
  self:assert_equal("application/json", r:media_type():essence())
  self:assert_equal("127.0.0.1", r:peer_address().ip)
  self:assert_nil(http.Request({ target = "/" }):media_type())
end

function T:test_response_defaults()
  local r = http.Response()
  self:assert_equal(200, r.status)
  self:assert_equal("OK", r.reason)
  self:assert_equal(0, r.fields:count())
  self:assert_true(r:is_successful())
  self:assert_equal("Created", http.Response(201, { content = "x" }).reason)
  self:assert_equal("", http.Response(299).reason)
  self:assert_equal("custom", http.Response(200, { reason = "custom" }).reason)
end

function T:test_response_rejects_invalid_status_and_content()
  self:assert_error(function() http.Response(99) end)
  self:assert_error(function() http.Response(600) end)
  self:assert_error(function() http.Response("200") end)
  self:assert_error(function() http.Response(204, { content = "x" }) end)
  self:assert_error(function() http.Response(304, { content = "x" }) end)
  self:assert_false(http.Response(404):is_successful())
end

function T:test_response_set_cookie_adds_one_line_each()
  local r = http.Response(200)
  r:set_cookie(http.SetCookie({ name = "a", value = "1" })):set_cookie(http.SetCookie({ name = "b", value = "2", path = "/" }))
  local lines = r.fields:get_all("Set-Cookie")
  self:assert_equal(2, #lines)
  self:assert_equal("b=2; Path=/", lines[2])
end

return T
