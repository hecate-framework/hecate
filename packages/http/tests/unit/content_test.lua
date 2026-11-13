---@diagnostic disable: missing-fields, param-type-mismatch, assign-type-mismatch  -- the tests pass invalid arguments on purpose
local test = require("harness.test")
local core = require("hecate.core")
local http = require("hecate.http")
local T = test.Case("ContentTest")

local function chunks(list)
  local i = 0
  return function()
    i = i + 1
    return list[i]
  end
end

function T:test_reader_delivers_chunks_then_nil()
  local reader = http.ContentStream(chunks({ "ab", "cd" }))
  self:assert_false(reader:is_started())
  self:assert_equal("ab", reader:read())
  self:assert_true(reader:is_started())
  self:assert_equal("cd", reader:read())
  self:assert_nil(reader:read())
  self:assert_true(reader:is_finished())
  self:assert_equal(4, reader:consumed())
  self:assert_nil(reader:read())
end

function T:test_read_all_joins_the_chunks()
  self:assert_equal("abcd", http.ContentStream(chunks({ "ab", "cd" })):read_all())
  self:assert_equal("", http.ContentStream.of(""):read_all())
  self:assert_equal("hello", http.ContentStream.of("hello"):read_all())
end

function T:test_the_limit_of_the_reader_raises_413_and_is_sticky()
  local reader = http.ContentStream(chunks({ "abc", "def" }), { limit = 4 })
  self:assert_equal("abc", reader:read())
  local err = self:assert_error(function() reader:read() end)
  self:assert_true(core.is_instance_of(err, http.ContentError))
  self:assert_equal(413, err.context.status)
  self:assert_equal("too_large", err.context.reason)
  self:assert_equal(4, err.context.limit)
  self:assert_error(function() reader:read() end)
end

function T:test_read_all_limit_is_lower_than_the_reader_limit()
  local err = self:assert_error(function() http.ContentStream.of("abcdef"):read_all(3) end)
  self:assert_equal(413, err.context.status)
  self:assert_equal("abc", http.ContentStream.of("abc"):read_all(3))
end

function T:test_a_failure_of_the_source_is_sticky_and_raised_as_it_came()
  local boom = core.Error("source failed")
  local reader = http.ContentStream(function() error(boom, 0) end)
  self:assert_true(rawequal(boom, self:assert_error(function() reader:read() end)))
  self:assert_true(rawequal(boom, self:assert_error(function() reader:read() end)))
end

function T:test_request_reads_its_string_content()
  local request = http.Request({ method = "POST", target = "/x", content = "payload" })
  self:assert_equal("payload", request:read_content())
  self:assert_equal("", http.Request({ target = "/x" }):read_content())
  local reader = http.Request({ target = "/x", content = "ab" }):stream_content()
  self:assert_equal("ab", reader:read())
  self:assert_nil(reader:read())
end

function T:test_request_content_given_by_hand_is_a_string_or_nothing()
  -- OQ-76 (b): only a string can be read back as the content of a request; a table or a function would read as nothing.
  for _, invalid in ipairs({ { a = 1 }, function() end, 42, true }) do
    local err = self:assert_error(function() http.Request({ method = "POST", target = "/x", content = invalid }) end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
    self:assert_true(tostring(err):find("content must be a string", 1, true) ~= nil, tostring(err))
  end
  -- A server request has no `content`: it reads its content from the stream.
  local request = http.Request({ method = "POST", target = "/x", content_stream = http.ContentStream.of("streamed") })
  self:assert_nil(request.content)
  self:assert_equal("streamed", request:read_content())
  self:assert_nil(request.content)
end

function T:test_invalid_arguments()
  self:assert_error(function() http.ContentStream("x") end)
  self:assert_error(function() http.ContentStream(chunks({}), { limit = -1 }) end)
  self:assert_error(function() http.ContentStream.of("a"):read_all("x") end)
end
return T
