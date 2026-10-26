-- Message pipe (`reactor.ipc`): framing, failure paths and hand-over, tested in one process over
-- a connected pair of Unix-domain sockets, plus the framing alone over a scripted stream. The pair
-- needs descriptors libuv can pass handles over: Windows is covered by process_test.lua only.
local test = require("harness.test")
local core = require("hecate.core")
local uv = require("luv")
local reactor = require("hecate.reactor")
local T = test.Case("IpcTest")

local HEADER = ">I4B"
local is_windows = package.config:sub(1, 1) == "\\"

--- A connected pair of peers in this process.
---@return hecate.reactor.Peer a
---@return hecate.reactor.Peer b
local function peer_pair(options)
  local pair = assert(uv.socketpair("stream", 0, { nonblock = true }, { nonblock = true }))
  local a, b = uv.new_pipe(true), uv.new_pipe(true)
  assert(a:open(pair[1]))
  assert(b:open(pair[2]))
  return reactor.Peer(a, options), reactor.Peer(b, options)
end

--- Runs `fn(a, b)` on a reactor with a connected pair and checks that no libuv handle is left.
local function with_pair(self, fn, options)
  if is_windows then
    print("SKIP " .. self.name .. ": in-process pipe pair needs Unix-domain sockets")
    return
  end
  local before = reactor.Reactor.open_handles()
  local result = reactor.run(function()
    local a, b = peer_pair(options)
    local ok, value = pcall(fn, a, b)
    a:close()
    b:close()
    if not ok then error(value, 0) end
    return value
  end)
  self:assert_equal(before, reactor.Reactor.open_handles())
  return result
end

---@diagnostic disable: invisible  -- the tests write raw bytes through the stream of the peer

--- Writes raw bytes on the pipe of `peer`.
local function raw(peer, bytes) peer._stream:write(bytes) end

--- Writes raw bytes and hands a fresh bound TCP handle over with them.
local function raw_with_handle(peer, bytes)
  local handle = uv.new_tcp()
  assert(handle:bind("127.0.0.1", 0))
  peer._stream:_await("send", function(callback) return peer._handle:write2(bytes, handle, callback) end)
  handle:close()
end

