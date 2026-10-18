---@diagnostic disable: param-type-mismatch  -- the tests pass invalid arguments on purpose
-- Public surface of `hecate.net` that needs no I/O: exports, the `<close>` protocol of every
-- stream class, and argument checks that must fire before anything is resolved or connected.
local test = require("harness.test")
local core = require("hecate.core")
local reactor = require("hecate.reactor")
local net = require("hecate.net")
local T = test.Case("NetApiTest")

-- Invariant (net/CLAUDE.md): every stream is `<close>`-able. Generic over the classes, so a new
-- stream class that forgets `__close`, `close` or `is_closed` is caught here.
function T:test_every_stream_class_defines_close_dunder_close_and_is_closed()
  local classes = {
    TcpStream = net.TcpStream, PipeStream = net.PipeStream, TlsStream = net.TlsStream,
    TcpListener = net.TcpListener, PipeListener = net.PipeListener, UdpSocket = net.UdpSocket,
    BufferedReader = net.BufferedReader, BufferedWriter = net.BufferedWriter,
  }
  for name, class in pairs(classes) do
    for _, method in ipairs({ "close", "__close", "is_closed" }) do
      self:assert_equal("function", type(class[method]), name .. "." .. method)
    end
  end
end

function T:test_transport_error_is_the_reactor_class_and_the_error_types_are_exported()
  self:assert_true(net.TransportError == reactor.TransportError)
  self:assert_true(core.is_instance_of(net.TransportError({ message = "x" }), core.NetworkError))
  self:assert_true(core.is_instance_of(net.EndOfStreamError({ message = "x", context = { buffered = 0 } }), core.NetworkError))
  self:assert_true(core.is_instance_of(net.TlsError({ message = "x" }), core.NetworkError))
end

function T:test_stream_wrappers_return_nothing_from_write_and_shutdown()
  local calls = {}
  local inner = {
    write = function(_, data) calls[#calls + 1] = data return "leak" end,
    shutdown = function() return "leak" end,
    read = function() return nil end,
    close = function() end,
    is_closed = function() return false end,
  }
  for _, class in ipairs({ net.TcpStream, net.PipeStream }) do
    local stream = class(inner)
    self:assert_equal(0, select("#", stream:write("x")))
    self:assert_equal(0, select("#", stream:shutdown()))
  end
  local socket = net.UdpSocket({ send_to = function() return "leak" end })
  self:assert_equal(0, select("#", socket:send_to("127.0.0.1", 9, "x")))
end

function T:test_read_validates_max_the_same_way_for_tcp_and_pipe_streams()
  local inner = { read = function() return "x" end, close = function() end }
  for _, class in ipairs({ net.TcpStream, net.PipeStream }) do
    local stream = class(inner)
    for _, bad in ipairs({ 0, -1, 1.5, "8" }) do
      local err = self:assert_error(function() stream:read(bad) end)
      self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
      self:assert_true(tostring(err):find("read expects a positive integer, got", 1, true) ~= nil, tostring(err))
    end
    self:assert_equal("x", stream:read(1))
  end
end

function T:test_pipe_streams_forward_path()
  local stream = net.PipeStream({ path = function() return "/tmp/x.sock" end })
  self:assert_equal("/tmp/x.sock", stream:path())
end

function T:test_connect_and_listen_check_arguments_before_resolving_anything()
  -- Not inside a reactor: reaching the resolver would raise NonYieldableContextError instead.
  for _, call in ipairs({
    function() net.connect("example.org", 80, { nodelay = 1 }) end,
    function() net.connect("example.org", 80, { colour = "red" }) end,
    function() net.connect("example.org", 80, { backlog = 3 }) end,
    function() net.connect("example.org", 80, { keepalive_delay = -1 }) end,
    function() net.listen("example.org", 80, { reuseport = 1 }) end,
    function() net.listen("example.org", 80, { family = "ipx" }) end,
    function() net.listen("", 80) end,
    function() net.connect("example.org", 99999) end,
  }) do
    local err = self:assert_error(call)
    self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
  end
end

function T:test_each_ergonomics_error_names_the_net_function()
  local err = self:assert_error(function() net.connect("example.org", 80, { nodelay = 1 }) end)
  self:assert_true(tostring(err):find("connect: option nodelay must be a boolean", 1, true) ~= nil, tostring(err))
  err = self:assert_error(function() net.listen("example.org", 80, { colour = "red" }) end)
  self:assert_true(tostring(err):find("listen: unknown option colour (options: ", 1, true) ~= nil, tostring(err))
end

return T
