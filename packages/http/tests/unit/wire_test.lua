---@diagnostic disable: missing-fields, param-type-mismatch  -- the tests pass invalid arguments on purpose
local test = require("harness.test")
local http = require("hecate.http")
local wire = require("hecate.http.wire")
local T = test.Case("WireTest")

function T:test_http_date_is_imf_fixdate_whatever_the_locale()
  self:assert_equal("Thu, 01 Jan 1970 00:00:00 GMT", wire.http_date(0))
  self:assert_equal("Sun, 06 Nov 1994 08:49:37 GMT", wire.http_date(784111777)) -- RFC 9110, section 5.6.7
end

function T:test_head_lists_the_fields_in_order()
  local fields = http.Fields({ { "Content-Length", "2" }, { "Set-Cookie", "a=1" }, { "Set-Cookie", "b=2" } })
  self:assert_equal("HTTP/1.1 201 Created\r\nContent-Length: 2\r\nSet-Cookie: a=1\r\nSet-Cookie: b=2\r\n\r\n",
    wire.head(201, "Created", fields))
end

function T:test_a_reason_with_control_characters_never_reaches_the_wire()
  local head = wire.head(200, "OK\r\nX-Injected: 1", http.Fields())
  self:assert_equal("HTTP/1.1 200 OK\r\n\r\n", head)
  self:assert_equal("HTTP/1.1 299 \r\n\r\n", wire.head(299, "a\0b", http.Fields()))
end

function T:test_chunk_encoding()
  self:assert_equal("5\r\nhello\r\n", wire.chunk("hello"))
  self:assert_equal("10\r\n" .. ("x"):rep(16) .. "\r\n", wire.chunk(("x"):rep(16)))
  self:assert_equal("", wire.chunk(""), "an empty chunk would end the content")
  self:assert_equal("0\r\n\r\n", wire.LAST_CHUNK)
end

function T:test_connection_options_are_matched_as_list_items()
  self:assert_true(wire.has_connection_option("keep-alive, Close", "close"))
  self:assert_true(wire.has_connection_option("CLOSE", "close"))
  self:assert_false(wire.has_connection_option("closed", "close"))
  self:assert_false(wire.has_connection_option(nil, "close"))
end
return T