local function frame(message, flag) return string.pack(HEADER, #message, flag or 0) .. message end

local function errno_of(self, fn)
  local err = self:assert_error(fn)
  self:assert_true(core.is_instance_of(err, reactor.TransportError), tostring(err))
  return err.context.errno, err
end

function T:test_end_of_the_pipe_inside_a_header_is_an_error()
  with_pair(self, function(a, b)
    raw(a, frame("hello"):sub(1, 3))
    a:close()
    self:assert_equal("EPIPE", errno_of(self, function() b:receive() end))
  end)
end

function T:test_end_of_the_pipe_inside_a_body_is_an_error()
  with_pair(self, function(a, b)
    raw(a, frame("hello world"):sub(1, 9))
    a:close()
    self:assert_equal("EPIPE", errno_of(self, function() b:receive() end))
  end)
end

function T:test_a_clean_end_of_the_pipe_gives_nil_and_buffered_messages_are_kept()
  with_pair(self, function(a, b)
    a:send("last")
    a:close()
    self:assert_equal("last", b:receive())
    self:assert_nil(b:receive())
    self:assert_nil(b:receive()) -- stays at the end
  end)
end

function T:test_a_malformed_frame_is_refused_and_closes_the_peer()
  for name, bytes in pairs({
    flag = string.pack(HEADER, 1, 7) .. "x",
    length = string.pack(HEADER, 0x7fffffff, 0),
  }) do
    with_pair(self, function(a, b)
      raw(a, bytes)
      self:assert_equal("EPROTO", errno_of(self, function() b:receive() end), name)
      self:assert_true(b:is_closed(), name)
    end)
  end
end

function T:test_a_frame_that_announces_a_stream_without_one_is_refused()
  with_pair(self, function(a, b)
    raw(a, frame("x", 1))
    self:assert_equal("EPROTO", errno_of(self, function() b:receive() end))
    self:assert_true(b:is_closed())
  end)
end

function T:test_a_stream_attached_to_a_frame_that_announces_none_is_refused()
  with_pair(self, function(a, b)
    raw_with_handle(a, frame("plain"))
    self:assert_equal("EPROTO", errno_of(self, function() b:receive() end))
    self:assert_true(b:is_closed()) -- closing releases the stream that waited in libuv
  end)
end

function T:test_two_streams_attached_to_one_frame_are_refused()
  with_pair(self, function(a, b)
    local whole = frame("split", 1)
    raw_with_handle(a, whole:sub(1, 4))
    raw_with_handle(a, whole:sub(5))
    self:assert_equal("EPROTO", errno_of(self, function() b:receive() end))
    self:assert_true(b:is_closed())
  end)
end

function T:test_the_stream_of_the_next_frame_may_arrive_with_the_end_of_this_one()
  -- The operating system may deliver a handle together with bytes of an earlier frame: that is
  -- not a violation as long as a following frame announces it.
  with_pair(self, function(a, b)
    local listener <close> = reactor.listen_tcp("127.0.0.1", 0)
    local client <close> = reactor.connect_tcp("127.0.0.1", listener:local_address().port)
    local server = listener:accept()
    -- Both frames are written before anything is read, the second one carrying the handle.
    raw(a, frame("one"))
    a:send("two", server)
    self:assert_equal("one", b:receive())
    local message, handed = b:receive()
    self:assert_equal("two", message)
    handed:write("hi")
    self:assert_equal("hi", client:read())
    handed:close()
  end)
end

function T:test_a_cancelled_receive_keeps_the_peer_open_and_loses_nothing()
  with_pair(self, function(a, b)
    -- Nothing sent: the receive waits for a header and is cancelled.
    local ok, err = pcall(reactor.deadline, 0.02, b.receive, b)
    self:assert_false(ok)
    self:assert_true(core.is_instance_of(err, core.DeadlineExceededError), tostring(err))
    self:assert_false(b:is_closed())
    -- A partial header, cancelled again, then the rest of the frame and one more frame.
    local whole = frame("complete message") .. frame("next")
    raw(a, whole:sub(1, 3))
    ok = pcall(reactor.deadline, 0.02, b.receive, b)
    self:assert_false(ok)
    raw(a, whole:sub(4, 12)) -- header complete, body partial
    ok = pcall(reactor.deadline, 0.02, b.receive, b)
    self:assert_false(ok)
    self:assert_false(b:is_closed())
    raw(a, whole:sub(13))
    self:assert_equal("complete message", b:receive())
    self:assert_equal("next", b:receive())
  end)
end

function T:test_operations_on_a_closed_peer_raise_ebadf_and_closing_wakes_a_pending_receive()
  with_pair(self, function(a, b)
    local waiting = reactor.fork(function() return errno_of(self, function() b:receive() end) end)
    for _ = 1, 2000 do
      if b._receiving then break end
      reactor.sleep(0.001)
    end
    self:assert_true(b._receiving)
    b:close()
    self:assert_equal("ECANCELED", waiting:value())
    self:assert_equal("EBADF", errno_of(self, function() b:receive() end))
    self:assert_equal("EBADF", errno_of(self, function() b:send("x") end))
    self:assert_equal("EBADF", errno_of(self, function() a:close(); a:send("x") end))
  end)
end

function T:test_sending_to_a_peer_that_went_away_fails()
  with_pair(self, function(a, b)
    b:close()
    local errno = errno_of(self, function()
      for _ = 1, 2000 do a:send(("x"):rep(65536)); reactor.sleep(0) end
    end)
    -- Platforms report the vanished peer differently.
    self:assert_true(errno == "EPIPE" or errno == "ECONNRESET" or errno == "ECANCELED", tostring(errno))
  end)
end

function T:test_close_is_idempotent_and_closes_at_the_end_of_a_scope()
  with_pair(self, function(a, b)
    self:assert_false(a:is_closed())
    a:close()
    a:close()
    self:assert_true(a:is_closed())
    do
      local scoped <close> = b
      self:assert_false(scoped:is_closed())
    end
    self:assert_true(b:is_closed())
  end)
end

function T:test_many_streams_handed_over_in_a_row_stay_matched_with_their_messages()
  with_pair(self, function(a, b)
    local listener <close> = reactor.listen_tcp("127.0.0.1", 0, { backlog = 64 })
    local port = listener:local_address().port
    local count = 30
    local clients = {}
    for index = 1, count do
      clients[index] = reactor.connect_tcp("127.0.0.1", port)
      local server = listener:accept()
      if index % 3 == 0 then a:send("plain" .. index) end
      a:send("m" .. index, server)
    end
    for index = 1, count do
      if index % 3 == 0 then self:assert_equal("plain" .. index, (b:receive())) end
      local message, stream = b:receive()
      self:assert_equal("m" .. index, message)
      stream:write(message)
      stream:close()
    end
    for index = 1, count do
      self:assert_equal("m" .. index, clients[index]:read())
      clients[index]:close()
    end
  end)
end

function T:test_max_message_bounds_what_is_sent_and_received()
  with_pair(self, function(a, b)
    local err = self:assert_error(function() a:send(("x"):rep(11)) end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
    a:send(("x"):rep(10))
    self:assert_equal(("x"):rep(10), b:receive())
    raw(a, frame(("y"):rep(11))) -- a sender with a larger limit
    self:assert_equal("EPROTO", errno_of(self, function() b:receive() end))
  end, { max_message = 10 })
end

function T:test_peer_options_are_validated()
  local handle = uv.new_pipe(true)
  for _, options in ipairs({ { max_message = -1 }, { max_message = 1.5 }, { max_message = 2 ^ 33 }, { nope = 1 }, "x" }) do
    local err = self:assert_error(function() reactor.Peer(handle, options) end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
  end
  ---@diagnostic disable-next-line: assign-type-mismatch  -- the point is to pass a wrong type
  local err = self:assert_error(function() reactor.ipc.parent({ max_message = "big" }) end)
  self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
  self:assert_nil(reactor.ipc.parent({ max_message = 1 })) -- this process has no parent
  handle:close()
end

--- A stream that delivers `bytes` in chunks of the given sizes and then ends, with a handle that
--- behaves like libuv's: a stream is pending once the first byte of a frame that carries one was
--- delivered.
local function scripted(bytes, sizes, announces)
  local offset, chunk_index, pending = 1, 0, 0
  local stream = { _closed = false }
  function stream:read()
    if offset > #bytes then return nil end
    chunk_index = chunk_index + 1
    local size = sizes[(chunk_index - 1) % #sizes + 1]
    local from, to = offset, math.min(#bytes, offset + size - 1)
    offset = to + 1
    for _, start in ipairs(announces) do
      if start >= from and start <= to then pending = pending + 1 end
    end
    return bytes:sub(from, to)
  end
  function stream:close() self._closed = true end
  function stream:is_closed() return self._closed end
  local handle = {}
  function handle:pending_count() return pending end
  function handle:pending_type() return pending > 0 and "tcp" or nil end
  function handle:accept(client) pending = pending - 1; return true end
  return stream, handle
end

function T:test_framing_survives_any_chunking_of_the_byte_stream()
  local seed = os.time()
  math.randomseed(seed)
  local sizes_to_try = { { 1 }, { 2 }, { 3 }, { 5 }, { 7, 1, 13 }, { 64 }, { 1024 }, { 100000 } }
  for _ = 1, 40 do -- random chunk size lists
    local list = {}
    for index = 1, math.random(1, 6) do list[index] = math.random(1, 40) end
    sizes_to_try[#sizes_to_try + 1] = list
  end
  -- A random sequence of frames, some carrying a stream, some empty, some large.
  local messages, flags, bytes, announces = {}, {}, {}, {}
  local position = 1
  for index = 1, 40 do
    local length = ({ 0, 1, 5, 100, 4000 })[math.random(1, 5)]
    local message = string.char(65 + index % 26):rep(length)
    local flag = math.random(0, 1)
    messages[index], flags[index] = message, flag
    local piece = frame(message, flag)
    if flag == 1 then announces[#announces + 1] = position end
    bytes[index] = piece
    position = position + #piece
  end
  local all = table.concat(bytes)
  for _, sizes in ipairs(sizes_to_try) do
    local stream, handle = scripted(all, sizes, announces)
    local peer = reactor.Peer(handle, nil, stream)
    for index = 1, #messages do
      local message, stream_received = peer:receive()
      local context = ("seed %d, chunks %s, frame %d"):format(seed, table.concat(sizes, ","), index)
      self:assert_equal(messages[index], message, context)
      self:assert_equal(flags[index] == 1, stream_received ~= nil, context)
      if stream_received then stream_received:close() end
    end
    self:assert_nil(peer:receive())
  end
end

return T
