-- Pipe transport: Unix-domain sockets (named pipes on Windows) over libuv pipe handles. It
-- reuses the stream and listener machinery of `tcp.lua`; only the handle kind, the addresses and
-- the absence of TCP options differ (OQ-28: luv is wrapped once, in the reactor).
global <const> type, error, require, pcall, tostring, tonumber, pairs, math, package

local core = require("hecate.core")
local uv = require("luv")
local uv_call = require("hecate.reactor.internal.uv_call")
local context = require("hecate.reactor.internal.context")
local tcp = require("hecate.reactor.tcp")

local DEFAULT_BACKLOG = 128
local IS_WINDOWS = package.config:sub(1, 1) == "\\"
--- Longest name after `\\.\pipe\` that Windows accepts for a named pipe.
local WINDOWS_NAME_LIMIT = 256

---@param name string
---@param path any
---@param windows? boolean  validate for Windows (default: the running platform; tests pass it)
local function check_path(name, path, windows)
  if windows == nil then windows = IS_WINDOWS end
  if type(path) ~= "string" or path == "" then
    error(core.ArgumentError(("%s: expects a path string, got %s"):format(name, tostring(path))), 3)
  end
  if windows then
    local pipe_name = path:match("^\\\\[.?]\\pipe\\(.*)$") or path
    if #pipe_name > WINDOWS_NAME_LIMIT then
      error(core.ArgumentError(("%s: the pipe name is %d characters, the limit on Windows is %d"):format(
        name, #pipe_name, WINDOWS_NAME_LIMIT)), 3)
    end
    return
  end
  -- `sun_path` holds 108 bytes on Linux and 104 on macOS, the terminating NUL included, so a path of at most
  -- 107 bytes (103 on macOS) fits; a longer path would otherwise fail with an obscure ENAMETOOLONG or EINVAL.
  local limit = (uv.os_uname().sysname == "Darwin" and 104 or 108) - 1
  if #path > limit then
    error(core.ArgumentError(("%s: the socket path is %d bytes, the limit on this platform is %d"):format(
      name, #path, limit)), 3)
  end
end

--- Who may connect to a listening pipe (`mode` option). `"owner"` restricts the socket file to its
--- owner (permissions 0600); the others open it to every user, with the given access.
local MODES = { owner = true, readable = "r", writable = "w", readwrite = "rw" }

---@param name string
---@param options any
---@return table
local function check_options(name, options)
  if options == nil then return {} end
  if type(options) ~= "table" then
    error(core.ArgumentError(("%s: expects an options table, got %s"):format(name, type(options))), 3)
  end
  for key in pairs(options) do
    if key ~= "backlog" and key ~= "mode" then
      error(core.ArgumentError(("%s: unknown option %s"):format(name, tostring(key))), 3)
    end
  end
  if options.backlog ~= nil and (math.type(options.backlog) ~= "integer" or options.backlog < 1) then
    error(core.ArgumentError(name .. ": option backlog must be a positive integer"), 3)
  end
  if options.mode ~= nil and MODES[options.mode] == nil then
    error(core.ArgumentError(name .. ": option mode must be \"owner\", \"readable\", \"writable\" or \"readwrite\""), 3)
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
  ---@diagnostic disable-next-line: invisible  -- base class initialiser
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

--- Path the listener is bound to. libuv removes the socket file when the listener closes; a stale file
--- left by a crashed process is not removed before the bind, so binding it fails.
---@return string
function PipeListener:path() return self._path end

core.finalise(PipeListener)

--- Options of `listen_pipe`.
---@class hecate.reactor.PipeListenOptions
---@field backlog? integer  length of the queue of pending connections, default 128 (ignored on Windows)
---@field mode? "owner"|"readable"|"writable"|"readwrite"  who may connect, default "owner" (ignored on Windows)

local M = { PipeStream = PipeStream, PipeListener = PipeListener, _check_path = check_path }

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
function api.connect_pipe(path)
  check_path("reactor.connect_pipe", path)
  uv_call.begin("reactor.connect_pipe")
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

--- Binds and listens on a Unix-domain socket path. Does not suspend. The path must not exist
--- (`EADDRINUSE` otherwise). Option `mode` says who may connect: `"owner"` (default) restricts the
--- socket file to its owner, `"readable"`, `"writable"` and `"readwrite"` open it to every user
--- with that access (libuv `chmod`). `mode` has no effect on Windows, where the default security
--- of the named pipe applies; `backlog` is ignored there too. On Windows the pipe name after
--- `\\.\pipe\` is limited to 256 characters.
---
--- Raises `hecate.reactor.TransportError` when binding or listening fails and
--- `hecate.core.ArgumentError` for a malformed path or option.
---@param path string  socket path
---@param options? hecate.reactor.PipeListenOptions
---@return hecate.reactor.PipeListener listener  the listening pipe
function api.listen_pipe(path, options)
  check_path("reactor.listen_pipe", path)
  options = check_options("reactor.listen_pipe", options)
  uv_call.begin("reactor.listen_pipe")
  local handle = uv.new_pipe(false)
  local bound, bind_err = handle:bind(path)
  if not bound then
    handle:close()
    uv_call.fail_transport("bind " .. path, tostring(bind_err))
  end
  if not IS_WINDOWS and path:sub(1, 1) ~= "\0" then -- an abstract socket has no file to protect
    local mode = options.mode or "owner"
    local changed, chmod_err
    if mode == "owner" then
      changed, chmod_err = uv.fs_chmod(path, tonumber("600", 8))
    else
      changed, chmod_err = handle:chmod(MODES[mode])
    end
    if not changed then
      handle:close()
      uv_call.fail_transport("chmod " .. path, tostring(chmod_err))
    end
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

M.connect_pipe = api.connect_pipe
M.listen_pipe = api.listen_pipe

return M
