local test = require("harness.test")
local core = require("hecate.core")
local uv = require("luv")
local reactor = require("hecate.reactor")
local pipe = require("hecate.reactor.pipe")
local T = test.Case("PipeTest")

local is_windows = package.config:sub(1, 1) == "\\"
math.randomseed(os.time(), uv.os_getpid())

--- A socket path unique to this process and run (process id, counter, random part); named pipe
--- syntax on Windows. The file is removed by `with_listener` (libuv unlinks it on close, but a
--- failed test must not leave it behind).
local counter = 0
local created = {}
local function pipe_path()
  counter = counter + 1
  local name = ("hp%x-%d-%x"):format(uv.os_getpid(), counter, math.random(0, 0xffffff))
  if is_windows then return "\\\\.\\pipe\\" .. name end
  local path = uv.os_tmpdir() .. "/" .. name .. ".sock"
  created[#created + 1] = path
  return path
end

function T:tear_down()
  for _, path in ipairs(created) do os.remove(path) end
  created = {}
end

local function with_listener(self, fn, options)
  local before = reactor.Reactor.open_handles()
  local result = reactor.run(function()
    local path = pipe_path()
    local listener <close> = reactor.listen_pipe(path, options)
    return fn(listener, path)
  end)
  self:assert_equal(before, reactor.Reactor.open_handles())
  return result
end

local function errno_of(self, fn)
  local err = self:assert_error(fn)
  self:assert_true(core.is_instance_of(err, reactor.TransportError), tostring(err))
  return err.context.errno
end

function T:test_echo_round_trip()
  local reply = with_listener(self, function(listener, path)
    reactor.fork(function()
      local peer <close> = listener:accept()
      peer:write(peer:read():upper())
    end)
    local client <close> = reactor.connect_pipe(path)
    client:write("hello")
    return client:read()
  end)
  self:assert_equal("HELLO", reply)
end

function T:test_shutdown_gives_end_of_stream()
  local result = with_listener(self, function(listener, path)
    reactor.fork(function()
      local peer <close> = listener:accept()
      peer:write("bye")
      peer:shutdown()
    end)
    local client <close> = reactor.connect_pipe(path)
    local first = client:read()
    return { first, client:read() }
  end)
  self:assert_equal("bye", result[1])
  self:assert_nil(result[2])
end

function T:test_listener_reports_its_path()
  with_listener(self, function(listener, path) self:assert_equal(path, listener:path()) end)
end

function T:test_connect_to_missing_path_is_a_transport_error()
  reactor.run(function()
    local err = self:assert_error(function() reactor.connect_pipe(pipe_path()) end)
    self:assert_true(core.is_instance_of(err, reactor.TransportError), tostring(err))
  end)
end

function T:test_malformed_arguments_are_rejected()
  reactor.run(function()
    local err = self:assert_error(function() reactor.listen_pipe("") end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError))
    err = self:assert_error(function() reactor.listen_pipe(pipe_path(), { nope = 1 }) end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError))
  end)
end

