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
    self:assert_true(core.is_instance_of(self:assert_error(function() reader:read_some() end), reactor.TransportError))
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
      self:assert_true(core.is_instance_of(
        self:assert_error(function() reader:read_some(bad) end), core.ArgumentError))
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
    local later = self:assert_error(function() writer:write("def") end)
    self:assert_true(core.is_instance_of(later, core.NetworkError))
    self:assert_true(later ~= boom) -- a fresh error: the original may be a cancellation
    self:assert_equal(boom, later.cause)
    self:assert_true(core.is_instance_of(self:assert_error(function() writer:flush() end), core.NetworkError))
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
    self:assert_true(core.is_instance_of(self:assert_error(function() writer:write("x") end), reactor.TransportError))
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

-- Regression (found by the property test below): a record exactly at the limit, followed by a
-- multi-byte delimiter whose first byte arrives before the rest, is not too long.
function T:test_a_record_at_the_limit_with_a_split_multi_byte_delimiter_is_accepted()
  run(function()
    local reader = net.BufferedReader(fake_stream({ "abcdefg\r", "\nrest" }), { limit = 7 })
    self:assert_equal("abcdefg", reader:read_until("\r\n"))
    -- One byte more is too long, wherever the chunks end.
    local longer = net.BufferedReader(fake_stream({ "abcdefgh\r", "\n" }), { limit = 7 })
    self:assert_true(core.is_instance_of(self:assert_error(function() longer:read_until("\r\n") end), core.ProtocolError))
    local whole = net.BufferedReader(fake_stream({ "abcdefgh\r\n" }), { limit = 7 })
    self:assert_true(core.is_instance_of(self:assert_error(function() whole:read_until("\r\n") end), core.ProtocolError))
  end)
end

