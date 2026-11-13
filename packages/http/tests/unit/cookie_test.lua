---@diagnostic disable: assign-type-mismatch  -- the tests pass invalid options on purpose
---@diagnostic disable: missing-fields, param-type-mismatch  -- the tests pass invalid options on purpose
local test = require("harness.test")
local http = require("hecate.http")
local Cookie, SetCookie = http.Cookie, http.SetCookie
local T = test.Case("CookieTest")

function T:test_parse_pairs()
  local map, list = Cookie.parse("a=1; b=2;c=3 ;  d = 4")
  self:assert_equal("1", map.a)
  self:assert_equal("2", map.b)
  self:assert_equal("3", map.c)
  self:assert_equal("4", map.d)
  self:assert_equal(4, #list)
  self:assert_equal("a", list[1][1])
end

function T:test_parse_quoted_value_duplicates_and_malformed()
  local map, list = Cookie.parse('a="x y"; a=2; novalue; =x; b c=1; e=')
  self:assert_equal("x y", map.a)
  self:assert_equal("", map.e)
  self:assert_nil(map.novalue)
  self:assert_nil(map["b c"])
  self:assert_equal(3, #list)
end

-- Review H-1: the pairs are split with `find` and indices, in linear time, with the same results.
function T:test_parse_whitespace_around_names_and_values_and_an_equals_sign_in_a_value()
  local map, list = Cookie.parse(" \t a \t = \t x=y \t ;b=\" q \";  c  =  ")
  self:assert_equal("x=y", map.a)
  self:assert_equal(" q ", map.b)
  self:assert_equal("", map.c)
  self:assert_equal(3, #list)
end

function T:test_parse_a_whitespace_heavy_cookie_in_linear_time()
  local inner = (" "):rep(8000)
  local text = "a" .. inner .. "=" .. inner .. "v" .. inner .. "w" .. inner .. "; b" .. inner .. "c=1; " .. (" \t"):rep(4000)
  local started = os.clock()
  local map, list
  for _ = 1, 10 do map, list = Cookie.parse(text) end
  local elapsed = os.clock() - started
  self:assert_equal("v" .. inner .. "w", map.a)
  self:assert_equal(1, #list, "a name with inner whitespace is not a token")
  self:assert_true(elapsed < 0.5, ("took %.3f s"):format(elapsed))
end

function T:test_parse_non_string_is_empty()
  local map, list = Cookie.parse(nil)
  self:assert_nil(next(map))
  self:assert_equal(0, #list)
end

function T:test_format_attributes_in_order()
  local c = SetCookie({ name = "sid", value = "abc", max_age = 3600, domain = "example.org", path = "/",
    secure = true, http_only = true, same_site = "Lax" })
  self:assert_equal("sid=abc; Max-Age=3600; Domain=example.org; Path=/; Secure; HttpOnly; SameSite=Lax", c:format())
end

function T:test_expires_is_an_imf_fixdate()
  self:assert_equal("Thu, 01 Jan 1970 00:00:00 GMT", Cookie.imf_fixdate(0))
  self:assert_equal("Sun, 06 Nov 1994 08:49:37 GMT", Cookie.imf_fixdate(784111777))
  self:assert_equal("Tue, 29 Feb 2000 23:59:59 GMT", Cookie.imf_fixdate(951868799))
  local c = SetCookie({ name = "a", value = "b", expires = 784111777 })
  self:assert_equal("a=b; Expires=Sun, 06 Nov 1994 08:49:37 GMT", tostring(c))
end

function T:test_injection_is_refused()
  self:assert_error(function() SetCookie({ name = "a b", value = "1" }) end)
  self:assert_error(function() SetCookie({ name = "a", value = "1; Domain=evil" }) end)
  self:assert_error(function() SetCookie({ name = "a", value = "1\r\nX: y" }) end)
  self:assert_error(function() SetCookie({ name = "a", value = "x,y" }) end)
  self:assert_error(function() SetCookie({ name = "a", value = "x y" }) end)
  self:assert_error(function() SetCookie({ name = "a", value = "1", path = "/; Secure" }) end)
  self:assert_error(function() SetCookie({ name = "a", value = "1", domain = "a\r\nb" }) end)
  self:assert_error(function() SetCookie({ name = "a", value = "1", same_site = "Bogus" }) end)
  self:assert_error(function() SetCookie({ name = "a", value = "1", max_age = 1.5 }) end)
  self:assert_error(function() SetCookie({ name = "a", value = "1", same_site = "None" }) end)
  self:assert_equal("a=1; Secure; SameSite=None", SetCookie({ name = "a", value = "1", secure = true, same_site = "None" }):format())
end

return T
