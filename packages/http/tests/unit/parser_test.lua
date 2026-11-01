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

function T:test_the_lenient_flags_and_the_native_handle_are_not_reachable()
  local p = Parser.request()
  self:assert_nil(p.set_lenient)
  self:assert_nil(parser_module.native, "the native module is not exported")
  self:assert_equal("string", type(getmetatable(p._handle)), "the handle metatable is protected")
  self:assert_nil(p._handle.set_lenient)
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

-- Findings of the native-code review (step 2b) -----------------------------------------------------------------

function T:test_chunked_in_http_1_0_is_rejected()
  local err = self:reject("POST / HTTP/1.0\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n")
  self:assert_equal("chunked_in_http_1_0", err.context.kind)
end

function T:test_only_http_1_0_and_1_1_are_accepted()
  self:assert_nil(select(2, parse("GET / HTTP/1.0\r\n\r\n")))
  for _, line in ipairs({ "GET / HTTP/2.0", "GET / HTTP/0.9", "GET / HTTP/1.2", "GET / HTTP/3.0" }) do
    self:reject(line .. "\r\nHost: h\r\n\r\n")
  end
end

function T:test_rtsp_and_ice_requests_are_refused()
  local err = self:reject("DESCRIBE rtsp://h/x RTSP/1.0\r\nCSeq: 1\r\n\r\n")
  self:assert_equal("unsupported_method", err.context.kind)
  self:reject("SETUP / HTTP/1.1\r\nHost: h\r\n\r\n")
  self:reject("PLAY / HTTP/1.1\r\nHost: h\r\n\r\n")
  self:reject("SOURCE /mount ICE/1.0\r\nHost: h\r\n\r\n")
  self:reject("SOURCE /mount HTTP/1.1\r\nHost: h\r\n\r\n")
  self:reject("GET / RTSP/1.0\r\nHost: h\r\n\r\n")
  self:reject("GET / ICE/1.0\r\nHost: h\r\n\r\n")
end

function T:test_rtsp_and_ice_responses_are_refused()
  for _, line in ipairs({ "RTSP/1.0 200 OK", "ICE/1.0 200 OK", "HTTP/2.0 200 OK" }) do
    local _, err = Parser.response():feed(line .. "\r\nContent-Length: 0\r\n\r\n")
    self:assert_true(err ~= nil, line)
  end
  self:assert_nil(select(2, Parser.response():feed("HTTP/1.0 200 OK\r\nContent-Length: 0\r\n\r\n")))
end

function T:test_the_head_budget_counts_raw_bytes_not_only_values()
  -- Leading whitespace of values and the bytes between fields are not part of any field value.
  local fields = {}
  for i = 1, 30 do fields[i] = "X-" .. i .. ":" .. (" "):rep(3000) .. "v\r\n" end
  local err = self:reject("GET / HTTP/1.1\r\n" .. table.concat(fields) .. "\r\n", 431)
  self:assert_equal("head_too_large", err.context.kind)
end

function T:test_a_flood_of_empty_lines_before_the_request_line_hits_the_head_budget()
  local p = Parser.request({ max_head_size = 1000 })
  local failed
  for _ = 1, 50 do
    local _, err = p:feed(("\r\n"):rep(100))
    if err then failed = err break end
  end
  self:assert_true(failed ~= nil, "unbounded leading CRLF")
  self:assert_equal(431, failed.context.status)
end

function T:test_a_long_reason_phrase_is_bounded()
  local _, err = Parser.response():feed("HTTP/1.1 200 " .. ("r"):rep(9000) .. "\r\n\r\n")
  self:assert_equal("reason_too_long", err.context.kind)
  self:assert_equal(400, err.context.status, "a response has nothing to answer: the generic status")
end

function T:test_chunk_extensions_and_chunk_size_digits_are_bounded()
  local options = { max_head_size = 1000 }
  local head = "POST / HTTP/1.1\r\nHost: h\r\nTransfer-Encoding: chunked\r\n\r\n"
  local p = Parser.request(options)
  local _, err = p:feed(head .. "3;" .. ("e"):rep(5000) .. "=x\r\nabc\r\n0\r\n\r\n")
  self:assert_true(err ~= nil, "chunk extension")
  p = Parser.request(options)
  local failed
  p:feed(head)
  for _ = 1, 20 do
    local _, e = p:feed(("0"):rep(200))
    if e then failed = e break end
  end
  self:assert_true(failed ~= nil, "chunk size digits")
  self:assert_equal(431, failed.context.status)