--- Splits `payload` into chunks of random sizes (at least one byte each).
local function split(payload, random)
  local chunks, pos = {}, 1
  while pos <= #payload do
    local size = random(1, 9)
    chunks[#chunks + 1] = payload:sub(pos, pos + size - 1)
    pos = pos + size
  end
  return chunks
end

--- Runs `ops` on a reader and returns a printable trace: a result, or the error kind (an end of
--- stream with the bytes it kept, a protocol error that stops the run).
local function trace(self, chunks, ops, limit)
  local reader = net.BufferedReader(fake_stream(chunks), { limit = limit })
  local out = {}
  for _, op in ipairs(ops) do
    local ok, result = pcall(function()
      if op.kind == "line" then return reader:read_line() end
      if op.kind == "until" then return reader:read_until(op.delimiter) end
      return reader:read_exact(op.count)
    end)
    if ok then
      out[#out + 1] = result == nil and "nil" or ("%q"):format(result)
    elseif core.is_instance_of(result, net.EndOfStreamError) then
      out[#out + 1] = "end:" .. tostring(result.context.buffered)
    elseif core.is_instance_of(result, core.ProtocolError) then
      out[#out + 1] = "protocol"
      break -- what stays buffered after this depends on how the bytes arrived
    else
      self:fail(tostring(result))
    end
  end
  return table.concat(out, ",")
end

-- Property: however the received bytes are split into chunks, a sequence of line, delimiter and
-- exact-length reads gives the same results, errors included, as when they arrive at once.
function T:test_results_do_not_depend_on_how_the_bytes_are_chunked()
  local random = math.random
  math.randomseed(20261018)
  local alphabet = { "a", "b", "\r", "\n", "-", "\n", "x" }
  local delimiters = { "\n", "\r\n", "--" }
  run(function()
    for _ = 1, 250 do
      local bytes = {}
      for k = 1, random(0, 120) do bytes[k] = alphabet[random(#alphabet)] end
      local payload = table.concat(bytes)
      local ops = {}
      for k = 1, random(1, 12) do
        local roll = random(3)
        if roll == 1 then ops[k] = { kind = "line" }
        elseif roll == 2 then ops[k] = { kind = "until", delimiter = delimiters[random(#delimiters)] }
        else ops[k] = { kind = "exact", count = random(0, 20) } end
      end
      local limit = random(1, 3) == 1 and random(2, 12) or nil
      local whole = trace(self, { payload }, ops, limit)
      if payload == "" then whole = trace(self, {}, ops, limit) end
      local pieces = trace(self, split(payload, random), ops, limit)
      self:assert_equal(whole, pieces, ("payload %q"):format(payload))
    end
  end)
end

-- Property: `read_some` over any chunking returns every byte once, in order.
function T:test_read_some_returns_every_byte_once_in_order()
  local random = math.random
  math.randomseed(20261019)
  run(function()
    for _ = 1, 100 do
      local bytes = {}
      for k = 1, random(0, 200) do bytes[k] = string.char(random(0, 255)) end
      local payload = table.concat(bytes)
      local reader = net.BufferedReader(fake_stream(split(payload, random)))
      local got = {}
      while true do
        local part = reader:read_some(random(1, 7))
        if part == nil then break end
        got[#got + 1] = part
      end
      self:assert_true(table.concat(got) == payload, "bytes lost, duplicated or reordered")
    end
  end)
end
-- Owner decision: a closed reader or writer raises what a closed TcpStream raises, a
-- `reactor.TransportError` with errno EBADF, and `context.operation` names the method.
function T:test_closed_readers_and_writers_raise_a_transport_error_with_ebadf_and_a_stable_operation()
  run(function()
    local reader = net.BufferedReader(fake_stream({ "abc\n" }))
    reader:close()
    local writer = net.BufferedWriter(fake_stream({}))
    writer:close()
    local cases = {
      { "read_line", function() reader:read_line() end },
      { "read_until", function() reader:read_until("\n") end },
      { "read_exact", function() reader:read_exact(1) end },
      { "read_some", function() reader:read_some() end },
      { "write", function() writer:write("x") end },
      { "flush", function() writer:flush() end },
    }
    for _, case in ipairs(cases) do
      local err = self:assert_error(case[2])
      self:assert_true(core.is_instance_of(err, reactor.TransportError), case[1] .. ": " .. tostring(err))
      self:assert_true(core.is_instance_of(err, core.NetworkError), case[1])
      self:assert_equal("EBADF", err.context.errno, case[1])
      self:assert_equal(case[1], err.context.operation)
    end
  end)
end

function T:test_reader_and_writer_options_are_checked()
  run(function()
    local stream = fake_stream({})
    local function refused(fn, pattern)
      local err = self:assert_error(fn)
      self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
      if pattern then self:assert_true(tostring(err):find(pattern, 1, true) ~= nil, tostring(err)) end
    end
    refused(function() net.BufferedReader(stream, "x") end, "options table")
    refused(function() net.BufferedReader(stream, { limits = 5 }) end, "unknown option limits")
    refused(function() net.BufferedReader(stream, { limit = false }) end, "invalid limit")
    refused(function() net.BufferedWriter(stream, 8) end, "options table")
    refused(function() net.BufferedWriter(stream, { capacit = 5 }) end, "unknown option capacit")
    refused(function() net.BufferedWriter(stream, { capacity = false }) end, "invalid capacity")
    refused(function() net.BufferedWriter(stream, { capacity = 0 }) end, "invalid capacity")
    net.BufferedReader(stream, {})
    net.BufferedWriter(stream, {})
  end)
end

-- A delimiter found after many chunks: the search resumes in the new chunk plus the tail, so a
-- delimiter straddling any number of one-byte chunks, or none, is found where it is.
function T:test_read_until_finds_delimiters_across_one_byte_chunks_and_after_consumed_bytes()
  run(function()
    local payload = "ab--cd----e--"
    local chunks = {}
    for k = 1, #payload do chunks[k] = payload:sub(k, k) end
    local reader = net.BufferedReader(fake_stream(chunks))
    self:assert_equal("ab", reader:read_until("--"))
    self:assert_equal("cd", reader:read_until("--"))
    self:assert_equal("", reader:read_until("--"))
    self:assert_equal("e", reader:read_until("--"))
    self:assert_nil(reader:read_until("--"))
    -- A tail shorter than the delimiter must not reach into bytes that were already consumed.
    local second = net.BufferedReader(fake_stream({ "xxabc-", "-yy" }))
    self:assert_equal("xx", second:read_exact(2))
    self:assert_equal("abc", second:read_until("--"))
    self:assert_equal("yy", second:read_some())
  end)
end

function T:test_a_large_record_in_many_chunks_is_read_whole()
  run(function()
    local record = string.rep("0123456789abcdef", 16 * 1024) -- 256 KiB
    local chunks = {}
    for pos = 1, #record, 1000 do chunks[#chunks + 1] = record:sub(pos, pos + 999) end
    chunks[#chunks + 1] = "\r\nnext"
    local reader = net.BufferedReader(fake_stream(chunks), { limit = #record + 1 }) -- the carriage return counts
    self:assert_true(reader:read_line() == record)
    self:assert_equal(4, reader:buffered())
  end)
end

function T:test_a_cancelled_read_until_resumes_from_what_it_received()
  run(function()
    local stream = fake_stream({})
    local script = { "par", "tial-", "-end", "-" }
    local index = 0
    function stream:read()
      index = index + 1
      if index == 3 then reactor.sleep(10) end -- parked here when the deadline cancels the read
      return script[index > 3 and index - 1 or index]
    end
    local reader = net.BufferedReader(stream)
    local ok, err = pcall(reactor.deadline, 0.01, reader.read_until, reader, "--")
    self:assert_false(ok)
    self:assert_true(core.is_instance_of(err, core.DeadlineExceededError))
    self:assert_equal(8, reader:buffered()) -- "partial-"
    -- The delimiter straddles the cancelled chunk boundary and the next one.
    self:assert_equal("partial", reader:read_until("--"))
  end)
end

-- A payload of at least `capacity` bytes, with nothing buffered, is written in one call (the direct
-- path skips the copy through the buffer; what the stream sees, bytes and order, must not change).
function T:test_a_large_write_goes_straight_to_the_stream_when_nothing_is_buffered()
  run(function()
    local stream = fake_stream({})
    local writer = net.BufferedWriter(stream, { capacity = 8 })
    local payload = "0123456789"
    writer:write(payload)
    self:assert_equal(1, #stream.sent)
    self:assert_true(stream.sent[1] == payload)
    self:assert_equal(0, writer:buffered())
    -- With bytes already buffered the order is kept: they go out first, with the payload.
    writer:write("ab")
    writer:write(payload)
    self:assert_equal("0123456789ab0123456789", table.concat(stream.sent))
    self:assert_equal(0, writer:buffered())
  end)
end

function T:test_a_failed_direct_write_poisons_the_writer()
  run(function()
    local stream = fake_stream({})
    stream.write_failure = core.NetworkError("reset")
    local writer = net.BufferedWriter(stream, { capacity = 4 })
    local first = self:assert_error(function() writer:write("0123456789") end)
    self:assert_equal(stream.write_failure, first)
    stream.write_failure = nil
    local second = self:assert_error(function() writer:write("x") end)
    self:assert_true(second.cause == first)
    self:assert_equal(0, #stream.sent)
  end)
end

function T:test_a_cancelled_direct_write_poisons_the_writer()
  run(function()
    local stream = fake_stream({})
    function stream:write(data) reactor.sleep(10) self.sent[#self.sent + 1] = data end
    local writer = net.BufferedWriter(stream, { capacity = 4 })
    local ok, err = pcall(reactor.deadline, 0.01, writer.write, writer, "0123456789")
    self:assert_false(ok)
    self:assert_true(core.is_instance_of(err, core.DeadlineExceededError))
    local later = self:assert_error(function() writer:write("x") end)
    self:assert_true(core.is_instance_of(later, core.NetworkError))
    self:assert_not_nil(later.cause)
    self:assert_equal(0, #stream.sent) -- nothing is sent after a gap
  end)
end

function T:test_concurrent_direct_and_buffered_writes_keep_byte_order()
  run(function()
    local stream = fake_stream({})
    function stream:write(data)
      reactor.sleep(0.005)
      self.sent[#self.sent + 1] = data
    end
    local writer = net.BufferedWriter(stream, { capacity = 4 })
    reactor.scope(function(scope)
      scope:fork(function() writer:write("0123456789") end) -- direct: holds the lock while it writes
      scope:fork(function() writer:write("ab") end) -- buffered behind it
    end)
    writer:flush()
    self:assert_equal("0123456789ab", table.concat(stream.sent))
  end)
end

return T
