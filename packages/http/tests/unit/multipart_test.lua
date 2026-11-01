---@diagnostic disable: missing-fields, param-type-mismatch, need-check-nil  -- the tests pass invalid arguments on purpose
local test = require("harness.test")
local core = require("hecate.core")
local http = require("hecate.http")
local form = require("hecate.http.form")
local multipart = require("hecate.http.multipart")
local T = test.Case("MultipartTest")

local B = "XbOuNdArY"

--- A content stream over `chunks` (a list of strings), counting the pulls.
local function source(chunks, counter)
  local i = 0
  return http.ContentStream(function()
    i = i + 1
    if counter then counter.pulls = i end
    return chunks[i]
  end)
end

--- Splits `text` into pieces of `size` bytes (or by `sizes`, a function giving the next size).
local function split(text, size)
  local chunks, pos = {}, 1
  while pos <= #text do
    local n = type(size) == "function" and size() or size
    chunks[#chunks + 1] = text:sub(pos, pos + n - 1)
    pos = pos + n
  end
  return chunks
end

--- Parses everything: a list of `{ name, filename, content_type, content }`, or nil and the error.
local function parse_all(chunks, boundary, limits)
  local out = {}
  local ok, err = pcall(function()
    local reader = multipart.Reader(source(chunks), boundary or B, limits)
    while true do
      local part = reader:next_part()
      if part == nil then break end
      out[#out + 1] = { part.name, part.filename, part.content_type, part:read_content() }
    end
  end)
  if ok then return out end
  return nil, err
end

local function body(parts, boundary)
  boundary = boundary or B
  local out = {}
  for _, part in ipairs(parts) do
    out[#out + 1] = "--" .. boundary .. "\r\n" .. part[1] .. "\r\n\r\n" .. part[2] .. "\r\n"
  end
  out[#out + 1] = "--" .. boundary .. "--\r\n"
  return table.concat(out)
end

local function disp(name, filename)
  return 'Content-Disposition: form-data; name="' .. name .. '"' .. (filename and ('; filename="' .. filename .. '"') or "")
end

local function expect_error(self, chunks, kind, status, boundary, limits)
  local out, err = parse_all(chunks, boundary, limits)
  self:assert_nil(out, "expected a failure of kind " .. kind)
  self:assert_true(core.is_instance_of(err, core.ProtocolError), tostring(err))
  self:assert_equal(kind, err.context.kind or err.context.reason, tostring(err))
  if status then self:assert_equal(status, err.context.status) end
  return err
end

function T:test_parts_come_in_order_with_names_filenames_types_and_duplicates()
  local text = "preamble to ignore\r\n" .. body({
    { disp("a"), "1" },
    { disp("file", "r.txt") .. "\r\nContent-Type: text/plain", "line1\r\nline2" },
    { disp("a"), "2" },
    { disp("empty"), "" },
  }) .. "epilogue to ignore"
  local parts = parse_all({ text })
  self:assert_equal(4, #parts)
  self:assert_equal("a", parts[1][1]); self:assert_equal("1", parts[1][4])
  self:assert_equal("file", parts[2][1]); self:assert_equal("r.txt", parts[2][2])
  self:assert_equal("text/plain", parts[2][3]); self:assert_equal("line1\r\nline2", parts[2][4])
  self:assert_equal("a", parts[3][1]); self:assert_equal("2", parts[3][4])
  self:assert_equal("", parts[4][4])
  self:assert_nil(parts[1][2])
end

function T:test_the_first_delimiter_needs_no_preceding_line_break_and_a_final_one_ends_the_parsing()
  local parts = parse_all({ body({ { disp("a"), "x" } }) })
  self:assert_equal(1, #parts)
  local reader = multipart.Reader(source({ body({ { disp("a"), "x" } }) }), B)
  reader:next_part()
  self:assert_nil(reader:next_part())
  self:assert_nil(reader:next_part(), "after the end it stays the end")
end

function T:test_any_split_gives_the_whole_result()
  local content = ("0123456789\r\n--" .. B:sub(1, 4) .. "\r\n--"):rep(30) -- boundary-like bytes inside the content
  local text = body({ { disp("a"), content }, { disp("b", "f.bin"), "\0\1\2" }, { disp("c"), "tail" } })
  local whole = parse_all({ text })
  self:assert_equal(3, #whole)
  self:assert_equal(content, whole[1][4])
  for _, size in ipairs({ 1, 2, 3, 5, 7, 16, 100 }) do
    local pieces = parse_all(split(text, size))
    self:assert_equal(3, #pieces, "size " .. size)
    for i = 1, 3 do
      for j = 1, 4 do self:assert_equal(whole[i][j], pieces[i][j], ("size %d part %d field %d"):format(size, i, j)) end
    end
  end
end

function T:test_bytes_that_look_like_the_boundary_but_are_not_a_delimiter_stay_content()
  local tricky = {
    "--" .. B .. "x", -- without a line break before, and followed by more characters
    "\r\n--" .. B .. "x", -- a longer boundary
    "\r\n--" .. B .. "-x", -- one dash only
    "\r\n--" .. B:sub(1, -2), -- a shorter boundary
    "\r\n--" .. B .. " x", -- padding then not a line break
    "\n--" .. B .. "\n", -- bare line feeds
  }
  for _, content in ipairs(tricky) do
    for _, size in ipairs({ 1000, 1, 4 }) do
      local parts = parse_all(split(body({ { disp("a"), content } }), size))
      self:assert_not_nil(parts, content)
      self:assert_equal(1, #parts, content)
      self:assert_equal(content, parts[1][4])
    end
  end
end

function T:test_a_delimiter_followed_by_padding_and_a_line_break_is_a_delimiter()
  local text = "--" .. B .. " \t\r\n" .. disp("a") .. "\r\n\r\nx\r\n--" .. B .. "  \r\n" .. disp("b") .. "\r\n\r\ny\r\n--" .. B .. "--"
  local parts = parse_all({ text })
  self:assert_equal(2, #parts)
  self:assert_equal("y", parts[2][4])
end

function T:test_a_part_content_cannot_smuggle_a_part_by_ending_the_message_early()
  -- The real delimiter ends the part; what follows the final delimiter (here a would-be part) is epilogue.
  local text = body({ { disp("a"), "x" } }) .. "--" .. B .. "\r\n" .. disp("evil") .. "\r\n\r\nowned\r\n--" .. B .. "--\r\n"
  local parts = parse_all({ text })
  self:assert_equal(1, #parts)
end

function T:test_bare_line_feeds_are_refused()
  local text = ("--" .. B .. "\n" .. disp("a") .. "\n\nx\n--" .. B .. "--\n")
  expect_error(self, { text }, "truncated", 400)
  local mixed = "--" .. B .. "\r\n" .. disp("a") .. "\r\nX-Odd: a\nb\r\n\r\nx\r\n--" .. B .. "--"
  expect_error(self, { mixed }, "bad_part_header", 400)
end

function T:test_part_headers_that_inject_or_hide_are_refused()
  local function with(header) return "--" .. B .. "\r\n" .. header .. "\r\n\r\nx\r\n--" .. B .. "--" end
  for _, header in ipairs({
    disp("a") .. "\r\nX: a\rb",
    disp("a") .. "\r\nX: a\0b",
    disp("a") .. "\r\nBad Name: x",
    disp("a") .. "\r\nX : x",
    disp("a") .. "\r\n folded",
    disp("a") .. "\r\nno colon here",
    "Content-Disposition: attachment; name=\"a\"",
    "Content-Disposition: form-data; name=\"a\0b\"",
    disp("a", "f\0.txt"),
  }) do
    expect_error(self, { with(header) }, "bad_part_header", 400)
  end
  expect_error(self, { with("Content-Type: text/plain") }, "missing_name", 400)
  expect_error(self, { "--" .. B .. "\r\n\r\nx\r\n--" .. B .. "--" }, "missing_name", 400)
end

function T:test_filenames_are_exposed_raw_and_a_basename_helper_never_returns_a_path()
  local parts = parse_all({ body({ { disp("f", "../../etc/passwd"), "x" } }) })
  self:assert_equal("../../etc/passwd", parts[1][2], "raw, never trusted")
  local cases = {
    ["../../etc/passwd"] = "passwd", ["C:\\Users\\x\\y.txt"] = "y.txt", ["plain.txt"] = "plain.txt", ["a/b/"] = nil,
    [".."] = nil, ["."] = nil, [""] = nil, ["..hidden"] = "hidden", ["tab\tname"] = "tabname", ["/"] = nil,
    ["na\1me.txt"] = "name.txt", ["dir\\..\\..\\x"] = "x",
  }
  for input, expected in pairs(cases) do self:assert_equal(expected, multipart.basename(input), input) end
  self:assert_nil(multipart.basename(nil))
  local part = multipart.Reader(source({ body({ { disp("f", "../x.txt"), "x" } }) }), B):next_part()
  self:assert_equal("x.txt", part:safe_filename())
end

function T:test_an_extended_filename_is_decoded_and_wins_and_a_bad_one_is_ignored()
  local header = disp("f", "fallback.txt") .. "; filename*=UTF-8''%E2%82%AC%20rates.txt"
  local parts = parse_all({ body({ { header, "x" } }) })
  self:assert_equal("€ rates.txt", parts[1][2])
  local bad = parse_all({ body({ { disp("f", "fallback.txt") .. "; filename*=UTF-8''%ZZ", "x" } }) })
  self:assert_equal("fallback.txt", bad[1][2])
  local other = parse_all({ body({ { disp("f", "fallback.txt") .. "; filename*=ISO-8859-1''%E9.txt", "x" } }) })
  self:assert_equal("fallback.txt", other[1][2], "only UTF-8 is accepted")
end

function T:test_quoted_string_parameters_with_escapes_and_semicolons()
  local header = 'Content-Disposition: form-data; name="a;b\\"c"; filename="x;y.txt"'
  local parts = parse_all({ body({ { header, "x" } }) })
  self:assert_equal('a;b"c', parts[1][1])
  self:assert_equal("x;y.txt", parts[1][2])
end

function T:test_limits_have_a_kind_and_a_status()
  local many = {}
  for i = 1, 5 do many[i] = { disp("p" .. i), "x" } end
  expect_error(self, { body(many) }, "too_many_parts", 413, nil, { max_parts = 4 })
  self:assert_equal(5, #parse_all({ body(many) }, nil, { max_parts = 5 }))
  local big_header = body({ { disp("a") .. "\r\nX-Big: " .. ("h"):rep(300), "x" } })
  expect_error(self, split(big_header, 50), "part_header_too_large", 413, nil, { max_header_size = 200 })
  local long_header_no_end = "--" .. B .. "\r\n" .. disp("a") .. "\r\nX: " .. ("h"):rep(500)
  expect_error(self, split(long_header_no_end, 64), "part_header_too_large", 413, nil, { max_header_size = 200 })
  local err = select(2, parse_all({ body({ { disp("a"), ("x"):rep(100) } }) }, nil, { max_part_size = 50 }))
  self:assert_true(core.is_instance_of(err, http.ContentError))
  self:assert_equal(413, err.context.status)
  expect_error(self, split(body({ { disp("a"), ("x"):rep(100) }, { disp("b"), ("y"):rep(100) } }), 30), "total_too_large", 413, nil, { max_total_size = 150 })
  self:assert_equal(100, multipart.DEFAULTS.max_parts)
  self:assert_equal(8192, multipart.DEFAULTS.max_header_size)
  self:assert_equal(1048576, multipart.DEFAULTS.max_part_size)
  self:assert_equal(1048576, multipart.DEFAULTS.max_total_size)
end

function T:test_a_part_the_consumer_leaves_unread_is_skipped_within_the_part_limit()
  local reader = multipart.Reader(source({ body({ { disp("a"), "unread" }, { disp("b"), "read" } }) }), B)
  reader:next_part()
  local second = reader:next_part()
  self:assert_equal("b", second.name)
  self:assert_equal("read", second:read_content())
  local huge = multipart.Reader(source(split(body({ { disp("a"), ("x"):rep(500) }, { disp("b"), "y" } }), 40)), B, { max_part_size = 100 })
  huge:next_part()
  local err = self:assert_error(function() huge:next_part() end)
  self:assert_equal(413, err.context.status)
end

function T:test_a_missing_final_delimiter_or_a_cut_message_is_truncated()
  expect_error(self, { "--" .. B .. "\r\n" .. disp("a") .. "\r\n\r\nx\r\n" }, "truncated", 400)
  expect_error(self, { "--" .. B .. "\r\n" .. disp("a") .. "\r\n\r\nx" }, "truncated", 400)
  expect_error(self, { "--" .. B .. "\r\n" .. disp("a") .. "\r\n" }, "truncated", 400)
  expect_error(self, { "--" .. B .. "\r\n" }, "truncated", 400)
  expect_error(self, { "no boundary anywhere" }, "truncated", 400)
  expect_error(self, { "" }, "truncated", 400)
  expect_error(self, { "--" .. B }, "truncated", 400)
end

function T:test_boundaries_follow_rfc_2046()
  local function bad(boundary) self:assert_error(function() multipart.Reader(source({}), boundary) end) end
  bad("")
  bad(("a"):rep(71))
  bad("with space")
  bad('quote"d')
  bad("tab\t")
  bad("new\r\nline")
  bad("nul\0")
  bad(nil)
  multipart.Reader(source({}), ("a"):rep(70))
  multipart.Reader(source({}), "0aZ'()+_,-./:=?")
  local err = self:assert_error(function() multipart.Reader(source({}), ("a"):rep(71)) end)
  self:assert_equal("bad_boundary", err.context.kind)
end

function T:test_the_boundary_comes_from_the_media_type_and_other_types_are_415()
  local function media(text) return http.MediaType.parse(text) end
  self:assert_equal("abc", multipart.boundary_of(media("multipart/form-data; boundary=abc")))
  self:assert_error(function() multipart.boundary_of(media('multipart/form-data; boundary="a b"')) end)
  local function kind(text)
    local err = self:assert_error(function() multipart.boundary_of(media(text)) end)
    self:assert_true(core.is_instance_of(err, form.FormError))
    return err.context.kind, err.context.status
  end
  self:assert_equal("unsupported_media_type", (kind("application/json")))
  self:assert_equal(415, select(2, kind("multipart/mixed; boundary=abc")))
  self:assert_equal("bad_boundary", (kind("multipart/form-data")))
  self:assert_equal("bad_boundary", (kind("multipart/form-data; boundary=" .. ("a"):rep(500))))
  self:assert_equal(415, select(2, kind("multipart/form-data; boundary=")), "a media type that does not parse is not a supported one")
end

function T:test_a_nested_multipart_is_delivered_raw_not_parsed()
  local inner = "--IN\r\n" .. disp("x") .. "\r\n\r\nv\r\n--IN--"
  local parts = parse_all({ body({ { disp("files") .. "\r\nContent-Type: multipart/mixed; boundary=IN", inner } }) })
  self:assert_equal(1, #parts)
  self:assert_equal("multipart/mixed; boundary=IN", parts[1][3])
  self:assert_equal(inner, parts[1][4])
end

function T:test_the_reader_pulls_only_what_it_needs()
  local counter = { pulls = 0 }
  local i = 0
  local endless = http.ContentStream(function()
    i = i + 1
    counter.pulls = i
    if i == 1 then return "--" .. B .. "\r\n" .. disp("a") .. "\r\n\r\n" end
    return ("z"):rep(4096)
  end)
  local part = multipart.Reader(endless, B):next_part()
  local before = counter.pulls
  part:stream_content():read()
  part:stream_content():read()
  self:assert_true(counter.pulls <= before + 3, "pulled " .. counter.pulls .. " chunks for two reads")
  local small = multipart.Reader(source({ body({ { disp("a"), "x" } }) }), B)
  self:assert_equal(1, #parse_all({ body({ { disp("a"), "x" } }) }))
  self:assert_not_nil(small)
end

function T:test_building_round_trips_and_quotes_names()
  local content, content_type = multipart.build({
    { name = "a", content = "1" },
    { name = 'we"ird\r\nname', filename = 'f"x.txt', content_type = "text/plain", content = "data\r\n--" },
    { name = "streamed", filename = "s.bin", content = function(write) write("ab"); write("cd") end },
  })
  self:assert_equal("function", type(content), "a function part makes the content a stream")
  local pieces = {}
  content(function(chunk) pieces[#pieces + 1] = chunk end)
  local media = http.MediaType.parse(content_type)
  self:assert_equal("multipart/form-data", media:essence())
  local boundary = multipart.boundary_of(media)
  local parts = parse_all({ table.concat(pieces) }, boundary)
  self:assert_equal(3, #parts)
  self:assert_equal("we%22ird%0D%0Aname", parts[2][1], "quotes and line breaks are percent-encoded, as browsers do")
  self:assert_equal("f%22x.txt", parts[2][2])
  self:assert_equal("data\r\n--", parts[2][4])
  self:assert_equal("abcd", parts[3][4])
  local whole, type2 = multipart.build({ { name = "a", content = "1" } })
  self:assert_equal("string", type(whole), "string parts only: a string with a length")
  self:assert_equal(1, #parse_all({ whole }, multipart.boundary_of(http.MediaType.parse(type2))))
  self:assert_error(function() multipart.build({ { name = "a\0", content = "x" } }) end)
  self:assert_error(function() multipart.build({ { content = "x" } }) end)
  self:assert_error(function() multipart.build({ { name = "a", content = 5 } }) end)
  self:assert_error(function() multipart.build({ { name = "a", content = "x", content_type = "a\r\nb" } }) end)
end

function T:test_a_boundary_found_in_a_string_part_is_never_used()
  -- The generator verifies the candidate against the string parts; force a collision with the first candidates.
  local first = multipart.build({ { name = "a", content = "x" } })
  local boundary = first:match("^%-%-([^\r]+)")
  local content, content_type = multipart.build({ { name = "a", content = "--" .. boundary }, { name = "b", content = "y" } })
  local used = multipart.boundary_of(http.MediaType.parse(content_type))
  self:assert_equal(2, #parse_all({ content }, used))
end

function T:test_basename_is_conservative_for_windows_and_long_names()
  local cases = {
    ['a<b>:c"d|e?f*g.txt'] = "abcdefg.txt", ["name. "] = "name", ["name..."] = "name", ["CON"] = nil, ["con.txt"] = nil,
    ["NUL.tar.gz"] = nil, ["COM1"] = nil, ["lpt9.log"] = nil, ["COM10"] = "COM10", ["console.txt"] = "console.txt",
    ["aux"] = nil, ["Prn.x"] = nil, [" . "] = nil,
  }
  for input, expected in pairs(cases) do self:assert_equal(expected, multipart.basename(input), input) end
  local long = multipart.basename(("a"):rep(300) .. ".txt")
  self:assert_true(#long <= 255, "length " .. #long)
  local multibyte = multipart.basename(("é"):rep(200))
  self:assert_true(#multibyte <= 255 and utf8.len(multibyte) ~= nil, "a cut never splits a character")
end

function T:test_boundaries_differ_between_messages()
  local seen = {}
  for _ = 1, 200 do
    local _, content_type = multipart.build({ { name = "a", content = "x" } })
    local boundary = content_type:match("boundary=(.+)$")
    self:assert_equal(7 + 32, #boundary)
    self:assert_nil(seen[boundary])
    seen[boundary] = true
  end
end

return T
