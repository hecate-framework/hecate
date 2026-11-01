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
  -- libuv reads the path as a C string and would truncate it at a NUL. A leading NUL names an abstract
  -- socket (Linux) and stays allowed there.
  local nul = path:find("\0", 1, true)
  if nul and (windows or nul ~= 1 or path:find("\0", 2, true)) then
    error(core.ArgumentError(("%s: the path contains a NUL byte"):format(name)), 3)
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
--- owner (permissions 0600); the others open it to every user, with the given access. Connecting
--- to a Unix-domain socket requires write permission on the socket file (connect(2)), so
--- `"readable"` (0444) leaves the socket unconnectable for every user but, depending on the system,
--- root: it is of no use for connecting on POSIX. `"writable"` and `"readwrite"` are what let other
--- users connect.
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
---@overload fun(handle: table, options?: table, local_path?: string): hecate.reactor.PipeStream
local PipeStream = core.class("PipeStream", tcp.TcpStream)

---@param handle table
---@param options? table
---@param local_path? string  the path the stream was connected to, or the listener was asked to bind for an accepted stream
---@private
function PipeStream:init(handle, options, local_path)
  ---@diagnostic disable-next-line: invisible  -- base class initialiser
  tcp.TcpStream.init(self, handle, options)
  self._label = "reactor.PipeStream"
  self._local_path = local_path
end

--- Path of the pipe the stream is bound to (the local end), or the peer's for a client.
---@return string
function PipeStream:path()
  if self._closed then tcp.fail_closed(self, "path", "EBADF: stream is closed") end
  if self._local_path then return self._local_path end
  local path, err = self._handle:getpeername()
  if not path or path == "" then path, err = self._handle:getsockname() end
  if not path then uv_call.fail_transport(self._label .. ".path", "path", tostring(err)) end
  return path
end

core.finalise(PipeStream)

--- A listening pipe that accepts `PipeStream`s.
---@class hecate.reactor.PipeListener: hecate.reactor.TcpListener
---@overload fun(handle: table, options: table, path: string, file_identity?: { dev: integer, ino: integer }): hecate.reactor.PipeListener
local PipeListener = core.class("PipeListener", tcp.TcpListener)

---@param handle table
---@param options table
---@param path string
---@param file_identity? { dev: integer, ino: integer }  the socket file was linked to `path` here (this is its device and inode), so closing the listener removes it if it is still that file (libuv only knows the private path)
---@private
function PipeListener:init(handle, options, path, file_identity)
  ---@diagnostic disable-next-line: invisible  -- base class initialiser
  tcp.TcpListener.init(self, handle, options)
  self._label = "reactor.PipeListener"
  self._path = path
  self._file_identity = file_identity
end

--- Closes the listener and removes the socket file it linked to its path, provided the file at
--- the path is still that socket (same device and inode): a file that replaced it is left alone.
--- The removal is attempted even when closing the handle raises; that error is then re-raised.
function PipeListener:close()
  if self._closed then return end
  local closed, close_error = pcall(tcp.TcpListener.close, self)
  local identity = self._file_identity
  if identity then
    local stat = uv.fs_stat(self._path)
    if stat and stat.dev == identity.dev and stat.ino == identity.ino then uv.fs_unlink(self._path) end
  end
  if not closed then error(close_error, 0) end
end

---@return table
---@private
function PipeListener:_new_handle() return uv.new_pipe(false) end

---@param client table
---@return hecate.reactor.PipeStream
---@private
function PipeListener:_wrap(client) return PipeStream(client, nil, self._path) end

--- Path the listener is bound to. The socket file is removed when the listener closes; a stale file
--- left by a crashed process is not removed before the bind, so binding it fails.
---@return string
function PipeListener:path() return self._path end

core.finalise(PipeListener)

--- Options of `listen_pipe`.
---@class hecate.reactor.PipeListenOptions
---@field backlog? integer  length of the queue of pending connections, default 128 (ignored on Windows)
---@field mode? "owner"|"readable"|"writable"|"readwrite"  permissions of the socket file, default "owner" (0600); other users can connect only with "writable" or "readwrite", "readable" is of no use for connecting on POSIX (connect(2) needs write permission); ignored on Windows

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
    uv_call.fail_transport("reactor.connect_pipe", "connect " .. path, state.err)
  end
  return PipeStream(handle, nil, path)
end

--- File permissions of the socket for each `mode` option.
local MODE_BITS = { owner = tonumber("600", 8), readable = tonumber("444", 8), writable = tonumber("222", 8), readwrite = tonumber("666", 8) }

--- Longest socket path the platform accepts (see `check_path`).
local function path_limit() return (uv.os_uname().sysname == "Darwin" and 104 or 108) - 1 end

--- Errors of `link(2)` that mean "this file system has no hard links for sockets", the only ones
--- that justify the direct-bind fallback.
local NO_HARD_LINKS = { EPERM = true, ENOTSUP = true, EOPNOTSUPP = true, EXDEV = true, ENOSYS = true, EMLINK = true }

