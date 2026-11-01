---@diagnostic disable: missing-fields, param-type-mismatch  -- the tests pass invalid arguments on purpose
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
  local reader = http.ContentReader(chunks({ "ab", "cd" }))
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
  self:assert_equal("abcd", http.ContentReader(chunks({ "ab", "cd" })):read_all())
  self:assert_equal("", http.ContentReader.of(""):read_all())
  self:assert_equal("hello", http.ContentReader.of("hello"):read_all())
end

function T:test_the_limit_of_the_reader_raises_413_and_is_sticky()
  local reader = http.ContentReader(chunks({ "abc", "def" }), { limit = 4 })
  self:assert_equal("abc", reader:read())
  local err = self:assert_error(function() reader:read() end)
  self:assert_true(core.is_instance_of(err, http.ContentError))
  self:assert_equal(413, err.context.status)
  self:assert_equal("too_large", err.context.reason)
  self:assert_equal(4, err.context.limit)
  self:assert_error(function() reader:read() end)
end

function T:test_read_all_limit_is_lower_than_the_reader_limit()
  local err = self:assert_error(function() http.ContentReader.of("abcdef"):read_all(3) end)
  self:assert_equal(413, err.context.status)
  self:assert_equal("abc", http.ContentReader.of("abc"):read_all(3))
end

function T:test_a_failure_of_the_source_is_sticky_and_raised_as_it_came()
  local boom = core.Error("source failed")
  local reader = http.ContentReader(function() error(boom, 0) end)
  self:assert_true(rawequal(boom, self:assert_error(function() reader:read() end)))
  self:assert_true(rawequal(boom, self:assert_error(function() reader:read() end)))
end

function T:test_request_reads_its_string_content()
  local request = http.Request({ method = "POST", target = "/x", content = "payload" })
  self:assert_equal("payload", request:read_content())
  self:assert_equal("", http.Request({ target = "/x" }):read_content())
  local reader = http.Request({ target = "/x", content = "ab" }):content_reader()
  self:assert_equal("ab", reader:read())
  self:assert_nil(reader:read())
end

function T:test_invalid_arguments()
  self:assert_error(function() http.ContentReader("x") end)
  self:assert_error(function() http.ContentReader(chunks({}), { limit = -1 }) end)
  self:assert_error(function() http.ContentReader.of("a"):read_all("x") end)
end
return T
