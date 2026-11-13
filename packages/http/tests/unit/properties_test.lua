---@diagnostic disable: missing-fields, param-type-mismatch, need-check-nil  -- the tests pass invalid arguments on purpose
-- Deterministic property tests (seeded generators, the same sequence on every platform): the parser, URLs, fields,
-- cookies, forms, media types and the chunk encoder of the server, plus a replay of the fuzz seeds.
local test = require("harness.test")
local core = require("hecate.core")
local http = require("hecate.http")
local util = require("lib.util")
local T = test.Case("PropertiesTest")

local Parser = require("hecate.http.parser")
local wire = require("hecate.http.wire")
local url = require("hecate.http.url")
local form = require("hecate.http.form")

local function generator(seed)
  local state = seed
  return function(n)
    state = (state * 6364136223846793005 + 1442695040888963407) & 0x7fffffffffffffff
    return (state >> 33) % n
  end
end

local function pick(rand, list) return list[rand(#list) + 1] end

local function random_token(rand, length)
  local alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.~!#$%&'*+^`|"
  local out = {}
  for i = 1, 1 + rand(length) do local c = rand(#alphabet) + 1; out[i] = alphabet:sub(c, c) end
  return table.concat(out)
end

local function random_case(rand, text)
  return (text:gsub("%a", function(c) return rand(2) == 0 and c:upper() or c:lower() end))
end

-- Parser ----------------------------------------------------------------------------------------------------------

--- A summary of the events: heads (method, target, fields), the data joined, completes.
local function summary(events)
  local out, data = {}, {}
  for _, event in ipairs(events) do
    if event.type == "head" then
      local fields = {}
      for name, value in event.fields:lines() do fields[#fields + 1] = string.lower(name) .. "=" .. value end
      out[#out + 1] = "head " .. tostring(event.method or event.status) .. " " .. tostring(event.target or event.reason) .. " [" .. table.concat(fields, ";") .. "]"
    elseif event.type == "data" then
      data[#data + 1] = event.data
    elseif event.type == "complete" then
      out[#out + 1] = "data " .. table.concat(data) .. " complete"
      data = {}
    else
      out[#out + 1] = event.type
    end
  end
  return table.concat(out, "\n")
end

local function feed_all(kind, chunks, options)
  local parser = Parser.new(kind, options)
  local all, err = {}, nil
  for _, chunk in ipairs(chunks) do
    local events, failure = parser:feed(chunk)
    for _, event in ipairs(events) do all[#all + 1] = event end
    if failure then err = failure break end
  end
  parser:close()
  return all, err
end

local function split(rand, text, maximum)
  local chunks, pos = {}, 1
  while pos <= #text do
    local n = maximum == 1 and 1 or (1 + rand(maximum))
    chunks[#chunks + 1] = text:sub(pos, pos + n - 1)
    pos = pos + n
  end
  return chunks
end

local METHODS = { "GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS", "HEAD" }

local function random_request(rand)
  local out = { pick(rand, METHODS), " /", random_token(rand, 12):gsub("[^%w%-_.~]", "x"), "?q=", tostring(rand(1000)), " HTTP/1.1\r\nHost: h", tostring(rand(10)), "\r\n" }
  for _ = 1, rand(5) do
    out[#out + 1] = "X-" .. random_token(rand, 8):gsub("[^%w%-]", "z") .. ": " .. string.rep("v", rand(20)) .. "\r\n"
  end
  local mode = rand(3)
  local body = ("b"):rep(rand(60))
  if mode == 0 then
    out[#out + 1] = "Content-Length: " .. #body .. "\r\n\r\n" .. body
  elseif mode == 1 then
    out[#out + 1] = "Transfer-Encoding: chunked\r\n\r\n"
    local pos = 1
    while pos <= #body do
      local n = 1 + rand(10)
      out[#out + 1] = string.format("%x\r\n", #body:sub(pos, pos + n - 1)) .. body:sub(pos, pos + n - 1) .. "\r\n"
      pos = pos + n
    end
    out[#out + 1] = "0\r\n\r\n"
  else
    out[#out + 1] = "\r\n"
  end
  return table.concat(out)
end

function T:test_well_formed_requests_parse_the_same_whole_in_pieces_and_byte_by_byte()
  local rand = generator(11)
  for _ = 1, 200 do
    local burst = {}
    for i = 1, 1 + rand(3) do burst[i] = random_request(rand) end
    local text = table.concat(burst)
    local whole, whole_err = feed_all("request", { text })
    self:assert_nil(whole_err, "a generated message must be valid")
    local expected = summary(whole)
    self:assert_equal(expected, summary((feed_all("request", split(rand, text, 40)))), "random pieces")
    self:assert_equal(expected, summary((feed_all("request", split(rand, text, 1)))), "byte by byte")
  end
end

function T:test_arbitrary_bytes_never_raise_and_the_limits_hold()
  local rand = generator(23)
  local limits = { max_target_size = 64, max_field_size = 64, max_head_size = 256, max_fields = 5, max_events = 8 }
  for _ = 1, 300 do
    local bytes = {}
    for i = 1, rand(400) do bytes[i] = string.char(rand(256)) end
    local text = table.concat(bytes)
    if rand(2) == 0 then text = pick(rand, { "GET /", "POST / HTTP/1.1\r\n", "HTTP/1.1 200 OK\r\n" }) .. text end
    for _, kind in ipairs({ "request", "response" }) do
      local ok, events, err = pcall(function()
        local parser = Parser.new(kind, limits)
        local all, failure = {}, nil
        for _, chunk in ipairs(split(rand, text, 50)) do
          local list, e = parser:feed(chunk)
          for _, event in ipairs(list) do all[#all + 1] = event end
          if e then failure = e break end
        end
        parser:close()
        return all, failure
      end)
      self:assert_true(ok, "the parser raised on arbitrary bytes: " .. tostring(events))
      if err ~= nil then
        self:assert_true(core.is_instance_of(err, core.ProtocolError))
        if kind == "request" then
          self:assert_true(err.context.status == 400 or err.context.status == 414 or err.context.status == 431, "status " .. tostring(err.context.status))
        else
          self:assert_nil(err.context.status, "a response has no status to answer with (OQ-82)")
        end
      end
      for _, event in ipairs(events) do
        if event.type == "head" then self:assert_true(event.fields:count() <= limits.max_fields, "max_fields holds") end
      end
    end
  end
end

function T:test_content_length_with_transfer_encoding_or_two_content_lengths_are_always_refused()
  local rand = generator(31)
  local function ows() return pick(rand, { "", " ", "\t", "  ", " \t" }) end
  for _ = 1, 300 do
    local cl = random_case(rand, "Content-Length") .. ":" .. ows() .. tostring(rand(10)) .. ows()
    local te = random_case(rand, "Transfer-Encoding") .. ":" .. ows() .. random_case(rand, pick(rand, { "chunked", "gzip, chunked" })) .. ows()
    local cl2 = random_case(rand, "Content-Length") .. ":" .. ows() .. tostring(rand(10)) .. ows()
    local lines
    local label
    if rand(2) == 0 then
      lines, label = { cl, te }, "CL+TE"
    else
      lines, label = { cl, cl2 }, "CL+CL"
    end
    if rand(2) == 0 then lines = { lines[2], lines[1] } end
    local text = "POST / HTTP/1.1\r\nHost: h\r\n" .. table.concat(lines, "\r\n") .. "\r\n\r\n0\r\n\r\nGET /hidden HTTP/1.1\r\nHost: h\r\n\r\n"
    local events, err = feed_all("request", { text })
    self:assert_not_nil(err, label .. " accepted: " .. text:gsub("\r\n", "|"))
    self:assert_equal(400, err.context.status)
    for _, event in ipairs(events) do self:assert_true(event.type ~= "head", label .. ": a head was delivered") end
  end
end

function T:test_the_chunk_encoder_of_the_server_decodes_to_the_same_content_through_the_parser()
  local rand = generator(41)
  for _ = 1, 100 do
    local pieces, joined = {}, {}
    for i = 1, 1 + rand(6) do
      local bytes = {}
      for j = 1, 1 + rand(300) do bytes[j] = string.char(rand(256)) end
      pieces[i] = table.concat(bytes)
      joined[#joined + 1] = pieces[i]
    end
    local encoded = {}
    for _, piece in ipairs(pieces) do encoded[#encoded + 1] = wire.chunk(piece) end
    local message = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n" .. table.concat(encoded) .. wire.LAST_CHUNK
    for _, maximum in ipairs({ 1000000, 7, 1 }) do
      local events, err = feed_all("response", split(rand, message, maximum))
      self:assert_nil(err)
      local data = {}
      for _, event in ipairs(events) do if event.type == "data" then data[#data + 1] = event.data end end
      self:assert_equal(table.concat(joined), table.concat(data))
    end
  end
end

function T:test_the_fuzz_seeds_replay_without_raising_whole_and_byte_by_byte()
  local here = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
  local seeds = here:match("^(.*)/tests/unit/") .. "/csrc/fuzz/seeds"
  local names = util.list_dir(seeds)
  self:assert_true(#names >= 5, "the seed corpus is there")
  for _, name in ipairs(names) do
    local file = assert(io.open(seeds .. "/" .. name, "rb"))
    local text = file:read("a")
    file:close()
    for _, kind in ipairs({ "request", "response" }) do
      local whole = pcall(feed_all, kind, { text })
      local bytes = pcall(feed_all, kind, split(generator(1), text, 1))
      self:assert_true(whole and bytes, name .. " (" .. kind .. ") raised")
    end
  end
end

-- URLs ------------------------------------------------------------------------------------------------------------

-- RFC 3986 section 5.4: reference resolution examples against http://a/b/c/d;p?q. The fragment is dropped by `resolve`
-- (a request never carries one), the empty reference is refused, and a reference with a scheme is returned as it is.
local EXAMPLES = {
  { "g:h", "g:h" }, { "g", "http://a/b/c/g" }, { "./g", "http://a/b/c/g" }, { "g/", "http://a/b/c/g/" },
  { "/g", "http://a/g" }, { "//g", "http://g" }, { "?y", "http://a/b/c/d;p?y" }, { "g?y", "http://a/b/c/g?y" },
  { "#s", "http://a/b/c/d;p?q" }, { "g#s", "http://a/b/c/g" }, { "g?y#s", "http://a/b/c/g?y" }, { ";x", "http://a/b/c/;x" },
  { "g;x", "http://a/b/c/g;x" }, { "g;x?y#s", "http://a/b/c/g;x?y" }, { ".", "http://a/b/c/" }, { "./", "http://a/b/c/" },
  { "..", "http://a/b/" }, { "../", "http://a/b/" }, { "../g", "http://a/b/g" }, { "../..", "http://a/" },
  { "../../", "http://a/" }, { "../../g", "http://a/g" },
  { "../../../g", "http://a/g" }, { "../../../../g", "http://a/g" }, { "/./g", "http://a/g" }, { "/../g", "http://a/g" },
  { "g.", "http://a/b/c/g." }, { ".g", "http://a/b/c/.g" }, { "g..", "http://a/b/c/g.." }, { "..g", "http://a/b/c/..g" },
  { "./../g", "http://a/b/g" }, { "./g/.", "http://a/b/c/g/" }, { "g/./h", "http://a/b/c/g/h" }, { "g/../h", "http://a/b/c/h" },
  { "g;x=1/./y", "http://a/b/c/g;x=1/y" }, { "g;x=1/../y", "http://a/b/c/y" },
  { "g?y/./x", "http://a/b/c/g?y/./x" }, { "g?y/../x", "http://a/b/c/g?y/../x" },
  { "g#s/./x", "http://a/b/c/g" }, { "g#s/../x", "http://a/b/c/g" }, { "http:g", "http:g" },
}

function T:test_every_example_of_rfc_3986_section_5_4_resolves()
  local base = url.parse("http://a/b/c/d;p?q")
  for _, example in ipairs(EXAMPLES) do
    self:assert_equal(example[2], (url.resolve(base, example[1])), "reference " .. example[1])
  end
  self:assert_nil((url.resolve(base, "")))
end

function T:test_parsed_urls_round_trip_and_resolving_an_absolute_url_is_the_identity()
  local rand = generator(53)
  for _ = 1, 200 do
    local segments = {}
    for i = 1, rand(4) do segments[i] = random_token(rand, 6):gsub("[^%w%-_.~]", "s") end
    local text = pick(rand, { "http", "https" }) .. "://" .. pick(rand, { "example.org", "a.b", "127.0.0.1", "[::1]" })
      .. (rand(2) == 0 and (":" .. (1 + rand(65535))) or "") .. "/" .. table.concat(segments, "/") .. (rand(2) == 0 and ("?k=" .. rand(100)) or "")
    local parsed = url.parse(text)
    self:assert_not_nil(parsed, text)
    self:assert_equal(parsed.origin .. parsed.target, parsed.scheme .. "://" .. parsed.authority .. parsed.target)
    local again = url.parse(parsed.origin .. parsed.target)
    self:assert_equal(parsed.origin, again.origin)
    self:assert_equal(parsed.target, again.target)
    self:assert_equal(parsed.origin .. parsed.target, (url.resolve(parsed, parsed.origin .. parsed.target)))
  end
end

-- Fields, cookies, media types -----------------------------------------------------------------------------------

function T:test_field_names_are_case_insensitive_whatever_the_case_and_order_is_kept()
  local rand = generator(61)
  for _ = 1, 100 do
    local fields = http.Fields()
    local expected = {}
    local base = random_token(rand, 10):gsub("[^%w%-]", "n")
    for i = 1, 1 + rand(5) do
      fields:add(random_case(rand, base), "v" .. i)
      expected[i] = "v" .. i
    end
    for _ = 1, 5 do
      self:assert_equal("v1", fields:get(random_case(rand, base)))
      self:assert_equal(table.concat(expected, ","), table.concat(fields:get_all(random_case(rand, base)), ","))
      self:assert_true(fields:has(random_case(rand, base)))
    end
    self:assert_equal(#expected, fields:remove(random_case(rand, base)))
    self:assert_equal(0, fields:count())
  end
end

local COOKIE_OCTETS = "abcXYZ019!#$%&'()*+-./:<=>?@[]^_`{|}~"

function T:test_cookies_round_trip_and_a_formatted_cookie_never_breaks_the_header()
  local rand = generator(71)
  for _ = 1, 200 do
    local value = {}
    for i = 1, rand(20) do local c = rand(#COOKIE_OCTETS) + 1; value[i] = COOKIE_OCTETS:sub(c, c) end
    local name = random_token(rand, 8):gsub("[^%w_%-]", "n")
    local set = http.SetCookie({ name = name, value = table.concat(value), path = "/", max_age = rand(1000), http_only = rand(2) == 0, secure = true, same_site = pick(rand, { "Strict", "Lax", "None" }) })
    local formatted = set:format()
    self:assert_nil(formatted:find("[\r\n%z]"), "a formatted cookie holds no line break")
    local parsed = http.Cookie.parse(name .. "=" .. table.concat(value) .. "; other=1")
    self:assert_equal(table.concat(value), parsed[name])
    self:assert_equal("1", parsed.other)
  end
end

function T:test_media_types_round_trip_through_format_and_parse()
  local rand = generator(83)
  for _ = 1, 150 do
    local media = http.MediaType(pick(rand, { "text", "application", "multipart" }), random_token(rand, 8):lower())
    local names = {}
    for i = 1, rand(4) do
      local name = "p" .. i
      local value
      if rand(2) == 0 then
        value = random_token(rand, 8)
      else
        local specials = { "a b", 'q"uote', "semi;colon", "back\\slash", "x,y", "=" }
        value = pick(rand, specials) .. random_token(rand, 4)
      end
      media:set_parameter(name, value)
      names[#names + 1] = name
    end
    local parsed = http.MediaType.parse(media:format())
    self:assert_not_nil(parsed, media:format())
    self:assert_equal(media:essence(), parsed:essence())
    for _, name in ipairs(names) do self:assert_equal(media.parameters[name], parsed.parameters[name], media:format()) end
  end
end

-- Forms -----------------------------------------------------------------------------------------------------------

local function random_text(rand)
  local out = {}
  for i = 1, rand(12) do
    local kind = rand(4)
    local code
    if kind == 0 then code = 1 + rand(127) elseif kind == 1 then code = 128 + rand(1900) elseif kind == 2 then code = 0x800 + rand(0xd000)
    else code = 0x10000 + rand(0x1000) end
    out[i] = utf8.char(code)
  end
  return table.concat(out)
end

function T:test_form_decode_of_encode_gives_the_pairs_back_for_arbitrary_text_and_arbitrary_bytes_never_raise_anything_else()
  local rand = generator(97)
  for _ = 1, 200 do
    local pairs_ = {}
    for i = 1, rand(8) do pairs_[i] = { random_text(rand), random_text(rand) } end
    local back = form.parse_urlencoded(form.encode_urlencoded(pairs_), { max_pairs = 100 })
    local names = {}
    for name, value in back:pairs() do names[#names + 1] = name .. "\0" .. value end
    local expected = {}
    for i, pair in ipairs(pairs_) do expected[i] = pair[1] .. "\0" .. pair[2] end
    -- An entry with an empty name and an empty value is "=" and survives as a pair; a pair list that is empty stays empty.
    self:assert_equal(table.concat(expected, "\1"), table.concat(names, "\1"))
  end
  for _ = 1, 200 do
    local bytes = {}
    for i = 1, rand(30) do bytes[i] = string.char(rand(256)) end
    local encoded = form.encode_urlencoded({ { table.concat(bytes), "v" } })
    local ok, result = pcall(form.parse_urlencoded, encoded)
    if not ok then
      self:assert_true(core.is_instance_of(result, form.FormError), tostring(result))
      local reason = result.context.reason ---@diagnostic disable-line: undefined-field
      self:assert_true(reason == "invalid_utf8" or reason == "nul_in_value", tostring(reason))
    end
  end
end

return T
