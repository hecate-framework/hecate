local test = require("harness.test")
local core = require("hecate.core")
local reactor = require("hecate.reactor")
local T = test.Case("PipeTest")

--- A socket path unique to this process; named pipe syntax on Windows.
local counter = 0
local function pipe_path()
  counter = counter + 1
  local name = ("hecate-pipe-test-%d-%d"):format(os.time(), counter)
  if package.config:sub(1, 1) == "\\" then return "\\\\.\\pipe\\" .. name end
  local dir = os.getenv("TMPDIR") or "/tmp"
  return dir .. "/" .. name .. ".sock"
end

local function with_listener(self, fn)
  local before = reactor.Reactor.open_handles()
  local result = reactor.run(function()
    local path = pipe_path()
    local listener <close> = reactor.pipe_listen(path)
    return fn(listener, path)
  end)
  self:assert_equal(before, reactor.Reactor.open_handles())
  return result
end

function T:test_echo_round_trip()
  local reply = with_listener(self, function(listener, path)
    reactor.fork(function()
      local peer <close> = listener:accept()
      peer:write(peer:read():upper())
    end)
    local client <close> = reactor.pipe_connect(path)
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
    local client <close> = reactor.pipe_connect(path)
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
    local err = self:assert_error(function() reactor.pipe_connect(pipe_path()) end)
    self:assert_true(core.is_instance_of(err, reactor.TransportError), tostring(err))
  end)
end

function T:test_malformed_arguments_are_rejected()
  reactor.run(function()
    local err = self:assert_error(function() reactor.pipe_listen("") end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError))
    err = self:assert_error(function() reactor.pipe_listen(pipe_path(), { nope = 1 }) end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError))
  end)
end

return T
