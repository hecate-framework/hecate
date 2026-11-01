---@diagnostic disable: need-check-nil, param-type-mismatch  -- the tests read the fields of a URL they have just parsed
local test = require("harness.test")
local url = require("hecate.http.url")
local T = test.Case("UrlTest")

function T:test_parse_gives_origin_target_and_default_ports()
  local u = url.parse("HTTP://Example.ORG/a/b?x=1#frag")
  self:assert_equal("http", u.scheme)
  self:assert_equal("example.org", u.host)
  self:assert_equal(80, u.port)
  self:assert_equal("/a/b", u.path)
  self:assert_equal("x=1", u.query)
  self:assert_equal("/a/b?x=1", u.target)
  self:assert_equal("example.org", u.authority)
  self:assert_equal("http://example.org", u.origin)
  local s = url.parse("https://h:8443")
  self:assert_equal("/", s.target)
  self:assert_equal("h:8443", s.authority)
  self:assert_equal(443, url.parse("https://h/").port)
  self:assert_equal("/?", url.parse("http://h/?").target)
end

function T:test_ipv6_literals_are_bracketed_in_the_authority_and_bare_as_host()
  local u = url.parse("http://[::1]:8080/x")
  self:assert_equal("::1", u.host)
  self:assert_equal(8080, u.port)
  self:assert_equal("[::1]:8080", u.authority)
  self:assert_equal("[::1]", url.parse("http://[::1]/").authority)
end

function T:test_refused_urls_have_a_reason()
  for _, text in ipairs({
    "http://user:pw@h/", "http://h /", "http://h/\r\nX: y", "http://h/\0", "ftp://h/", "//h/x", "/relative", "http://",
    "http://h:99999/", "http://h:x/", "http://[::1/", "http://[abc]/", "http://h/é", "http://:80/",
  }) do
    local parsed, reason = url.parse(text)
    self:assert_nil(parsed, text)
    self:assert_equal("string", type(reason), text)
  end
  self:assert_nil((url.parse(42)))
end

function T:test_resolve_locations()
  local base = url.parse("http://h:81/a/b/c?q=1")
  self:assert_equal("http://other/x", url.resolve(base, "http://other/x"))
  self:assert_equal("http://h:81/x?y=2", url.resolve(base, "/x?y=2"))
  self:assert_equal("http://h:81/a/b/d", url.resolve(base, "d"))
  self:assert_equal("http://h:81/a/d", url.resolve(base, "../d"))
  self:assert_equal("http://h:81/d", url.resolve(base, "../../../d"))
  self:assert_equal("http://h:81/a/b/c?z", url.resolve(base, "?z"))
  self:assert_equal("http:" .. "//n/p", url.resolve(base, "//n/p"))
  self:assert_equal("http://h:81/a/b/", url.resolve(base, "."))
  self:assert_nil((url.resolve(base, "")))
end

return T
