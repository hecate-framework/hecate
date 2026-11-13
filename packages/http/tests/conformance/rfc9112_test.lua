-- Conformance vectors for hecate.http.parser against RFC 9112 (HTTP/1.1) and RFC 9110 (semantics). The vectors are
-- data: a message, and either what the parser must deliver or the ParseError it must return (`status`, optionally
-- `kind`). Differences between llhttp and the RFCs are asserted as they are (and listed in packages/http/README.md,
-- "Known limits"): a vector marked `llhttp = "..."` names the RFC behaviour that the parser does not have.
-- Every message is also fed byte by byte: the result must be the same as for the whole buffer.
local test = require("harness.test")
local T = test.Case("Rfc9112ConformanceTest")

local built, parser_module = pcall(require, "hecate.http.parser")
local Parser, ParseError

function T:set_up()
  if not built then self:fail("hecate.http.native is not built: run `lua tools/run.lua build-native http`\n" .. tostring(parser_module)) end
  Parser, ParseError = parser_module, parser_module.ParseError
end

local function crlf(text) return (text:gsub("\n", "\r\n")) end

-- A compact, comparable summary of the events: "head GET /x | data abc | complete".
local function summary(events)
  local out = {}
  for _, e in ipairs(events) do
    if e.type == "head" then
      out[#out + 1] = e.method and ("head " .. e.method .. " " .. e.target .. " " .. e.version)
        or ("head " .. e.status .. " " .. e.reason .. " " .. e.version)
    elseif e.type == "data" then
      out[#out + 1] = "data " .. e.data
    elseif e.type == "complete" then
      out[#out + 1] = "complete"
    else
      out[#out + 1] = e.type
    end
  end
  return out
end

-- Runs `text` through a parser (`kind`) whole, then byte by byte. Returns the whole-buffer events and error, after
-- checking that the two ways of feeding agree on the outcome (the body is compared concatenated: the cut of the
-- data events depends on the feeding).
function T:run(kind, text, options, prepare)
  local whole = Parser.new(kind, options)
  if prepare then prepare(whole) end
  local events, err = whole:feed(text)
  local more, finished = whole:finish()
  local bytes = Parser.new(kind, options)
  if prepare then prepare(bytes) end
  local all, byte_err = {}, nil
  for i = 1, #text do
    local got, e = bytes:feed(text:sub(i, i))
    for _, event in ipairs(got) do all[#all + 1] = event end
    if e then byte_err = e break end
    -- After an upgrade the bytes are not HTTP: the parser refuses any further feed (kind `upgraded`).
    if #got > 0 and got[#got].type == "upgrade" then break end
  end
  local function merged(list)
    local out, body = {}, nil
    for _, line in ipairs(summary(list)) do
      if line:sub(1, 5) == "data " then
        body = (body or "") .. line:sub(6)
      else
        if body then out[#out + 1] = "data " .. body body = nil end
        out[#out + 1] = line
      end
    end
    if body then out[#out + 1] = "data " .. body end
    return table.concat(out, " | ")
  end
  self:assert_equal(err == nil, byte_err == nil, "whole buffer and byte by byte disagree on acceptance")
  if err and byte_err then
    self:assert_equal(err.context.status, byte_err.context.status, "status differs when fed byte by byte")
  else
    self:assert_equal(merged(events), merged(all), "events differ when fed byte by byte")
  end
  return events, err, more, finished
end

-- Vectors that are accepted: {name, text, expected summary (merged data), check?} --------------------------------

local function body_of(events)
  local out = {}
  for _, e in ipairs(events) do if e.type == "data" then out[#out + 1] = e.data end end
  return table.concat(out)
end

local function head_of(events) return events[1] end

-- Request-line forms (RFC 9112 section 3) -------------------------------------------------------------------------

local REQUEST_TARGETS = {
  -- origin-form (section 3.2.1)
  { "origin-form", "GET /where?q=now HTTP/1.1\nHost: www.example.org\n\n", "/where?q=now" },
  { "origin-form, root", "GET / HTTP/1.1\nHost: h\n\n", "/" },
  { "origin-form, percent-encoded", "GET /a%20b/%E2%82%AC HTTP/1.1\nHost: h\n\n", "/a%20b/%E2%82%AC" },
  -- absolute-form (section 3.2.2), the example of the RFC
  { "absolute-form", "GET http://www.example.org/pub/WWW/TheProject.html HTTP/1.1\nHost: www.example.org\n\n",
    "http://www.example.org/pub/WWW/TheProject.html" },
  -- authority-form (section 3.2.3), CONNECT only
  { "authority-form", "CONNECT www.example.com:80 HTTP/1.1\nHost: www.example.com:80\n\n", "www.example.com:80" },
  -- asterisk-form (section 3.2.4), OPTIONS only
  { "asterisk-form", "OPTIONS * HTTP/1.1\nHost: www.example.org:8001\n\n", "*" },
}

function T:test_request_target_forms_are_delivered_as_received()
  for _, vector in ipairs(REQUEST_TARGETS) do
    local events, err = self:run("request", crlf(vector[2]))
    self:assert_nil(err, vector[1])
    self:assert_equal(vector[3], head_of(events).target, vector[1])
  end
end

local METHODS = { "GET", "HEAD", "POST", "PUT", "DELETE", "OPTIONS", "TRACE", "PATCH", "QUERY", "PROPFIND" }

function T:test_methods_are_tokens_and_case_sensitive()
  for _, method in ipairs(METHODS) do
    local events, err = self:run("request", ("%s /x HTTP/1.1\r\nHost: h\r\n\r\n"):format(method))
    self:assert_nil(err, method)
    self:assert_equal(method, head_of(events).method)
  end
  -- RFC 9110 section 9.1: the method is case-sensitive; llhttp accepts only its known (upper case) methods.
  local _, err = self:run("request", "get / HTTP/1.1\r\nHost: h\r\n\r\n")
  self:assert_equal(400, err.context.status)
end

-- Malformed request lines, each must be refused with 400 (RFC 9112 section 3, 2.3, 9110 section 15.5.1).
local BAD_REQUEST_LINES = {
  { "no version (HTTP/0.9 simple request, RFC 9112 section 3)", "GET /\r\nHost: h\r\n\r\n" },
  { "no version and no fields", "GET /\r\n\r\n" },
  { "space after the version", "GET / HTTP/1.1 \r\nHost: h\r\n\r\n" },
  { "tab after the version", "GET / HTTP/1.1\t\r\nHost: h\r\n\r\n" },
  { "tab between method and target", "GET\t/ HTTP/1.1\r\nHost: h\r\n\r\n" },
  { "tab as separator", "GET\t/\tHTTP/1.1\r\nHost: h\r\n\r\n" },
  { "space in the target", "GET /a b HTTP/1.1\r\nHost: h\r\n\r\n" },
  { "lower case version name", "GET / http/1.1\r\nHost: h\r\n\r\n" },
  { "version without minor", "GET / HTTP/1\r\nHost: h\r\n\r\n" },
  { "version with two digits", "GET / HTTP/1.10\r\nHost: h\r\n\r\n" },
  { "empty target", "GET  HTTP/1.1\r\nHost: h\r\n\r\n" },
  { "control character in the target", "GET /\1 HTTP/1.1\r\nHost: h\r\n\r\n" },
  { "DEL in the target", "GET /\127 HTTP/1.1\r\nHost: h\r\n\r\n" },
  { "bare CR after the version", "GET / HTTP/1.1\rHost: h\r\n\r\n" },
  { "leading space", " GET / HTTP/1.1\r\nHost: h\r\n\r\n" },
  { "method with a separator character", "G(T / HTTP/1.1\r\nHost: h\r\n\r\n" },
  { "response line in a request", "HTTP/1.1 200 OK\r\nHost: h\r\n\r\n" },
}

function T:test_malformed_request_lines_are_refused_with_400()
  for _, vector in ipairs(BAD_REQUEST_LINES) do
    local events, err = self:run("request", vector[2])
    self:assert_true(err ~= nil, "accepted: " .. vector[1])
    self:assert_true(require("hecate.core").is_instance_of(err, ParseError), vector[1])
    self:assert_equal(400, err.context.status, vector[1])
    self:assert_equal(0, #events, vector[1])
  end
end

-- RFC 9112 section 3: the grammar wants a single SP, but "recipients MAY instead parse on whitespace-delimited word
-- boundaries". llhttp does so for runs of SP (not for HTAB): accepted, and the target is the word, without spaces.
function T:test_runs_of_spaces_in_the_request_line_are_accepted_as_permitted_by_the_rfc()
  for _, line in ipairs({ "GET  / HTTP/1.1", "GET /  HTTP/1.1", "GET   /   HTTP/1.1" }) do
    local events, err = self:run("request", line .. "\r\nHost: h\r\n\r\n")
    self:assert_nil(err, line)
    self:assert_equal("/", head_of(events).target, line)
    self:assert_equal("GET", head_of(events).method, line)
  end
end

-- RFC 9112 section 2.2: a server SHOULD ignore at least one empty line (CRLF) before the request line.
function T:test_one_empty_line_before_the_request_line_is_ignored()
  local events, err = self:run("request", "\r\nGET / HTTP/1.1\r\nHost: h\r\n\r\n")
  self:assert_nil(err)
  self:assert_equal("/", head_of(events).target)
end

-- RFC 9112 section 2.3: HTTP/1.0 and HTTP/1.1 are the versions of this parser.
function T:test_versions()
  local events = self:run("request", "GET / HTTP/1.0\r\n\r\n")
  self:assert_equal("HTTP/1.0", head_of(events).version)
  events = self:run("request", "GET / HTTP/1.1\r\nHost: h\r\n\r\n")
  self:assert_equal("HTTP/1.1", head_of(events).version)
  for _, version in ipairs({ "HTTP/0.9", "HTTP/2.0", "HTTP/1.2", "HTTP/9.9" }) do
    local _, err = self:run("request", ("GET / %s\r\nHost: h\r\n\r\n"):format(version))
    self:assert_equal(400, err.context.status, version)
  end
end

-- Header fields (RFC 9112 section 5, RFC 9110 section 5) ------------------------------------------------------------

function T:test_field_values_are_trimmed_of_optional_whitespace()
  -- RFC 9110 section 5.6.3 (OWS) and section 5.5: leading and trailing whitespace is not part of the value.
  local vectors = {
    { "X-A:v\r\n", "v" },
    { "X-A: v\r\n", "v" },
    { "X-A:    v\r\n", "v" },
    { "X-A:\tv\r\n", "v" },
    { "X-A: \t v \t\r\n", "v" },
    { "X-A: v w\r\n", "v w" },
    { "X-A: v\tw\r\n", "v\tw" },
    { "X-A: v  w\r\n", "v  w" },
  }
  for _, vector in ipairs(vectors) do
    local events, err = self:run("request", "GET / HTTP/1.1\r\nHost: h\r\n" .. vector[1] .. "\r\n")
    self:assert_nil(err, vector[1])
    self:assert_equal(vector[2], head_of(events).fields:get("x-a"), vector[1])
  end
end

function T:test_an_empty_field_value_is_allowed()
  -- RFC 9110 section 5.5: field-value = *field-content, which may be empty.
  for _, line in ipairs({ "X-A:\r\n", "X-A: \r\n", "X-A:  \t \r\n" }) do
    local events, err = self:run("request", "GET / HTTP/1.1\r\nHost: h\r\n" .. line .. "\r\n")
    self:assert_nil(err, line)
    self:assert_equal("", head_of(events).fields:get("x-a"), line)
  end
end

function T:test_field_names_are_case_insensitive_and_keep_their_order()
  local events, err = self:run("request",
    "GET / HTTP/1.1\r\nHOST: h\r\nx-Custom: 1\r\nX-CUSTOM: 2\r\nAccept: a\r\nX-Custom: 3\r\n\r\n")
  self:assert_nil(err)
  local fields = head_of(events).fields
  self:assert_equal("h", fields:get("host"))
  local all = fields:get_all("X-Custom")
  self:assert_equal(3, #all)
  self:assert_equal("1", all[1])
  self:assert_equal("2", all[2])
  self:assert_equal("3", all[3])
  -- RFC 9110 section 5.3: the combined value joins the lines with a comma, in order.
  self:assert_equal("1, 2, 3", fields:combined("x-custom"))
end

function T:test_set_cookie_lines_stay_separate()
  -- RFC 9110 section 5.3 (exception) and RFC 6265 section 3.
  local events, err = self:run("response", "HTTP/1.1 200 OK\r\nSet-Cookie: a=1; Path=/\r\nSet-Cookie: b=2\r\nContent-Length: 0\r\n\r\n")
  self:assert_nil(err)
  self:assert_equal(2, #head_of(events).fields:get_all("set-cookie"))
end

function T:test_a_field_value_may_carry_obs_text_and_visible_characters()
  -- RFC 9110 section 5.5: field-vchar = VCHAR / obs-text.
  local events, err = self:run("request", "GET / HTTP/1.1\r\nHost: h\r\nX-A: caf\xC3\xA9 \"q\" (c) ~!\r\n\r\n")
  self:assert_nil(err)
  self:assert_equal("caf\xC3\xA9 \"q\" (c) ~!", head_of(events).fields:get("x-a"))
end

local BAD_FIELDS = {
  { "no colon", "X-A v\r\n" },
  { "space before the colon (RFC 9112 section 5.1)", "X-A : v\r\n" },
  { "tab before the colon (RFC 9112 section 5.1)", "X-A\t: v\r\n" },
  { "empty field name", ": v\r\n" },
  { "space in the field name", "X A: v\r\n" },
  { "separator in the field name", "X(A): v\r\n" },
  { "non-ASCII in the field name", "X-\xC3\xA9: v\r\n" },
  { "obs-fold with a space (RFC 9112 section 5.2)", "X-A: one\r\n two\r\n" },
  { "obs-fold with a tab (RFC 9112 section 5.2)", "X-A: one\r\n\ttwo\r\n" },
  { "obs-fold after an empty value", "X-A:\r\n two\r\n" },
  { "NUL in the value", "X-A: a\0b\r\n" },
  { "control character in the value", "X-A: a\1b\r\n" },
  { "bare CR in the value", "X-A: a\rb\r\n" },
  { "bare LF ending a field line", "X-A: a\n" },
  { "DEL in the value", "X-A: a\127b\r\n" },
}

function T:test_malformed_field_lines_are_refused_with_400()
  for _, vector in ipairs(BAD_FIELDS) do
    local events, err = self:run("request", "GET / HTTP/1.1\r\nHost: h\r\n" .. vector[2] .. "\r\n")
    self:assert_true(err ~= nil, "accepted: " .. vector[1])
    self:assert_equal(400, err.context.status, vector[1])
    for _, e in ipairs(events) do self:assert_true(e.type ~= "head", vector[1]) end
  end
end

-- RFC 9112 section 5.2: obs-fold in a response may be replaced by SP; llhttp (strict) refuses it instead.
function T:test_obs_fold_in_a_response_is_refused()
  local _, err = self:run("response", "HTTP/1.1 200 OK\r\nX-A: one\r\n two\r\nContent-Length: 0\r\n\r\n")
  self:assert_true(err ~= nil)
  self:assert_nil(err.context.status) -- a response has no status to answer with (OQ-82)
end

-- Message framing, RFC 9112 section 6.3: one vector per rule ----------------------------------------------------------

-- Rule 1: a response to HEAD, and any 1xx, 204 or 304, has no content whatever its fields say.
function T:test_rule_1_responses_without_content()
  local function response(status_line, fields, prepare)
    return self:run("response", status_line .. "\r\n" .. fields .. "\r\n", nil, prepare)
  end
  local events, err = response("HTTP/1.1 204 No Content", "Content-Length: 5\r\n")
  -- llhttp: a 204 with a Content-Length is accepted and has no content, or refused; both are safe. Assert no data.
  if err == nil then self:assert_equal("", body_of(events)) end
  events, err = response("HTTP/1.1 304 Not Modified", "Content-Length: 5\r\nETag: \"x\"\r\n")
  self:assert_nil(err)
  self:assert_equal("", body_of(events))
  self:assert_equal("complete", events[#events].type)
  events, err = response("HTTP/1.1 100 Continue", "")
  self:assert_nil(err)
  self:assert_equal("head,complete", table.concat((function() local t = {} for _, e in ipairs(events) do t[#t + 1] = e.type end return t end)(), ","))
  events, err = response("HTTP/1.1 200 OK", "Content-Length: 5\r\n", function(p) p:skip_content() end)
  self:assert_nil(err)
  self:assert_equal("", body_of(events))
  self:assert_equal("complete", events[#events].type)
  -- 204 with Transfer-Encoding: RFC 9110 section 15.3.5, a server MUST NOT send it; a client reads no content.
  events, err = response("HTTP/1.1 204 No Content", "")
  self:assert_nil(err)
  self:assert_equal("complete", events[#events].type)
end

-- Rule 2: a 2xx response to CONNECT switches to a tunnel (the content is not HTTP). The request side is an upgrade.
function T:test_rule_2_connect_leaves_http()
  local text = "CONNECT www.example.com:443 HTTP/1.1\r\nHost: www.example.com:443\r\n\r\nTUNNEL"
  local events, err = self:run("request", text)
  self:assert_nil(err)
  self:assert_true(head_of(events).upgrade, "CONNECT is reported as leaving HTTP")
  local last = events[#events]
  self:assert_equal("upgrade", last.type)
  self:assert_equal("TUNNEL", text:sub(last.position + 1))
end

-- Rule 3: Transfer-Encoding. The request/response differences are tested below with the Content-Length table.
local TRANSFER_ENCODING_ACCEPTED = {
  { "chunked", "Transfer-Encoding: chunked\r\n" },
  { "chunked, case-insensitive", "Transfer-Encoding: Chunked\r\n" },
  { "chunked, upper case", "Transfer-Encoding: CHUNKED\r\n" },
  { "chunked with surrounding whitespace", "Transfer-Encoding:   chunked  \r\n" },
}

function T:test_rule_3_transfer_encoding_chunked_frames_the_request()
  for _, vector in ipairs(TRANSFER_ENCODING_ACCEPTED) do
    local events, err = self:run("request", "POST / HTTP/1.1\r\nHost: h\r\n" .. vector[2] .. "\r\n3\r\nabc\r\n0\r\n\r\n")
    self:assert_nil(err, vector[1])
    self:assert_true(head_of(events).chunked, vector[1])
    self:assert_equal("abc", body_of(events), vector[1])
  end
end

function T:test_rule_3_a_coding_list_ending_in_chunked_is_accepted()
  -- RFC 9112 section 6.1: gzip, chunked: the framing is chunked; the server decodes gzip itself (not the parser).
  local events, err = self:run("request",
    "POST / HTTP/1.1\r\nHost: h\r\nTransfer-Encoding: gzip, chunked\r\n\r\n3\r\nabc\r\n0\r\n\r\n")
  self:assert_nil(err)
  self:assert_true(head_of(events).chunked)
  self:assert_equal("gzip, chunked", head_of(events).fields:get("transfer-encoding"))
end

-- RFC 9112 section 6.3 rule 3 (request): a Transfer-Encoding whose final coding is not chunked cannot be framed: 400.
-- Section 6.1 asks for 501 for a coding the server does not understand; llhttp answers a generic refusal, so the
-- parser returns 400 (Known limits).
local TRANSFER_ENCODING_REFUSED_IN_REQUEST = {
  { "gzip alone", "Transfer-Encoding: gzip\r\n" },
  { "chunked then gzip", "Transfer-Encoding: chunked, gzip\r\n" },
  { "identity", "Transfer-Encoding: identity\r\n" },
  { "chunked twice", "Transfer-Encoding: chunked, chunked\r\n" },
  { "chunked twice, two lines", "Transfer-Encoding: chunked\r\nTransfer-Encoding: chunked\r\n" },
  { "chunked, then another line with gzip", "Transfer-Encoding: chunked\r\nTransfer-Encoding: gzip\r\n" },
  { "obfuscated: chunked with a suffix", "Transfer-Encoding: chunkedx\r\n" },
  { "obfuscated: xchunked", "Transfer-Encoding: xchunked\r\n" },
  { "obfuscated: leading vertical tab", "Transfer-Encoding: \11chunked\r\n" },
  { "obfuscated: quoted", "Transfer-Encoding: \"chunked\"\r\n" },
  { "obfuscated: comma and nothing", "Transfer-Encoding: chunked,\r\n" },
  { "obfuscated: empty value", "Transfer-Encoding:\r\n" },
}

function T:test_rule_3_a_request_that_cannot_be_framed_is_refused()
  for _, vector in ipairs(TRANSFER_ENCODING_REFUSED_IN_REQUEST) do
    local events, err = self:run("request", "POST / HTTP/1.1\r\nHost: h\r\n" .. vector[2] .. "\r\n0\r\n\r\n")
    self:assert_true(err ~= nil, "accepted: " .. vector[1])
    self:assert_equal(400, err.context.status, vector[1])
    self:assert_equal(0, #events, vector[1])
  end
end

-- RFC 9112 section 6.1: Transfer-Encoding in an HTTP/1.0 message must not be processed as chunked; the parser refuses it.
function T:test_rule_3_transfer_encoding_in_http_1_0()
  local _, err = self:run("request", "POST / HTTP/1.0\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n")
  self:assert_equal(400, err.context.status)
  self:assert_equal("chunked_in_http_1_0", err.context.reason)
end

-- Rule 3 and section 6.1 and 11.2: both Content-Length and Transfer-Encoding. The RFC allows a server to process the
-- message with Transfer-Encoding (and close the connection) or to refuse it; the parser refuses it (a defence).
function T:test_rule_3_both_content_length_and_transfer_encoding_are_refused_in_either_order()
  local first = "POST / HTTP/1.1\r\nHost: h\r\nContent-Length: 6\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\nX"
  local second = "POST / HTTP/1.1\r\nHost: h\r\nTransfer-Encoding: chunked\r\nContent-Length: 6\r\n\r\n0\r\n\r\nX"
  for _, text in ipairs({ first, second }) do
    local events, err = self:run("request", text)
    self:assert_true(err ~= nil)
    self:assert_equal(400, err.context.status)
    self:assert_equal(0, #events)
  end
  -- Also with a chunked list, an empty Content-Length, and in a response.
  local _, err = self:run("request", "POST / HTTP/1.1\r\nHost: h\r\nContent-Length: 0\r\nTransfer-Encoding: gzip, chunked\r\n\r\n0\r\n\r\n")
  self:assert_equal(400, err.context.status)
  _, err = self:run("response", "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n")
  self:assert_true(err ~= nil)
end

-- Rule 3 (response): a response whose final coding is not chunked has its content delimited by the close.
function T:test_rule_3_a_response_with_a_final_coding_other_than_chunked_ends_with_the_connection()
  local p = Parser.response()
  local events, err = p:feed("HTTP/1.1 200 OK\r\nTransfer-Encoding: gzip\r\n\r\nraw bytes")
  self:assert_nil(err)
  self:assert_equal("raw bytes", body_of(events))
  self:assert_true(events[#events].type ~= "complete", "the message ends with the connection")
  local more, finished = p:finish()
  self:assert_nil(finished)
  self:assert_equal("complete", more[#more].type)
end

-- Rule 4: an invalid Content-Length, or a list of different values. Every case refused with 400 (RFC 9112 section
-- 6.3 rule 5, 9110 section 8.6: Content-Length = 1*DIGIT).
local BAD_CONTENT_LENGTH = {
  { "plus sign", "+4" },
  { "minus sign", "-1" },
  { "hexadecimal", "0x4" },
  { "decimal point", "4.0" },
  { "exponent", "4e0" },
  { "trailing garbage", "4a" },
  { "internal space", "4 4" },
  { "a list of equal values", "4, 4" },
  { "a list of different values", "4, 5" },
  { "list with an empty element", "4," },
  { "empty value", "" },
  { "overflow of 64 bits", "18446744073709551616" },
  { "far overflow", "99999999999999999999999" },
  { "non-ASCII digit", "\xD9\xA4" },
  { "quoted", "\"4\"" },
}

function T:test_rule_5_an_invalid_content_length_is_refused()
  for _, vector in ipairs(BAD_CONTENT_LENGTH) do
    for _, kind in ipairs({ "request", "response" }) do
      local head = kind == "request" and "POST / HTTP/1.1\r\nHost: h\r\n" or "HTTP/1.1 200 OK\r\n"
      local events, err = self:run(kind, head .. "Content-Length: " .. vector[2] .. "\r\n\r\nbody")
      self:assert_true(err ~= nil, kind .. " accepted: " .. vector[1])
      self:assert_equal(kind == "request" and 400 or nil, err.context.status, vector[1])
      for _, e in ipairs(events) do self:assert_true(e.type ~= "head", vector[1]) end
    end
  end
end

-- RFC 9112 section 6.3 rule 5 allows a recipient to merge several identical values ("4, 4" or two lines) or to
-- refuse the message. llhttp refuses both (Known limits): the safe side of the choice.
function T:test_rule_5_duplicate_content_length_is_refused_even_when_identical()
  local _, err = self:run("request", "POST / HTTP/1.1\r\nHost: h\r\nContent-Length: 4\r\nContent-Length: 4\r\n\r\nbody")
  self:assert_equal(400, err.context.status)
  _, err = self:run("request", "POST / HTTP/1.1\r\nHost: h\r\nContent-Length: 4\r\nContent-Length: 5\r\n\r\nbody!")
  self:assert_equal(400, err.context.status)
  _, err = self:run("response", "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nContent-Length: 2\r\n\r\nok")
  self:assert_true(err ~= nil)
  self:assert_nil(err.context.status) -- a response has no status to answer with (OQ-82)
end

-- Rule 5: a valid Content-Length gives the length of the content.
function T:test_rule_5_a_valid_content_length_frames_the_message()
  local vectors = {
    { "zero", "0", "" },
    { "one", "1", "x" },
    { "leading zeros", "0004", "abcd" },
    { "five", "5", "hello" },
  }
  for _, vector in ipairs(vectors) do
    for _, kind in ipairs({ "request", "response" }) do
      local head = kind == "request" and "POST / HTTP/1.1\r\nHost: h\r\n" or "HTTP/1.1 200 OK\r\n"
      local events, err = self:run(kind, head .. "Content-Length: " .. vector[2] .. "\r\n\r\n" .. vector[3])
      self:assert_nil(err, vector[1])
      self:assert_equal(vector[3], body_of(events), vector[1])
      self:assert_equal("complete", events[#events].type, vector[1])
      self:assert_equal(tonumber(vector[2]), head_of(events).content_length, vector[1])
    end
  end
end

function T:test_rule_5_a_short_message_waits_and_a_long_one_leaves_the_rest_for_the_next_message()
  local p = Parser.request()
  local events, err = p:feed("POST / HTTP/1.1\r\nHost: h\r\nContent-Length: 10\r\n\r\n12345")
  self:assert_nil(err)
  self:assert_true(events[#events].type ~= "complete")
  local _, finished = p:finish()
  self:assert_true(finished ~= nil, "the connection closed inside the content")
  -- Content longer than the length is the next message: here a request line that is not valid.
  events, err = Parser.request():feed("POST / HTTP/1.1\r\nHost: h\r\nContent-Length: 2\r\n\r\nokGET / HTTP/1.1\r\nHost: h\r\n\r\n")
  self:assert_nil(err)
  self:assert_equal("head,data,complete,head,complete", (function()
    local t = {} for _, e in ipairs(events) do t[#t + 1] = e.type end return table.concat(t, ",")
  end)())
  events, err = Parser.request():feed("POST / HTTP/1.1\r\nHost: h\r\nContent-Length: 2\r\n\r\nokJUNK\r\n\r\n")
  self:assert_true(err ~= nil, "the bytes after the content must parse as a request line")
end

-- Rule 6: a request without Content-Length and Transfer-Encoding has no content.
function T:test_rule_6_a_request_without_framing_fields_has_no_content()
  for _, method in ipairs({ "GET", "POST", "PUT", "DELETE" }) do
    local events, err = self:run("request", method .. " / HTTP/1.1\r\nHost: h\r\n\r\n")
    self:assert_nil(err, method)
    self:assert_equal("head,complete", (function()
      local t = {} for _, e in ipairs(events) do t[#t + 1] = e.type end return table.concat(t, ",")
    end)(), method)
  end
end

-- Rule 7: a response without them is delimited by the close of the connection.
function T:test_rule_7_a_response_without_framing_fields_ends_with_the_connection()
  local p = Parser.response()
  local events, err = p:feed("HTTP/1.1 200 OK\r\nServer: x\r\n\r\npart one, ")
  self:assert_nil(err)
  local more
  more, err = p:feed("part two")
  self:assert_nil(err)
  for _, e in ipairs(more) do events[#events + 1] = e end
  self:assert_equal("part one, part two", body_of(events))
  self:assert_true(events[#events].type ~= "complete")
  self:assert_false(head_of(events).keep_alive, "RFC 9112 section 9.3: the connection cannot stay open")
  local ended, finished = p:finish()
  self:assert_nil(finished)
  self:assert_equal("complete", ended[#ended].type)
end

-- Rule 8: a request whose length cannot be determined (the connection closed inside the head or the content).
function T:test_rule_8_a_message_cut_short_is_an_error_when_the_connection_closes()
  for _, text in ipairs({
    "GET / HTTP/1.1\r\nHost: h\r\n",
    "GET / HTT",
    "POST / HTTP/1.1\r\nHost: h\r\nContent-Length: 4\r\n\r\nab",
    "POST / HTTP/1.1\r\nHost: h\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nab",
    "POST / HTTP/1.1\r\nHost: h\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n",
  }) do
    local p = Parser.request()
    local _, err = p:feed(text)
    self:assert_nil(err)
    local _, finished = p:finish()
    self:assert_true(finished ~= nil, text)
  end
  local p = Parser.response()
  p:feed("HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nabc")
  local _, finished = p:finish()
  self:assert_true(finished ~= nil, "a response cut inside its Content-Length")
end

-- Chunked coding (RFC 9112 section 7.1) ---------------------------------------------------------------------------

local CHUNKED_HEAD = "POST / HTTP/1.1\r\nHost: h\r\nTransfer-Encoding: chunked\r\n\r\n"

function T:test_chunked_example_of_rfc_9112_section_7_1_3()
  -- The pseudocode of section 7.1.3 decodes "4\r\nWiki\r\n6\r\npedia \r\nE\r\nin \r\n\r\nchunks.\r\n0\r\n\r\n".
  local events, err = self:run("request", CHUNKED_HEAD .. "4\r\nWiki\r\n6\r\npedia \r\nE\r\nin \r\n\r\nchunks.\r\n0\r\n\r\n")
  self:assert_nil(err)
  self:assert_equal("Wikipedia in \r\n\r\nchunks.", body_of(events))
  self:assert_equal("complete", events[#events].type)
  self:assert_nil(events[#events].trailers)
end

function T:test_chunk_sizes_are_hexadecimal_in_either_case_with_leading_zeros()
  for _, size in ipairs({ "a", "A", "0a", "000A", "00000000000a" }) do
    local events, err = self:run("request", CHUNKED_HEAD .. size .. "\r\n0123456789\r\n0\r\n\r\n")
    self:assert_nil(err, size)
    self:assert_equal("0123456789", body_of(events), size)
  end
end

function T:test_a_last_chunk_alone_is_an_empty_content()
  local events, err = self:run("request", CHUNKED_HEAD .. "0\r\n\r\n")
  self:assert_nil(err)
  self:assert_equal("", body_of(events))
  self:assert_equal("complete", events[#events].type)
end

function T:test_chunk_extensions_are_accepted_and_ignored()
  -- RFC 9112 section 7.1.1: chunk-ext = *( BWS ";" BWS chunk-ext-name [ BWS "=" BWS chunk-ext-val ] ).
  for _, ext in ipairs({ ";a", ";a=b", ";a=\"quoted value\"", ";a=b;c=d", ";a=\"q;uo\\\"te\"", ";a=\"\"" }) do
    local events, err = self:run("request", CHUNKED_HEAD .. "3" .. ext .. "\r\nabc\r\n0" .. ext .. "\r\n\r\n")
    self:assert_nil(err, ext)
    self:assert_equal("abc", body_of(events), ext)
  end
end

-- RFC 9112 section 7.1.1 allows BWS around the ";" and the "=" of a chunk extension ("3 ; a = b"). llhttp refuses it
-- (Known limits): the safe side, a strict recipient is never a smuggling vector. Asserted as it is.
function T:test_whitespace_around_chunk_extension_delimiters_is_refused_by_llhttp()
  for _, ext in ipairs({ "; a=b", ";a =b", ";a= b", " ;a=b" }) do
    local _, err = self:run("request", CHUNKED_HEAD .. "3" .. ext .. "\r\nabc\r\n0\r\n\r\n")
    self:assert_true(err ~= nil, ext)
    self:assert_equal(400, err.context.status, ext)
  end
end

local BAD_CHUNKED = {
  { "chunk size not hexadecimal", "ZZ\r\nabc\r\n0\r\n\r\n" },
  { "empty chunk size", "\r\nabc\r\n0\r\n\r\n" },
  { "negative chunk size", "-3\r\nabc\r\n0\r\n\r\n" },
  { "chunk size with 0x", "0x3\r\nabc\r\n0\r\n\r\n" },
  { "chunk size with plus", "+3\r\nabc\r\n0\r\n\r\n" },
  { "chunk size overflows 64 bits", "10000000000000000\r\nabc\r\n0\r\n\r\n" },
  { "chunk longer than its size", "3\r\nabcde\r\n0\r\n\r\n" },
  { "chunk without the CRLF after the data", "3\r\nabc0\r\n\r\n" },
  { "chunk size line ended by a bare LF", "3\nabc\r\n0\r\n\r\n" },
  { "data ended by a bare LF", "3\r\nabc\n0\r\n\r\n" },
  { "space before the chunk size", " 3\r\nabc\r\n0\r\n\r\n" },
  { "extension with a bare CR", "3;a=b\rc\r\nabc\r\n0\r\n\r\n" },
  { "extension name with a separator", "3;a(=b\r\nabc\r\n0\r\n\r\n" },
}

function T:test_malformed_chunked_content_is_refused()
  for _, vector in ipairs(BAD_CHUNKED) do
    local _, err = self:run("request", CHUNKED_HEAD .. vector[2])
    self:assert_true(err ~= nil, "accepted: " .. vector[1])
    self:assert_equal(400, err.context.status, vector[1])
  end
end

function T:test_trailers_example_of_rfc_9112_section_7_1_2()
  local events, err = self:run("request", CHUNKED_HEAD ..
    "3\r\nabc\r\n0\r\nExpires: Wed, 21 Oct 2026 07:28:00 GMT\r\nX-Checksum: ab12\r\nX-Checksum: cd34\r\n\r\n")
  self:assert_nil(err)
  local trailers = events[#events].trailers
  self:assert_equal("Wed, 21 Oct 2026 07:28:00 GMT", trailers:get("expires"))
  self:assert_equal("ab12, cd34", trailers:combined("x-checksum"))
  self:assert_nil(head_of(events).fields:get("expires"), "trailers are not merged into the head")
end

function T:test_trailer_sections_follow_the_field_syntax()
  for _, bad in ipairs({ "X-A : v\r\n", "X-A: a\0b\r\n", "X-A: one\r\n two\r\n", "X-A: a\n" }) do
    local _, err = self:run("request", CHUNKED_HEAD .. "0\r\n" .. bad .. "\r\n")
    self:assert_true(err ~= nil, "accepted trailer " .. bad:gsub("%c", "?"))
    self:assert_equal(400, err.context.status)
  end
  -- An empty trailer value is allowed, like in a head.
  local events, err = self:run("request", CHUNKED_HEAD .. "0\r\nX-A:\r\n\r\n")
  self:assert_nil(err)
  self:assert_equal("", events[#events].trailers:get("x-a"))
end

function T:test_a_chunked_response_with_trailers()
  local events, err = self:run("response",
    "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nTrailer: X-Sum\r\n\r\n2\r\nok\r\n0\r\nX-Sum: 1\r\n\r\n")
  self:assert_nil(err)
  self:assert_equal("ok", body_of(events))
  self:assert_equal("1", events[#events].trailers:get("x-sum"))
end

function T:test_a_chunked_message_is_followed_by_the_next_message()
  local events, err = self:run("request", CHUNKED_HEAD .. "1\r\na\r\n0\r\n\r\nGET /next HTTP/1.1\r\nHost: h\r\n\r\n")
  self:assert_nil(err)
  local heads = {}
  for _, e in ipairs(events) do if e.type == "head" then heads[#heads + 1] = e.target end end
  self:assert_equal("/,/next", table.concat(heads, ","))
end

-- Connection persistence (RFC 9112 section 9.3, RFC 9110 section 7.6.1) ----------------------------------------------

local PERSISTENCE = {
  -- version, Connection field lines, expected keep_alive
  { "HTTP/1.1", "", true },
  { "HTTP/1.1", "Connection: close\r\n", false },
  { "HTTP/1.1", "Connection: Close\r\n", false },
  { "HTTP/1.1", "Connection: CLOSE\r\n", false },
  { "HTTP/1.1", "Connection: keep-alive\r\n", true },
  { "HTTP/1.1", "Connection: keep-alive, close\r\n", false },
  { "HTTP/1.1", "Connection: close, keep-alive\r\n", false },
  { "HTTP/1.1", "Connection: close\r\nConnection: keep-alive\r\n", false },
  { "HTTP/1.1", "Connection: TE\r\n", true },
  { "HTTP/1.0", "", false },
  { "HTTP/1.0", "Connection: keep-alive\r\n", true },
  { "HTTP/1.0", "Connection: Keep-Alive\r\n", true },
  { "HTTP/1.0", "Connection: close\r\n", false },
}

function T:test_connection_persistence_of_requests()
  for _, vector in ipairs(PERSISTENCE) do
    local host = vector[1] == "HTTP/1.1" and "Host: h\r\n" or ""
    local events, err = self:run("request", ("GET / %s\r\n%s%s\r\n"):format(vector[1], host, vector[2]))
    self:assert_nil(err, vector[1] .. " " .. vector[2])
    self:assert_equal(vector[3], head_of(events).keep_alive, vector[1] .. " " .. vector[2])
  end
end

function T:test_connection_persistence_of_responses()
  for _, vector in ipairs(PERSISTENCE) do
    local events, err = self:run("response", ("%s 200 OK\r\n%sContent-Length: 0\r\n\r\n"):format(vector[1], vector[2]))
    self:assert_nil(err, vector[1] .. " " .. vector[2])
    self:assert_equal(vector[3], head_of(events).keep_alive, vector[1] .. " " .. vector[2])
  end
end

function T:test_a_request_after_a_closing_message_is_not_parsed_as_one_message()
  -- RFC 9112 section 9.6: after Connection: close the peer sends nothing more. llhttp reports keep_alive = false;
  -- the server closes after the response. The parser does not refuse the pipelined bytes by itself (Known limits).
  local events, err = self:run("request", "GET /a HTTP/1.1\r\nHost: h\r\nConnection: close\r\n\r\nGET /b HTTP/1.1\r\nHost: h\r\n\r\n")
  self:assert_equal(false, head_of(events).keep_alive)
  if err == nil then
    -- the parser delivered the second message; the caller must not serve it
    self:assert_equal("head,complete,head,complete", (function()
      local t = {} for _, e in ipairs(events) do t[#t + 1] = e.type end return table.concat(t, ",")
    end)())
  end
end

-- Upgrade (RFC 9110 section 7.8) ---------------------------------------------------------------------------------

function T:test_upgrade_is_reported_with_the_position_of_the_new_protocol()
  local text = "GET /chat HTTP/1.1\r\nHost: h\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n\r\nFRAME"
  local events, err = self:run("request", text)
  self:assert_nil(err)
  self:assert_true(head_of(events).upgrade)
  self:assert_equal("FRAME", text:sub(events[#events].position + 1))
  -- Upgrade without the Connection token is not an upgrade (RFC 9110 section 7.8: the sender must also send it).
  events, err = self:run("request", "GET / HTTP/1.1\r\nHost: h\r\nUpgrade: websocket\r\n\r\n")
  self:assert_nil(err)
  self:assert_false(head_of(events).upgrade)
  -- A 101 response.
  events, err = self:run("response", "HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n\r\nFRAME")
  self:assert_nil(err)
  self:assert_equal(101, head_of(events).status)
  self:assert_equal("upgrade", events[#events].type)
end

-- Status line (RFC 9112 section 4) --------------------------------------------------------------------------------

function T:test_status_lines()
  local vectors = {
    { "HTTP/1.1 200 OK", 200, "OK" },
    { "HTTP/1.1 404 Not Found", 404, "Not Found" },
    { "HTTP/1.1 200 ", 200, "" },
    { "HTTP/1.1 200", 200, "" },
    { "HTTP/1.1 599 Custom Reason (x)", 599, "Custom Reason (x)" },
    { "HTTP/1.0 200 OK", 200, "OK" },
  }
  for _, vector in ipairs(vectors) do
    local events, err = self:run("response", vector[1] .. "\r\nContent-Length: 0\r\n\r\n")
    self:assert_nil(err, vector[1])
    self:assert_equal(vector[2], head_of(events).status, vector[1])
    self:assert_equal(vector[3], head_of(events).reason, vector[1])
  end
end

function T:test_malformed_status_lines_are_refused()
  for _, line in ipairs({
    "HTTP/1.1 20 OK", "HTTP/1.1 2000 OK", "HTTP/1.1 abc OK", "HTTP/1.1  200 OK", "HTTP/1.1 200\tOK", "HTTP/1.1 -200 OK",
    "HTTP/1.1", "200 OK", "http/1.1 200 OK",
  }) do
    local _, err = self:run("response", line .. "\r\nContent-Length: 0\r\n\r\n")
    self:assert_true(err ~= nil, "accepted: " .. line:gsub("%c", "?"))
    self:assert_nil(err.context.status) -- a response has no status to answer with (OQ-82)
  end
end

-- RFC 9112 section 4: reason-phrase = *( HTAB / SP / VCHAR / obs-text ), so no control character. llhttp accepts
-- other controls in the reason phrase (Known limits). The reason is informational: nothing decides on it, but a
-- logger must escape it.
function T:test_control_characters_in_a_reason_phrase_are_accepted_by_llhttp()
  for _, reason in ipairs({ "O\0K", "O\1K", "O\127K", "O\27[31mK" }) do
    local events, err = self:run("response", "HTTP/1.1 200 " .. reason .. "\r\nContent-Length: 0\r\n\r\n")
    self:assert_nil(err)
    self:assert_equal(200, head_of(events).status)
  end
end

-- RFC 9112 section 4: status codes are three digits; llhttp accepts any three-digit code (also 000 and 099, which are
-- not defined by RFC 9110 section 15). Known limit: the caller validates the range with hecate.http.status.
function T:test_any_three_digit_status_code_is_delivered()
  local events, err = self:run("response", "HTTP/1.1 099 Odd\r\nContent-Length: 0\r\n\r\n")
  self:assert_nil(err)
  self:assert_equal(99, head_of(events).status)
end

-- Examples quoted in the RFCs ---------------------------------------------------------------------------------------

function T:test_message_format_example_of_rfc_9112_section_2_1()
  -- "GET /hello.txt HTTP/1.1 / User-Agent: ... / Host: www.example.com / Accept-Language: en, mi" (section 3 example).
  local events, err = self:run("request", crlf(
    "GET /hello.txt HTTP/1.1\nUser-Agent: curl/7.64.1 libcurl/7.64.1 OpenSSL/1.1.1j zlib/1.2.11\nHost: www.example.com\nAccept-Language: en, mi\n\n"))
  self:assert_nil(err)
  local fields = head_of(events).fields
  self:assert_equal("www.example.com", fields:get("host"))
  self:assert_equal("en, mi", fields:get("accept-language"))
end

function T:test_response_example_of_rfc_9112_section_4()
  local events, err = self:run("response", crlf(
    "HTTP/1.1 200 OK\nDate: Mon, 27 Jul 2009 12:28:53 GMT\nServer: Apache\nLast-Modified: Wed, 22 Jul 2009 19:15:56 GMT\n"
    .. "ETag: \"34aa387-d-1568eb00\"\nAccept-Ranges: bytes\nContent-Length: 51\nVary: Accept-Encoding\nContent-Type: text/plain\n\n"
    .. "Hello World! My content includes a trailing CRLF.") .. "\r\n")
  self:assert_nil(err)
  self:assert_equal(51, head_of(events).content_length)
  self:assert_equal("Hello World! My content includes a trailing CRLF.\r\n", body_of(events))
  self:assert_equal("Wed, 22 Jul 2009 19:15:56 GMT", head_of(events).fields:get("last-modified"))
end

function T:test_connect_and_options_examples_of_rfc_9112_section_3_2()
  local events, err = self:run("request", crlf("OPTIONS * HTTP/1.1\nHost: www.example.org:8001\n\n"))
  self:assert_nil(err)
  self:assert_equal("*", head_of(events).target)
  self:assert_equal("www.example.org:8001", head_of(events).fields:get("host"))
end

function T:test_expect_100_continue_is_left_to_the_server()
  -- RFC 9110 section 10.1.1: the parser delivers the head; the server answers 100 before reading the content.
  local p = Parser.request()
  local events, err = p:feed("POST / HTTP/1.1\r\nHost: h\r\nContent-Length: 3\r\nExpect: 100-continue\r\n\r\n")
  self:assert_nil(err)
  self:assert_equal("100-continue", events[1].fields:get("expect"))
  self:assert_equal("head", events[#events].type)
  events = p:feed("abc")
  self:assert_equal("complete", events[#events].type)
end

function T:test_a_1xx_response_precedes_the_final_response()
  -- RFC 9112 section 4 and RFC 9110 section 15.2: any number of interim responses before the final one.
  local events, err = self:run("response", "HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 103 Early Hints\r\nLink: </s.css>; rel=preload\r\n\r\nHTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok")
  self:assert_nil(err)
  local statuses = {}
  for _, e in ipairs(events) do if e.type == "head" then statuses[#statuses + 1] = e.status end end
  self:assert_equal("100,103,200", table.concat(statuses, ","))
  self:assert_equal("ok", body_of(events))
end

-- Request smuggling variants (RFC 9112 section 11.2): every message is refused, nothing is delivered --------------

local SMUGGLING = {
  { "CL.TE", "POST / HTTP/1.1\r\nHost: h\r\nContent-Length: 4\r\nTransfer-Encoding: chunked\r\n\r\n1\r\nZ\r\nQ" },
  { "TE.CL", "POST / HTTP/1.1\r\nHost: h\r\nTransfer-Encoding: chunked\r\nContent-Length: 4\r\n\r\n5c\r\nGPOST / HTTP/1.1\r\n\r\n0\r\n\r\n" },
  { "TE.TE with a space before the colon", "POST / HTTP/1.1\r\nHost: h\r\nTransfer-Encoding : chunked\r\nContent-Length: 4\r\n\r\n0\r\n\r\n" },
  { "TE with a tab before the value and a CL", "POST / HTTP/1.1\r\nHost: h\r\nTransfer-Encoding:\tchunked\r\nContent-Length: 4\r\n\r\n0\r\n\r\n" },
  { "CL.CL", "POST / HTTP/1.1\r\nHost: h\r\nContent-Length: 0\r\nContent-Length: 44\r\n\r\n" },
  { "CL with a leading space on a continuation", "POST / HTTP/1.1\r\nHost: h\r\nContent-Length: 4\r\n Content-Length: 5\r\n\r\nbody" },
  { "CL with a bare LF between the fields", "POST / HTTP/1.1\r\nHost: h\nContent-Length: 4\r\n\r\nbody" },
  { "chunk size with a bare LF terminator hiding a request", "POST / HTTP/1.1\r\nHost: h\r\nTransfer-Encoding: chunked\r\n\r\n0\nGET /admin HTTP/1.1\r\nHost: h\r\n\r\n" },
  { "chunk extension with a bare CR", "POST / HTTP/1.1\r\nHost: h\r\nTransfer-Encoding: chunked\r\n\r\n2;x=\rab\r\nab\r\n0\r\n\r\n" },
}

function T:test_request_smuggling_vectors_are_refused()
  for _, vector in ipairs(SMUGGLING) do
    local events, err = self:run("request", vector[2])
    self:assert_true(err ~= nil, "accepted: " .. vector[1])
    self:assert_equal(400, err.context.status, vector[1])
    for _, e in ipairs(events) do self:assert_true(e.type ~= "head", vector[1] .. ": a head was delivered") end
  end
end

return T
