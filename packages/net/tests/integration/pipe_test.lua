---@diagnostic disable: param-type-mismatch  -- the tests pass invalid arguments on purpose
local test = require("harness.test")
local core = require("hecate.core")
local reactor = require("hecate.reactor")
local net = require("hecate.net")
local T = test.Case("NetPipeTest")

local IS_WINDOWS = package.config:sub(1, 1) == "\\"

-- Socket names must not collide between runs, processes or parallel test files: process-unique
-- (the address of a fresh table), a counter, the time and a random part. The file is removed.
local counter = 0
local function pipe_path()
  counter = counter + 1
  local unique = tostring({}):match("0x(%x+)") or "0"
  local name = ("hn%x-%s-%d-%d"):format(os.time(), unique, counter, math.random(0, 1 << 30))
  if IS_WINDOWS then return "\\\\.\\pipe\\" .. name end
  return (os.getenv("TMPDIR") or "/tmp") .. "/" .. name .. ".sock"
end

--- Removes the socket file a Unix listener leaves behind (named pipes on Windows vanish by themselves).
local function remove(path)
  if not IS_WINDOWS then os.remove(path) end
end

local function transport_error(self, fn)
  local err = self:assert_error(fn)
  self:assert_true(core.is_instance_of(err, reactor.TransportError), tostring(err))
  return err
end

function T:test_buffered_lines_over_a_pipe()
  local before = reactor.Reactor.open_handles()
  local path = pipe_path()
  local line = reactor.run(function()
    local listener <close> = net.listen_pipe(path)
    self:assert_equal(path, listener:path())
    reactor.fork(function()
      local peer <close> = listener:accept()
      local writer = peer:writer()
      writer:write("hello\nworld\n")
      writer:flush()
      peer:shutdown()
    end)
    local client <close> = net.connect_pipe(path)
    local reader = client:reader()
    local first = reader:read_line()
    local second = reader:read_line()
    -- Wait for the end of stream: macOS reports ENOTCONN when the peer shuts down after we closed.
    self:assert_nil(reader:read_line())
    return first .. "|" .. second
  end)
  remove(path)
  self:assert_equal("hello|world", line)
  self:assert_equal(before, reactor.Reactor.open_handles())
end

function T:test_connecting_to_a_missing_path_raises_enoent_and_leaks_nothing()
  local before = reactor.Reactor.open_handles()
  local path = pipe_path()
  reactor.run(function()
    local err = transport_error(self, function() net.connect_pipe(path) end)
    -- ENOENT on Unix; a missing named pipe is ENOENT on Windows too.
    self:assert_equal("ENOENT", err.context.errno)
  end)
  self:assert_equal(before, reactor.Reactor.open_handles())
end

function T:test_listening_on_an_existing_path_fails_and_leaks_nothing()
  local before = reactor.Reactor.open_handles()
  local path = pipe_path()
  reactor.run(function()
    local first <close> = net.listen_pipe(path)
    local err = transport_error(self, function() net.listen_pipe(path) end)
    -- A bound name is EADDRINUSE; Windows may report the exclusive first instance as EACCES.
    self:assert_true(err.context.errno == "EADDRINUSE" or (IS_WINDOWS and err.context.errno == "EACCES"),
      tostring(err.context.errno))
    self:assert_false(first:is_closed())
  end)
  remove(path)
  self:assert_equal(before, reactor.Reactor.open_handles())
end

function T:test_a_malformed_path_or_option_raises_an_argument_error()
  reactor.run(function()
    local cases = {
      function() net.listen_pipe(42) end,
      function() net.listen_pipe("") end,
      function() net.listen_pipe(pipe_path(), "x") end,
      function() net.listen_pipe(pipe_path(), { backlog = 0 }) end,
      function() net.listen_pipe(pipe_path(), { backlog = 1.5 }) end,
      function() net.listen_pipe(pipe_path(), { backlogs = 8 }) end,
      function() net.connect_pipe(42) end,
      function() net.connect_pipe("") end,
    }
    for index, call in ipairs(cases) do
      local err = self:assert_error(call)
      self:assert_true(core.is_instance_of(err, core.ArgumentError), index .. ": " .. tostring(err))
    end
  end)
