-- The incremental parser (hecate.http.parser, the llhttp binding of ADR 0019): well-formed messages, chunked feeding,
-- and the malformed-request corpus (request smuggling, RFC 9112 sections 6.1, 6.2, 6.3 and 2.2; field value
-- characters, RFC 9110 section 5.5). Every malformed message must end in a ParseError, never in a request.
-- The native module is required at run time: a module that is not built fails the file with the build command.
local test = require("harness.test")
local T = test.Case("ParserTest")

local built, parser_module = pcall(require, "hecate.http.parser")
local Parser, ParseError

function T:set_up()
  if not built then self:fail("hecate.http.native is not built: run `lua tools/run.lua build-native http`\n" .. tostring(parser_module)) end
  Parser, ParseError = parser_module, parser_module.ParseError
end

-- Feeds the whole text; returns the events and the error.
local function parse(text, options)
  local p = Parser.request(options)
  return p:feed(text)
end

local function kinds(events)
  local out = {}
  for _, e in ipairs(events) do out[#out + 1] = e.type end
  return table.concat(out, ",")
end

-- Asserts that `text` is rejected, with the 400-class reason given and no head event.
function T:reject(text, expected_status, options)
  local events, err = parse(text, options)
  self:assert_true(err ~= nil, "accepted: " .. text:gsub("[%c\128-\255]", "?"))
  self:assert_true(require("hecate.core").is_instance_of(err, ParseError))
  self:assert_equal(expected_status or 400, err.context.status)
  for _, e in ipairs(events) do self:assert_true(e.type ~= "head", "a head event came before the rejection") end
  return err
end

-- Well-formed messages ----------------------------------------------------------------------------------------

function T:test_a_simple_request()
  local events, err = parse("GET /users/42?x=1 HTTP/1.1\r\nHost: example.org\r\nAccept: */*\r\n\r\n")
  self:assert_nil(err)
  self:assert_equal("head,complete", kinds(events))
  local head = events[1]
  self:assert_equal("GET", head.method)
  self:assert_equal("/users/42?x=1", head.target)
  self:assert_equal("HTTP/1.1", head.version)
  self:assert_equal("example.org", head.fields:get("host"))
  self:assert_equal("*/*", head.fields:get("ACCEPT"))
  self:assert_true(head.keep_alive)
  self:assert_false(head.upgrade)
  self:assert_nil(head.content_length)
end

function T:test_content_length_body()
  local events, err = parse("POST /a HTTP/1.1\r\nHost: h\r\nContent-Length: 5\r\n\r\nhello")
  self:assert_nil(err)
  self:assert_equal("head,data,complete", kinds(events))
  self:assert_equal(5, events[1].content_length)
  self:assert_equal("hello", events[2].data)
end

function T:test_chunked_body_and_trailers()
  local text = "POST /a HTTP/1.1\r\nHost: h\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nabc\r\n2\r\nde\r\n0\r\nX-Sum: 7\r\n\r\n"
  local events, err = parse(text)
  self:assert_nil(err)
  self:assert_true(events[1].chunked)
  local body = {}
  for _, e in ipairs(events) do if e.type == "data" then body[#body + 1] = e.data end end
  self:assert_equal("abcde", table.concat(body))
  local last = events[#events]
  self:assert_equal("complete", last.type)
  self:assert_equal("7", last.trailers:get("x-sum"))
end

function T:test_feeding_byte_by_byte_gives_the_same_message()
  local text = "POST /p HTTP/1.1\r\nHost: h\r\nX-A: one\r\nContent-Length: 4\r\n\r\nbody"
  local p = Parser.request()
  local all = {}
  for i = 1, #text do
    local events, err = p:feed(text:sub(i, i))
    self:assert_nil(err)
    for _, e in ipairs(events) do all[#all + 1] = e end
  end
  local body = {}
  ---@type hecate.http.parser.Head
  local head
  for _, e in ipairs(all) do
    if e.type == "head" then head = e --[[@as hecate.http.parser.Head]] elseif e.type == "data" then body[#body + 1] = e.data end
  end
  self:assert_equal("/p", head.target)
  self:assert_equal("one", head.fields:get("x-a"))
  self:assert_equal("body", table.concat(body))
  self:assert_equal("complete", all[#all].type)
end

function T:test_pipelined_requests_come_in_order()
  local events, err = parse("GET /1 HTTP/1.1\r\nHost: h\r\n\r\nGET /2 HTTP/1.1\r\nHost: h\r\n\r\n")
  self:assert_nil(err)
  self:assert_equal("head,complete,head,complete", kinds(events))
  self:assert_equal("/1", events[1].target)
  self:assert_equal("/2", events[3].target)
end

function T:test_a_request_before_a_malformed_one_is_still_delivered()
  local events, err = parse("GET /ok HTTP/1.1\r\nHost: h\r\n\r\nGET /bad HTTP/1.1\r\nHost: h\r\nA: b\0c\r\n\r\n")
  self:assert_true(err ~= nil)
  self:assert_equal("head,complete", kinds(events))
  self:assert_equal("/ok", events[1].target)
end

function T:test_a_response()
  local p = Parser.response()
  local events, err = p:feed("HTTP/1.1 404 Not Found\r\nContent-Length: 2\r\nSet-Cookie: a=1\r\nSet-Cookie: b=2\r\n\r\nno")
  self:assert_nil(err)
  self:assert_equal(404, events[1].status)
  self:assert_equal("Not Found", events[1].reason)
  self:assert_equal(2, #events[1].fields:get_all("set-cookie"))
  self:assert_equal("no", events[2].data)
end

function T:test_a_head_response_has_no_body()
  local p = Parser.response()
  p:skip_body()
  local events, err = p:feed("HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\n")
  self:assert_nil(err)
  self:assert_equal("head,complete", kinds(events))
end

function T:test_upgrade_reports_the_rest_of_the_input()
  local text = "GET /ws HTTP/1.1\r\nHost: h\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n\r\nRAW"
  local events, err = parse(text)
  self:assert_nil(err)
  self:assert_true(events[1].upgrade)
  local last = events[#events]
  self:assert_equal("upgrade", last.type)
  self:assert_equal("RAW", text:sub(last.position + 1))
end

function T:test_finish_inside_a_message_is_an_error()
  local p = Parser.request()
  p:feed("GET / HTTP/1.1\r\nHost: h\r\n")
  local _, err = p:finish()
  self:assert_true(err ~= nil)
  local idle = Parser.request()
  self:assert_nil(select(2, idle:finish()))
end

-- Request smuggling (RFC 9112 section 6.3, rules 3 and 4; section 11.2) ------------------------------------------

function T:test_content_length_with_transfer_encoding_is_rejected()
  self:reject("POST / HTTP/1.1\r\nHost: h\r\nContent-Length: 4\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n")
  self:reject("POST / HTTP/1.1\r\nHost: h\r\nTransfer-Encoding: chunked\r\nContent-Length: 4\r\n\r\n0\r\n\r\n")
end

function T:test_duplicate_content_length_is_rejected_even_when_equal()
  self:reject("POST / HTTP/1.1\r\nHost: h\r\nContent-Length: 4\r\nContent-Length: 4\r\n\r\nbody")
  self:reject("POST / HTTP/1.1\r\nHost: h\r\nContent-Length: 4\r\nContent-Length: 5\r\n\r\nbody!")
end

function T:test_an_invalid_content_length_is_rejected()
  self:reject("POST / HTTP/1.1\r\nHost: h\r\nContent-Length: +4\r\n\r\nbody")
  self:reject("POST / HTTP/1.1\r\nHost: h\r\nContent-Length: -1\r\n\r\n")
  self:reject("POST / HTTP/1.1\r\nHost: h\r\nContent-Length: 4, 4\r\n\r\nbody")
  self:reject("POST / HTTP/1.1\r\nHost: h\r\nContent-Length: 0x4\r\n\r\nbody")
  self:reject("POST / HTTP/1.1\r\nHost: h\r\nContent-Length: 99999999999999999999999\r\n\r\n")
end

function T:test_whitespace_before_the_colon_is_rejected()
  self:reject("GET / HTTP/1.1\r\nHost: h\r\nContent-Length : 4\r\n\r\n")
  self:reject("GET / HTTP/1.1\r\nHost : h\r\n\r\n")
end

function T:test_obsolete_line_folding_is_rejected()
  self:reject("GET / HTTP/1.1\r\nHost: h\r\nX-A: one\r\n two\r\n\r\n")
end

function T:test_a_malformed_chunk_size_is_rejected()
  self:reject("POST / HTTP/1.1\r\nHost: h\r\nTransfer-Encoding: chunked\r\n\r\nZZ\r\nabc\r\n0\r\n\r\n")
  self:reject("POST / HTTP/1.1\r\nHost: h\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nabcde\r\n0\r\n\r\n")
end

function T:test_transfer_encoding_not_ending_in_chunked_is_rejected_for_a_request()
  self:reject("POST / HTTP/1.1\r\nHost: h\r\nTransfer-Encoding: chunked, gzip\r\n\r\n0\r\n\r\n")
end

-- Characters (RFC 9110 section 5.5, RFC 9112 section 2.2) -----------------------------------------------------------

function T:test_nul_in_a_field_value_is_rejected()
  self:reject("GET / HTTP/1.1\r\nHost: h\r\nX-A: a\0b\r\n\r\n")
end

function T:test_nul_in_a_field_name_the_target_or_the_method_is_rejected()
  self:reject("GET / HTTP/1.1\r\nHo\0st: h\r\n\r\n")
  self:reject("GET /a\0b HTTP/1.1\r\nHost: h\r\n\r\n")
  self:reject("GE\0T / HTTP/1.1\r\nHost: h\r\n\r\n")
end

function T:test_a_bare_cr_in_a_field_value_is_rejected()
  self:reject("GET / HTTP/1.1\r\nHost: h\r\nX-A: a\rb\r\n\r\n")
end

function T:test_bare_lf_line_endings_are_rejected()
  self:reject("GET / HTTP/1.1\nHost: h\n\n")
  self:reject("GET / HTTP/1.1\r\nHost: h\nX-A: b\r\n\r\n")
  self:reject("GET / HTTP/1.1\r\nHost: h\r\n\n")
end

function T:test_a_malformed_request_line_is_rejected()
  self:reject("get / HTTP/1.1\r\nHost: h\r\n\r\n")
  self:reject("GET / HTTP/1.2x\r\nHost: h\r\n\r\n")
  self:reject("GET /a b HTTP/1.1\r\nHost: h\r\n\r\n")
end

function T:test_the_lenient_flags_are_not_reachable()
  self:assert_nil(Parser.request().set_lenient)
  self:assert_nil(parser_module.native.set_lenient)
  self:reject("GET / HTTP/1.1\r\nHost: h\r\nX-A: a\0b\r\n\r\n")
end

-- Limits (every limit has a safe default) -------------------------------------------------------------------------

function T:test_an_oversized_target_is_rejected_with_414()
  self:reject("GET /" .. ("a"):rep(9000) .. " HTTP/1.1\r\nHost: h\r\n\r\n", 414)
end

function T:test_an_oversized_field_value_or_name_is_rejected_with_431()
  self:reject("GET / HTTP/1.1\r\nHost: h\r\nX-A: " .. ("a"):rep(9000) .. "\r\n\r\n", 431)
  self:reject("GET / HTTP/1.1\r\nHost: h\r\n" .. ("N"):rep(9000) .. ": a\r\n\r\n", 431)
end

function T:test_too_many_fields_or_too_large_a_head_is_rejected_with_431()
  local lines = {}
  for i = 1, 101 do lines[i] = "X-" .. i .. ": v\r\n" end
  self:reject("GET / HTTP/1.1\r\n" .. table.concat(lines) .. "\r\n", 431)
  local big = {}
  for i = 1, 20 do big[i] = "X-" .. i .. ": " .. ("v"):rep(7000) .. "\r\n" end
  self:reject("GET / HTTP/1.1\r\n" .. table.concat(big) .. "\r\n", 431)
end

function T:test_an_oversized_line_is_rejected_when_fed_in_pieces_without_buffering_it_all()
  local p = Parser.request()
  local err = select(2, p:feed("GET /"))
  self:assert_nil(err)
  local failed
  for _ = 1, 100 do
    err = select(2, p:feed(("a"):rep(1000)))
    if err then failed = true break end
  end
  self:assert_true(failed, "an unterminated target must hit the limit")
  self:assert_equal(414, err.context.status)
end

function T:test_the_limits_are_options()
  local p = Parser.request({ max_target_size = 8 })
  local _, err = p:feed("GET /123456789 HTTP/1.1\r\nHost: h\r\n\r\n")
  self:assert_equal(414, err.context.status)
  self:assert_error(function() Parser.request({ max_target_size = 0 }) end)
  self:assert_error(function() Parser.request({ max_fields = "x" }) end)
end

function T:test_a_failed_parser_keeps_failing()
  local p = Parser.request()
  local _, first = p:feed("GET / HTTP/1.1\r\nA: b\0c\r\n\r\n")
  self:assert_true(first ~= nil)
  local events, again = p:feed("GET / HTTP/1.1\r\nHost: h\r\n\r\n")
  self:assert_true(again ~= nil)
  self:assert_equal("", kinds(events))
end

function T:test_the_error_names_the_reason_and_the_position()
  local err = self:reject("GET / HTTP/1.1\r\nHost: h\r\nX-A: a\0b\r\n\r\n")
  self:assert_equal("string", type(err.context.reason))
  self:assert_equal("integer", math.type(err.context.position))
end

function T:test_arguments_are_checked()
  self:assert_error(function() Parser.request():feed(nil) end)
  self:assert_error(function() Parser.new("both") end)
end

return T
