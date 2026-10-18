---@diagnostic disable: param-type-mismatch  -- the tests pass invalid arguments on purpose
local test = require("harness.test")
local core = require("hecate.core")
local reactor = require("hecate.reactor")
local net = require("hecate.net")
local T = test.Case("BufferedTest")

--- In-memory stream: `chunks` are returned one per read; when they run out, the stream
--- ends, or raises `fail_after` if set.
local function fake_stream(chunks, fail_after)
  local stream = { sent = {}, closed = false, reads = 0 }
  local index = 0
  function stream:read()
    self.reads = self.reads + 1
    index = index + 1
    if chunks[index] == nil then
      if fail_after then error(fail_after, 0) end
      return nil
    end
    reactor.sleep(0) -- a real stream suspends here
    return chunks[index]
  end
  function stream:write(data)
    if self.write_failure then error(self.write_failure, 0) end
    self.sent[#self.sent + 1] = data
  end
  function stream:close() self.closed = true end
  return stream
end

local function run(fn) return reactor.run(fn) end

function T:test_stream_interface_is_exported()
  self:assert_true(core.is_interface(net.Stream))
end

function T:test_read_line_across_chunks_strips_line_feed_and_carriage_return()
  run(function()
    local reader = net.BufferedReader(fake_stream({ "he", "llo\r", "\nwor", "ld\n" }))
    self:assert_equal("hello", reader:read_line())
    self:assert_equal("world", reader:read_line())
    self:assert_nil(reader:read_line())
  end)
end

function T:test_read_until_finds_a_delimiter_split_between_chunks()
  run(function()
    local reader = net.BufferedReader(fake_stream({ "ab\r", "\n\r", "\ncd" }))
    self:assert_equal("ab", reader:read_until("\r\n"))
    self:assert_equal("", reader:read_until("\r\n"))
    self:assert_equal(2, reader:buffered())
  end)
end

function T:test_read_exact_returns_complete_data_and_keeps_the_rest()
  run(function()
    local reader = net.BufferedReader(fake_stream({ "abc", "defg" }))
    self:assert_equal("abcde", reader:read_exact(5))
    self:assert_equal(2, reader:buffered())
    self:assert_equal("", reader:read_exact(0))
    self:assert_equal("fg", reader:read_exact(2))
  end)
end

function T:test_partial_read_never_leaks_on_end_of_stream()
  run(function()
    local reader = net.BufferedReader(fake_stream({ "abc" }))
    local ok, err = pcall(reader.read_exact, reader, 5)
    self:assert_false(ok)
    self:assert_true(core.is_instance_of(err, net.EndOfStreamError))
    self:assert_true(core.is_instance_of(err, core.NetworkError))
    ---@diagnostic disable-next-line: undefined-field
    self:assert_equal(3, err.context.buffered)
    -- The bytes are still there for a smaller read.
    self:assert_equal("abc", reader:read_exact(3))
    local ok2, err2 = pcall(reader.read_line, (net.BufferedReader(fake_stream({ "no newline" }))))
    self:assert_false(ok2)
    self:assert_true(core.is_instance_of(err2, net.EndOfStreamError))
  end)
end

function T:test_stream_failure_mid_line_loses_nothing()
  run(function()
    local boom = core.NetworkError("connection reset")
    local reader = net.BufferedReader(fake_stream({ "par", "tial" }, boom))
    local ok, err = pcall(reader.read_line, reader)
    self:assert_false(ok)
    self:assert_equal(boom, err)
    self:assert_equal(7, reader:buffered())
  end)
end

function T:test_cancelled_read_keeps_received_bytes()
  run(function()
    local stream = fake_stream({ "abc" })
    function stream:read()
      if not self.gave then
        self.gave = true
        return "abc"
      end
      reactor.sleep(10)
    end
    local reader = net.BufferedReader(stream)
    local ok, err = pcall(reactor.deadline, 0.01, reader.read_line, reader)
    self:assert_false(ok)
    self:assert_true(core.is_instance_of(err, core.DeadlineExceededError))
    self:assert_equal(3, reader:buffered())
  end)
end

function T:test_limit_stops_an_unbounded_line()
  run(function()
    local reader = net.BufferedReader(fake_stream({ "aaaa", "aaaa", "\n" }), { limit = 6 })
    local err = self:assert_error(function() reader:read_line() end)
    self:assert_true(core.is_instance_of(err, core.ProtocolError))
    self:assert_equal(6, err.context.limit)
    local short = net.BufferedReader(fake_stream({ "abc\n" }), { limit = 3 })
    self:assert_equal("abc", short:read_line())
  end)
end

function T:test_read_some_returns_buffered_bytes_first()
  run(function()
    local reader = net.BufferedReader(fake_stream({ "abcdef" }))
    self:assert_equal("ab", reader:read_some(2))
    self:assert_equal("cdef", reader:read_some())
    self:assert_nil(reader:read_some())
  end)
end

function T:test_reads_are_serialised_between_coroutines()
  local got = {}
  run(function()
    local reader = net.BufferedReader(fake_stream({ "aa", "bb\n", "cc\n" }))
    reactor.scope(function(scope)
      scope:fork(function() local line = reader:read_line(); got[#got + 1] = line end)
      scope:fork(function() local line = reader:read_line(); got[#got + 1] = line end)
    end)
  end)
  table.sort(got)
  self:assert_equal("aabb,cc", table.concat(got, ","))
end

function T:test_reader_close_is_idempotent_leaves_the_stream_open_and_works_with_close()
  run(function()
    local stream = fake_stream({ "abc" })
    do
      local reader <close> = net.BufferedReader(stream)
      reader:read_some()
    end
    self:assert_false(stream.closed)
    local reader = net.BufferedReader(stream)
    reader:close(); reader:close()
    self:assert_true(reader:is_closed())
    -- A read after close is an error, not a clean end of stream.
    self:assert_true(core.is_instance_of(self:assert_error(function() reader:read_some() end), core.Error))
  end)
end

function T:test_read_exact_limit_and_per_call_limit_validation()
  run(function()
    local reader = net.BufferedReader(fake_stream({ "abcdef" }))
    local err = self:assert_error(function() reader:read_exact(1 << 30, 1024) end)
    self:assert_true(core.is_instance_of(err, core.ProtocolError), tostring(err))
    self:assert_equal("abc", reader:read_exact(3, 1024)) -- nothing was consumed by the refusal
    for _, bad in ipairs({ 0, -1, 1.5, "x" }) do
      self:assert_true(core.is_instance_of(
        self:assert_error(function() reader:read_until("\n", bad) end), core.ArgumentError))
    end
  end)
end

function T:test_many_chunks_and_small_reads_reassemble()
  run(function()
    local chunks, expected = {}, {}
    for i = 1, 300 do
      chunks[i] = ("line %d\r\n"):format(i)
      expected[i] = ("line %d"):format(i)
    end
    -- Re-cut the same bytes at odd boundaries, splitting the CRLF pairs.
    local all = table.concat(chunks)
    local cut = {}
    for pos = 1, #all, 7 do cut[#cut + 1] = all:sub(pos, pos + 6) end
    local reader = net.BufferedReader(fake_stream(cut))
    for i = 1, 300 do self:assert_equal(expected[i], reader:read_line()) end
    self:assert_nil(reader:read_line())
  end)
end

function T:test_invalid_arguments_raise_argument_errors()
  run(function()
    local reader = net.BufferedReader(fake_stream({}))
    self:assert_true(core.is_instance_of(self:assert_error(function() reader:read_exact(-1) end), core.ArgumentError))
    self:assert_true(core.is_instance_of(self:assert_error(function() reader:read_until("") end), core.ArgumentError))
    self:assert_true(core.is_instance_of(self:assert_error(function() net.BufferedReader(42) end), core.ArgumentError))
    self:assert_true(core.is_instance_of(
      self:assert_error(function() net.BufferedReader(fake_stream({}), { limit = 0 }) end), core.ArgumentError))
  end)
end

function T:test_suspending_reads_require_a_managed_coroutine()
  local reader = net.BufferedReader(fake_stream({ "a\n" }))
  local err = self:assert_error(function() reader:read_line() end)
  self:assert_true(core.is_instance_of(err, core.NonYieldableContextError))
end

function T:test_writer_coalesces_until_flush_or_capacity()
  run(function()
    local stream = fake_stream({})
    local writer = net.BufferedWriter(stream, { capacity = 8 })
    writer:write("abc"); writer:write("de")
    self:assert_equal(0, #stream.sent)
    self:assert_equal(5, writer:buffered())
    writer:write("fgh") -- reaches capacity
    self:assert_equal("abcdefgh", table.concat(stream.sent))
    self:assert_equal(1, #stream.sent)
    writer:write("x")
    writer:flush()
    writer:flush() -- nothing left
    self:assert_equal(2, #stream.sent)
    self:assert_equal(0, writer:buffered())
  end)
end

function T:test_failed_flush_poisons_the_writer_so_no_partial_write_leaks()
  run(function()
    local stream = fake_stream({})
    local writer = net.BufferedWriter(stream)
    local boom = core.NetworkError("broken pipe")
    stream.write_failure = boom
    writer:write("abc")
    self:assert_equal(boom, self:assert_error(function() writer:flush() end))
    stream.write_failure = nil
    self:assert_equal(boom, self:assert_error(function() writer:write("def") end))
    self:assert_equal(boom, self:assert_error(function() writer:flush() end))
    self:assert_equal(0, #stream.sent)
  end)
end

function T:test_close_discards_unflushed_bytes_and_keeps_the_stream_open()
  run(function()
    local stream = fake_stream({})
    do
      local writer <close> = net.BufferedWriter(stream)
      writer:write("lost")
    end
    self:assert_equal(0, #stream.sent)
    self:assert_false(stream.closed)
    local writer = net.BufferedWriter(stream)
    writer:close(); writer:close()
    self:assert_error(function() writer:write("x") end)
  end)
end

function T:test_concurrent_flushes_keep_byte_order()
  run(function()
    local stream = fake_stream({})
    function stream:write(data)
      reactor.sleep(0.01)
      self.sent[#self.sent + 1] = data
    end
    local writer = net.BufferedWriter(stream, { capacity = 2 })
    reactor.scope(function(scope)
      scope:fork(function() writer:write("aa") end)
      scope:fork(function() writer:write("bb") end)
    end)
    self:assert_equal("aabb", table.concat(stream.sent))
  end)
end

function T:test_write_rejects_non_strings()
  run(function()
    local writer = net.BufferedWriter(fake_stream({}))
    self:assert_true(core.is_instance_of(self:assert_error(function() writer:write(1) end), core.ArgumentError))
  end)
end

return T