end

function T:test_a_backlog_is_accepted()
  local path = pipe_path()
  reactor.run(function()
    local listener <close> = net.listen_pipe(path, { backlog = 4 })
    self:assert_equal(path, listener:path())
  end)
  remove(path)
end

function T:test_a_cancelled_accept_keeps_the_listener_and_the_queued_connections()
  local before = reactor.Reactor.open_handles()
  local path = pipe_path()
  reactor.run(function()
    local listener <close> = net.listen_pipe(path)
    local ok, err = pcall(reactor.deadline, 0.02, function() return listener:accept() end)
    self:assert_false(ok)
    self:assert_true(core.is_instance_of(err, core.DeadlineExceededError), tostring(err))
    self:assert_false(listener:is_closed())
    -- A connection that arrives after the cancellation is still accepted.
    local client <close> = net.connect_pipe(path)
    client:write("late")
    local peer <close> = listener:accept()
    self:assert_equal("late", peer:read())
  end)
  remove(path)
  self:assert_equal(before, reactor.Reactor.open_handles())
end

function T:test_listeners_and_streams_close_idempotently_and_with_a_close_scope()
  local before = reactor.Reactor.open_handles()
  local path = pipe_path()
  reactor.run(function()
    local listener, stream
    do
      local scoped_listener <close> = net.listen_pipe(path)
      listener = scoped_listener
      self:assert_false(listener:is_closed())
      reactor.fork(function() local peer <close> = listener:accept(); peer:read() end)
      local scoped_stream <close> = net.connect_pipe(path)
      stream = scoped_stream
      self:assert_false(stream:is_closed())
      self:assert_equal(path, stream:path())
    end
    self:assert_true(listener:is_closed())
    self:assert_true(stream:is_closed())
    listener:close()
    stream:close()
    local err = transport_error(self, function() stream:write("x") end)
    self:assert_equal("EBADF", err.context.errno)
  end)
  remove(path)
  self:assert_equal(before, reactor.Reactor.open_handles())
end

function T:test_a_closed_listener_wakes_a_pending_accept()
  local path = pipe_path()
  reactor.run(function()
    local listener = net.listen_pipe(path)
    local parked = reactor.Channel(1)
    local acceptor = reactor.fork(function()
      parked:send(true) -- cooperative scheduling: the closer runs only once this coroutine parked in `accept`
      return pcall(listener.accept, listener)
    end)
    parked:receive()
    listener:close()
    local ok, err = acceptor:value()
    self:assert_false(ok)
    self:assert_equal("ECANCELED", err.context.errno)
  end)
  remove(path)
end

function T:test_fifty_concurrent_connections_each_get_their_own_answer()
  local before = reactor.Reactor.open_handles()
  local path = pipe_path()
  local total = reactor.run(function()
    local listener <close> = net.listen_pipe(path, { backlog = 64 })
    reactor.fork(function()
      for _ = 1, 50 do
        local peer = listener:accept()
        reactor.fork(function()
          local stream <close> = peer
          local reader, writer = stream:reader(), stream:writer()
          writer:write(reader:read_line() .. "\n")
          writer:flush()
        end)
      end
    end)
    local futures = {}
    for i = 1, 50 do
      futures[i] = reactor.fork(function()
        local client <close> = net.connect_pipe(path)
        local reader, writer = client:reader(), client:writer()
        writer:write(i .. "\n")
        writer:flush()
        return tonumber(reader:read_line())
      end)
    end
    local sum = 0
    for i = 1, 50 do sum = sum + futures[i]:value() end
    return sum
  end)
  remove(path)
  self:assert_equal(1275, total)
  self:assert_equal(before, reactor.Reactor.open_handles())
end

return T