--- Binds `handle` so that the socket file is never visible at `path` with permissions other than
--- the requested ones (owner decision on OQ-47 (4)): it is bound inside a fresh directory that only
--- the owner can enter (libuv creates it `0700`), given its final permissions there, then linked to
--- `path`; the link fails if `path` exists, as a bind would. Returns `"linked"` and the device and inode of
--- the socket file (the hard link shares them) when `path` is bound this way; `"unused"` when the private
--- directory cannot be used (path too long once the directory is added, or the directory cannot be created)
--- and `handle` is untouched; `"retry"` when the file system has no hard links (the link failed with
--- `EPERM`, `ENOTSUP`, `EOPNOTSUPP`, `EXDEV`, `ENOSYS` or `EMLINK`: some network and virtual file systems),
--- `handle` is closed and the caller binds a new one directly, then restricts afterwards. Any other
--- failure raises `TransportError` and closes `handle`.
---
--- Exposure window of the direct-bind fallback (`"retry"` and `"unused"`): the socket file exists at `path`
--- with the permissions its creation gave it, derived from the umask of the process, until the `chmod` that
--- follows the bind. Lua cannot set a umask, so the window cannot be closed there: a process that needs
--- the guarantee sets a restrictive umask before it starts.
---@param handle table
---@param path string
---@param mode string
---@return "linked"|"unused"|"retry" outcome
---@return { dev: integer, ino: integer }? identity  of the socket file, when linked
local function bind_private(handle, path, mode)
  local parent = path:match("^(.*)/[^/]*$")
  if parent == nil then parent = "." elseif parent == "" then parent = "/" end
  local private = uv.fs_mkdtemp((parent == "/" and "" or parent) .. "/.hs-XXXXXX")
  if not private then return "unused" end
  local private_path = private .. "/s"
  local function discard()
    uv.fs_unlink(private_path)
    uv.fs_rmdir(private)
  end
  if #private_path > path_limit() then
    discard()
    return "unused"
  end
  local bound, bind_err = handle:bind(private_path)
  if not bound then
    discard()
    handle:close()
    uv_call.fail_transport("reactor.listen_pipe", "bind " .. path, tostring(bind_err))
  end
  local changed, chmod_err = uv.fs_chmod(private_path, MODE_BITS[mode])
  local identity, linked, link_err
  if changed then
    local stat = uv.fs_stat(private_path)
    if stat then identity = { dev = stat.dev, ino = stat.ino } end
    if identity then linked, link_err = uv.fs_link(private_path, path) else link_err = "EIO: cannot stat the socket file" end
  end
  discard()
  if not changed then
    handle:close()
    uv_call.fail_transport("reactor.listen_pipe", "chmod " .. path, tostring(chmod_err))
  end
  if not linked then
    handle:close()
    local code = tostring(link_err):match("^(%u[%u%d_]*):")
    -- An existing file is what a direct bind reports as EADDRINUSE.
    if code == "EEXIST" then
      uv_call.fail_transport("reactor.listen_pipe", "bind " .. path, "EADDRINUSE: address already in use")
    end
    if NO_HARD_LINKS[code] then return "retry" end -- the file system has no hard links for sockets: bind directly
    uv_call.fail_transport("reactor.listen_pipe", "link " .. path, tostring(link_err))
  end
  return "linked", identity
end

--- Binds and listens on a Unix-domain socket path. Does not suspend. The path must not exist
--- (`EADDRINUSE` otherwise). Option `mode` sets the permissions of the socket file: `"owner"` (default)
--- restricts it to its owner (0600); `"readable"` (0444), `"writable"` (0222) and `"readwrite"` (0666) open it
--- to every user with that access. Connecting to a Unix-domain socket requires write permission, so
--- `"readable"` is of no use for connecting on POSIX (nobody but, depending on the system, root can
--- connect); `"writable"` or `"readwrite"` is what lets other users connect. The socket is bound in a private `0700`
--- directory next to `path` and linked to it with its final permissions, so it is never visible with wider
--- ones. When the file system has no hard links (the link fails with `EPERM`, `ENOTSUP`, `EOPNOTSUPP`, `EXDEV`,
--- `ENOSYS` or `EMLINK`), or the private directory cannot be used, the socket is bound directly and restricted
--- right after: until that `chmod` the file has the permissions the umask of the process gives it (Lua cannot
--- set a umask, so a process that needs the guarantee sets a restrictive one before it starts). Any other link
--- failure raises `TransportError`. Closing the listener removes the socket file only if the file at `path` is
--- still the socket it linked. `mode` has no effect on Windows, where the default security of the named pipe
--- applies; `backlog` is ignored there too. On Windows the pipe name after `\\.\pipe\` is limited to 256 characters.
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
  local owns_file, identity = false, nil
  if not IS_WINDOWS and path:sub(1, 1) ~= "\0" then -- an abstract socket has no file to protect
    local outcome
    outcome, identity = bind_private(handle, path, options.mode or "owner")
    owns_file = outcome == "linked"
    if outcome == "retry" then handle = uv.new_pipe(false) end -- the first one was bound to the private path and closed
  end
  if not owns_file then
    local bound, bind_err = handle:bind(path)
    if not bound then
      handle:close()
      uv_call.fail_transport("reactor.listen_pipe", "bind " .. path, tostring(bind_err))
    end
    if not IS_WINDOWS and path:sub(1, 1) ~= "\0" then -- the private directory was not usable: restrict after the bind
      local mode = options.mode or "owner"
      local changed, chmod_err
      if mode == "owner" then
        changed, chmod_err = uv.fs_chmod(path, tonumber("600", 8))
      else
        changed, chmod_err = handle:chmod(MODES[mode])
      end
      if not changed then
        handle:close()
        uv_call.fail_transport("reactor.listen_pipe", "chmod " .. path, tostring(chmod_err))
      end
    end
  end
  local listener = PipeListener(handle, options, path, identity)
  local listening, listen_err = handle:listen(options.backlog or DEFAULT_BACKLOG, function(e)
    if e then listener._failure = e else listener._incoming = listener._incoming + 1 end
    local wake = listener._wake
    listener._wake = nil
    if wake then wake() end
  end)
  if not listening then
    listener:close()
    uv_call.fail_transport("reactor.listen_pipe", "listen " .. path, tostring(listen_err))
  end
  return listener
end

M.connect_pipe = api.connect_pipe
M.listen_pipe = api.listen_pipe

return M