end

function T:test_pipelined_requests_do_not_share_a_head_budget()
  local one = "GET /x HTTP/1.1\r\nHost: h\r\nX-A: " .. ("a"):rep(100) .. "\r\n\r\n"
  local events, err = Parser.request({ max_head_size = 400 }):feed(one:rep(50))
  self:assert_nil(err)
  self:assert_equal(100, #events)
end

function T:test_skip_body_is_consumed_by_a_final_status_only()
  local p = Parser.response()
  p:skip_body()
  local events, err = p:feed("HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\n")
  self:assert_nil(err)
  self:assert_equal("head,complete,head,complete", kinds(events))
  self:assert_equal(100, events[1].status)
  -- consumed: the next response has its body
  events, err = p:feed("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok")
  self:assert_nil(err)
  self:assert_equal("head,data,complete", kinds(events))
end

function T:test_finish_after_an_error_returns_the_sticky_error()
  local p = Parser.request()
  local _, first = p:feed("GET / HTTP/1.1\r\nA: b\0c\r\n\r\n")
  local events, err = p:finish()
  self:assert_true(err ~= nil)
  self:assert_equal("", kinds(events))
  self:assert_equal(first.context.reason, err.context.reason)
  self:assert_equal(first.context.position, err.context.position)
end

function T:test_feed_and_finish_after_an_upgrade_are_explicit_errors()
  local p = Parser.request()
  local events, err = p:feed("GET /ws HTTP/1.1\r\nHost: h\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n\r\n")
  self:assert_nil(err)
  self:assert_equal("upgrade", events[#events].type)
  local again, e1 = p:feed("GET / HTTP/1.1\r\nHost: h\r\n\r\n")
  self:assert_equal("upgraded", e1.context.kind)
  self:assert_equal("", kinds(again))
  local _, e2 = p:finish()
  self:assert_equal("upgraded", e2.context.kind)
end

function T:test_the_error_position_is_that_of_the_failing_call()
  local p = Parser.request()
  local _, none = p:feed("GET / HTTP/1.1\r\n")
  self:assert_nil(none)
  local text = "Host: h\r\nX: a\0b\r\n\r\n"
  local _, err = p:feed(text)
  self:assert_true(err.context.position <= #text)
  local _, again = p:feed(("x"):rep(10))
  self:assert_equal(err.context.position, again.context.position)
end

function T:test_adjacent_content_is_one_data_event()
  local body = ("x"):rep(100000)
  local events, err = Parser.request():feed("POST / HTTP/1.1\r\nHost: h\r\nContent-Length: 100000\r\n\r\n" .. body)
  self:assert_nil(err)
  self:assert_equal("head,data,complete", kinds(events))
  self:assert_equal(100000, #events[2].data)
end

function T:test_the_events_of_one_call_are_capped_without_losing_any()
  local parts = {}
  for i = 1, 200 do parts[i] = "1\r\n" .. string.char(96 + (i % 26) + 1) .. "\r\n" end
  local text = "POST / HTTP/1.1\r\nHost: h\r\nTransfer-Encoding: chunked\r\n\r\n" .. table.concat(parts) .. "0\r\n\r\n"
  local events, err = Parser.request({ max_events = 4 }):feed(text)
  self:assert_nil(err)
  local body = {}
  for _, e in ipairs(events) do if e.type == "data" then body[#body + 1] = e.data end end
  local expected = {}
  for i = 1, 200 do expected[i] = string.char(96 + (i % 26) + 1) end
  self:assert_equal(table.concat(expected), table.concat(body))
  self:assert_equal("complete", events[#events].type)
  self:assert_equal(202, #events, "head, 200 data, complete")
end

function T:test_options_are_integers_within_the_ceiling_and_known()
  self:assert_error(function() Parser.request({ max_target_size = "8192" }) end)
  self:assert_error(function() Parser.request({ max_target_size = 8192.0 }) end)
  self:assert_error(function() Parser.request({ max_target_size = 16777217 }) end)
  self:assert_error(function() Parser.request({ max_target_sise = 10 }) end)
  self:assert_error(function() Parser.request(5) end)
  Parser.request({ max_target_size = 16777216 })
  local core = require("hecate.core")
  local ok, err = pcall(Parser.request, { bogus = 1 })
  self:assert_false(ok)
  self:assert_true(core.is_instance_of(err, core.ArgumentError))
end

function T:test_failures_carry_a_machine_readable_kind()
  local cases = {
    { "GET /" .. ("a"):rep(9000) .. " HTTP/1.1\r\n\r\n", "target_too_long" },
    { "GET / HTTP/1.1\r\nX-A: " .. ("a"):rep(9000) .. "\r\n\r\n", "field_value_too_large" },
    { "GET / HTTP/1.1\r\n" .. ("N"):rep(9000) .. ": a\r\n\r\n", "field_name_too_large" },
  }
  for _, case in ipairs(cases) do
    local err = select(2, parse(case[1]))
    self:assert_equal(case[2], err.context.kind)
  end
  local plain = select(2, parse("GET / HTTP/1.1\r\nA: b\0c\r\n\r\n"))
  self:assert_nil(plain.context.kind, "an llhttp rejection has no kind of ours")
  local many = {}
  for i = 1, 101 do many[i] = "X-" .. i .. ": v\r\n" end
  self:assert_equal("too_many_fields", select(2, parse("GET / HTTP/1.1\r\n" .. table.concat(many) .. "\r\n")).context.kind)
end

function T:test_close_releases_the_parser()
  local p = Parser.request()
  p:feed("GET / HTTP/1.1\r\nHost: h\r\n")
  p:close()
  p:close()
  self:assert_error(function() p:feed("x") end)
end


-- Found by the conformance vectors (step 2c): llhttp reads a request line without a version as HTTP/0.9 and never
-- calls its version callback; RFC 9112 section 3 requires the HTTP-version.
function T:test_a_request_line_without_a_version_is_rejected()
  local err = self:reject("GET /\r\nHost: h\r\n\r\n")
  self:assert_equal("unsupported_version", err.context.kind)
  self:reject("POST /x\r\nHost: h\r\nContent-Length: 3\r\n\r\nabc")
end

function T:test_in_message_tells_whether_a_message_is_open()
  local p = Parser.request()
  self:assert_false(p:in_message())
  p:feed("GET / HTTP/1.1\r\nHost: h\r\n\r\n")
  self:assert_false(p:in_message(), "a complete message leaves nothing pending")
  p:feed("GET /next HT")
  self:assert_true(p:in_message(), "the start of the next head is pending")
  p:feed("TP/1.1\r\nHost: h\r\nContent-Length: 4\r\n\r\nab")
  self:assert_true(p:in_message(), "content is pending")
  p:feed("cd")
  self:assert_false(p:in_message())
  p:feed("GET / HTTP/1.1\r\nHost: h\r\n\r\nGET /b HTTP/1.1\r\nHo")
  self:assert_true(p:in_message(), "a complete message followed by a partial head")
  p:close()
end

function T:test_a_native_call_that_makes_no_progress_is_a_terminal_internal_error()
  local calls = 0
  local fake = {
    execute = function() calls = calls + 1; return {}, nil, 0 end, -- consumed nothing, no failure, no error
    finish = function() return {}, nil, 0 end,
    in_message = function() return false end,
    close = function() end,
  }
  local p = Parser(fake, "request")
  local events, err = p:feed("GET / HTTP/1.1\r\n")
  self:assert_equal(0, #events)
  self:assert_not_nil(err)
  self:assert_equal("no_progress", err.context.kind)
  self:assert_equal(500, err.context.status)
  local before = calls
  local _, again = p:feed("more")
  self:assert_equal("no_progress", again.context.kind)
  self:assert_equal(before, calls, "terminal: the native parser is not called again")
  local _, finishing = p:finish()
  self:assert_equal("no_progress", finishing.context.kind)
end

return T
