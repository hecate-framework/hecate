-- Pipe transport: Unix-domain sockets (named pipes on Windows) over libuv pipe handles. It
-- reuses the stream and listener machinery of `tcp.lua`; only the handle kind, the addresses and
-- the absence of TCP options differ (OQ-28: luv is wrapped once, in the reactor).
global <const> type, error, require, pcall, tostring, pairs, math

local core = require("hecate.core")
local uv = require("luv")
local uv_call = require("hecate.reactor.internal.uv_call")
local context = require("hecate.reactor.internal.context")
local tcp = require("hecate.reactor.tcp")

local DEFAULT_BACKLOG = 128

---@param name string
---@param path any
local function check_path(name, path)
  if type(path) ~= "string" or path == "" then
    error(core.ArgumentError(("%s expects a path string, got %s"):format(name, tostring(path))), 3)
  end
end

---@param name string
---@param options any
---@return table
local function check_options(name, options)
  if options == nil then return {} end
  if type(options) ~= "table" then
    error(core.ArgumentError(("%s expects an options table, got %s"):format(name, type(options))), 3)
  end
  for key in pairs(options) do
    if key ~= "backlog" then error(core.ArgumentError(("%s: unknown option %s"):format(name, tostring(key))), 3) end
  end
  if options.backlog ~= nil and (math.type(options.backlog) ~= "integer" or options.backlog < 1) then
    error(core.ArgumentError(name .. ": option backlog must be a positive integer"), 3)
  end
  return options
end

--- A connected pipe stream; same operations as `hecate.reactor.TcpStream` minus the TCP options.
---@class hecate.reactor.PipeStream: hecate.reactor.TcpStream
---@overload fun(handle: table): hecate.reactor.PipeStream
local PipeStream = core.class("PipeStream", tcp.TcpStream)

--- Path of the pipe the stream is bound to (the local end), or the peer's for a client.
---@return string
function PipeStream:path()
  if self._closed then tcp.fail_closed("path", "EBADF: stream is closed") end
  local path, err = self._handle:getpeername()
  if not path or path == "" then path, err = self._handle:getsockname() end
  if not path then uv_call.fail_transport("path", tostring(err)) end
  return path
end

core.finalise(PipeStream)

--- A listening pipe that accepts `PipeStream`s.
---@class hecate.reactor.PipeListener: hecate.reactor.TcpListener
---@overload fun(handle: table, options: table, path: string): hecate.reactor.PipeListener
local PipeListener = core.class("PipeListener", tcp.TcpListener)

---@param handle table
---@param options table
---@param path string
---@private
function PipeListener:init(handle, options, path)
  tcp.TcpListener.init(self, handle, options)
  self._path = path
end

---@return table
---@private
function PipeListener:_new_handle() return uv.new_pipe(false) end

---@param client table
---@return hecate.reactor.PipeStream
---@private
function PipeListener:_wrap(client) return PipeStream(client) end

--- Path the listener is bound to. The file is not removed on close (libuv unlinks it).
---@return string
function PipeListener:path() return self._path end

core.finalise(PipeListener)

local M = { PipeStream = PipeStream, PipeListener = PipeListener }

---@class hecate.reactor
local api = {}

--- Connects to a Unix-domain socket (a named pipe `\\.\pipe\name` on Windows). Bound it with
--- `reactor.deadline`; cancellation abandons the attempt and closes its handle.
---
--- Raises `hecate.reactor.TransportError` when the connection fails and
--- `hecate.core.ArgumentError` for a malformed path.
---@async
---@param path string  socket path
---@return hecate.reactor.PipeStream stream  the connected stream
function api.pipe_connect(path)
  check_path("pipe_connect", path)
  uv_call.begin("pipe_connect")
  local handle = uv.new_pipe(false)
  local state = {}
  local ok, failure = pcall(context.suspend, function(wake)
    handle:connect(path, function(e)
      state.done, state.err = true, e
      wake()
    end)
  end)
  if not ok then
    handle:close()
    error(failure, 0)
  end
  if state.err then
    handle:close()
    uv_call.fail_transport("connect " .. path, state.err)
  end
  return PipeStream(handle)
end

--- Binds and listens on a Unix-domain socket path. Does not suspend. The path must not exist.
---
--- Raises `hecate.reactor.TransportError` when binding or listening fails and
--- `hecate.core.ArgumentError` for a malformed path or option.
---@param path string  socket path
---@param options? { backlog?: integer }  length of the queue of pending connections, default 128
---@return hecate.reactor.PipeListener listener  the listening pipe
function api.pipe_listen(path, options)
  check_path("pipe_listen", path)
  options = check_options("pipe_listen", options)
  uv_call.begin("pipe_listen")
  local handle = uv.new_pipe(false)
  local bound, bind_err = handle:bind(path)
  if not bound then
    handle:close()
    uv_call.fail_transport("bind " .. path, tostring(bind_err))
  end
  local listener = PipeListener(handle, options, path)
  local listening, listen_err = handle:listen(options.backlog or DEFAULT_BACKLOG, function(e)
    if e then listener._failure = e else listener._incoming = listener._incoming + 1 end
    local wake = listener._wake
    listener._wake = nil
    if wake then wake() end
  end)
  if not listening then
    listener:close()
    uv_call.fail_transport("listen " .. path, tostring(listen_err))
  end
  return listener
end

M.pipe_connect = api.pipe_connect
M.pipe_listen = api.pipe_listen

return M
