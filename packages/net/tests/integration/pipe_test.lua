local test = require("harness.test")
local reactor = require("hecate.reactor")
local net = require("hecate.net")
local T = test.Case("NetPipeTest")

local counter = 0
local function pipe_path()
  counter = counter + 1
  local name = ("hecate-net-pipe-%d-%d"):format(os.time(), counter)
  if package.config:sub(1, 1) == "\\" then return "\\\\.\\pipe\\" .. name end
  return (os.getenv("TMPDIR") or "/tmp") .. "/" .. name .. ".sock"
end

function T:test_buffered_lines_over_a_pipe()
  local before = reactor.Reactor.open_handles()
  local line = reactor.run(function()
    local path = pipe_path()
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
  self:assert_equal("hello|world", line)
  self:assert_equal(before, reactor.Reactor.open_handles())
end

return T