function T:test_a_unix_socket_path_longer_than_the_platform_limit_is_refused()
  if package.config:sub(1, 1) == "\\" then return end -- named pipes have no such limit
  reactor.run(function()
    local path = "/tmp/" .. ("x"):rep(200)
    local err = self:assert_error(function() reactor.listen_pipe(path) end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
    err = self:assert_error(function() reactor.connect_pipe(path) end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
  end)
end

function T:test_the_socket_is_restricted_to_its_owner_by_default_and_mode_opens_it()
  if is_windows then return end -- named pipes use the default security; `mode` has no effect
  for _, case in ipairs({
    { options = nil, mode = tonumber("600", 8) },
    { options = { mode = "owner" }, mode = tonumber("600", 8) },
    { options = { mode = "readwrite" }, mode = tonumber("666", 8) },
    { options = { mode = "readable" }, mode = tonumber("444", 8) },
    { options = { mode = "writable" }, mode = tonumber("222", 8) },
  }) do
    with_listener(self, function(_, path)
      local stat = assert(uv.fs_stat(path))
      self:assert_equal(case.mode, stat.mode & tonumber("777", 8), ("mode %o"):format(case.mode))
    end, case.options)
  end
end

function T:test_a_mode_does_not_stop_the_owner_from_connecting()
  local reply = with_listener(self, function(listener, path)
    reactor.fork(function()
      local peer <close> = listener:accept()
      peer:write("hi")
    end)
    local client <close> = reactor.connect_pipe(path)
    return client:read()
  end, { mode = "readwrite" })
  self:assert_equal("hi", reply)
end

function T:test_options_are_validated()
  reactor.run(function()
    for _, options in ipairs({
      { backlog = 0 }, { backlog = -1 }, { backlog = 1.5 }, { backlog = "8" }, { mode = "all" }, { mode = 7 }, { nope = 1 },
    }) do
      local err = self:assert_error(function() reactor.listen_pipe(pipe_path(), options) end)
      self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
    end
    ---@diagnostic disable-next-line: param-type-mismatch  -- the point is to pass a wrong type
    local err = self:assert_error(function() reactor.listen_pipe(pipe_path(), "x") end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError))
  end)
end

function T:test_a_windows_pipe_name_is_limited_to_256_characters()
  pipe._check_path("reactor.listen_pipe", "\\\\.\\pipe\\" .. ("n"):rep(256), true)
  pipe._check_path("reactor.listen_pipe", ("n"):rep(256), true)
  for _, path in ipairs({ "\\\\.\\pipe\\" .. ("n"):rep(257), ("n"):rep(257), "\\\\?\\pipe\\" .. ("n"):rep(300) }) do
    local err = self:assert_error(function() pipe._check_path("reactor.listen_pipe", path, true) end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
    self:assert_true(tostring(err):find("256", 1, true) ~= nil, tostring(err))
  end
end

function T:test_listening_on_a_used_path_raises_eaddrinuse_and_leaks_nothing()
  with_listener(self, function(_, path)
    self:assert_equal("EADDRINUSE", errno_of(self, function() reactor.listen_pipe(path) end))
  end)
  if is_windows then return end
  local path = pipe_path()
  assert(io.open(path, "w")):close() -- an existing file of another kind
  local before = reactor.Reactor.open_handles()
  reactor.run(function()
    self:assert_equal("EADDRINUSE", errno_of(self, function() reactor.listen_pipe(path) end))
  end)
  self:assert_equal(before, reactor.Reactor.open_handles())
end

function T:test_connecting_to_a_missing_path_leaks_no_handle()
  local before = reactor.Reactor.open_handles()
  reactor.run(function()
    local errno = errno_of(self, function() reactor.connect_pipe(pipe_path()) end)
    self:assert_true(errno == "ENOENT" or errno == "ECONNREFUSED", tostring(errno))
  end)
  self:assert_equal(before, reactor.Reactor.open_handles())
end

function T:test_a_cancelled_accept_keeps_the_listener()
  with_listener(self, function(listener, path)
    local ok, err = pcall(reactor.deadline, 0.02, function() return listener:accept() end)
    self:assert_false(ok)
    self:assert_true(core.is_instance_of(err, core.DeadlineExceededError), tostring(err))
    self:assert_false(listener:is_closed())
    local client <close> = reactor.connect_pipe(path)
    local peer <close> = listener:accept()
    client:write("still works")
    self:assert_equal("still works", peer:read())
  end)
end

function T:test_close_and_scope_exit_close_the_streams_and_the_listener()
  local before = reactor.Reactor.open_handles()
  reactor.run(function()
    local path = pipe_path()
    local listener = reactor.listen_pipe(path)
    local acceptor = reactor.fork(function() local peer <close> = listener:accept() return peer:read() end)
    do
      local client <close> = reactor.connect_pipe(path)
      self:assert_false(client:is_closed())
      self:assert_equal(path, client:path())
    end
    self:assert_nil(acceptor:value()) -- the end of the client ended the stream
    self:assert_false(listener:is_closed())
    listener:close()
    listener:close()
    self:assert_true(listener:is_closed())
    self:assert_equal("EBADF", errno_of(self, function() listener:accept() end))
  end)
  self:assert_equal(before, reactor.Reactor.open_handles())
end

function T:test_many_concurrent_connections()
  local count = 50
  local total = with_listener(self, function(listener, path)
    reactor.fork(function()
      for _ = 1, count do
        local peer = listener:accept()
        reactor.fork(function()
          local stream <close> = peer
          stream:write(stream:read())
        end)
      end
    end)
    local futures = {}
    for index = 1, count do
      futures[index] = reactor.fork(function()
        local client <close> = reactor.connect_pipe(path)
        client:write(tostring(index))
        return tonumber(client:read())
      end)
    end
    local sum = 0
    for index = 1, count do sum = sum + futures[index]:value() end
    return sum
  end, { backlog = 64 })
  self:assert_equal(count * (count + 1) // 2, total)
end

return T
