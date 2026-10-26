-- `net.connect_pipe` and `net.listen_pipe`: Unix-domain sockets, named pipes on Windows.
global <const> require

local reactor = require("hecate.reactor")
local PipeStream = require("hecate.net.pipe_stream")
local PipeListener = require("hecate.net.pipe_listener")

-- Documented on `hecate.net` (module class completed here so that the LuaLS export lists the
-- functions; coding-standards.md, "Annotations for the reference").

---@class hecate.net
local M = {}

--- Connects to a Unix-domain socket path (`\\.\pipe\name` on Windows). Bound it with
--- `reactor.deadline`.
---
--- Raises `hecate.reactor.TransportError` when the connection fails and
--- `hecate.core.ArgumentError` for a malformed path.
---@async
---@param path string  socket path
---@return hecate.net.PipeStream stream  the connected stream
function M.connect_pipe(path)
  return PipeStream(reactor.connect_pipe(path))
end

--- Binds and listens on a Unix-domain socket path, which must not exist. Does not suspend. Options:
--- `backlog` (length of the queue of pending connections, default 128, ignored on Windows) and `mode`
--- (who may connect: `"owner"`, the default, `"readable"`, `"writable"` or `"readwrite"`; no effect on
--- Windows). A Windows pipe name is limited to 256 characters, a Unix socket path to the platform's
--- `sun_path` (at most 107 bytes on Linux, 103 on macOS, excluding the terminating NUL): a longer one raises `ArgumentError`.
---
--- Raises `hecate.reactor.TransportError` when binding or listening fails and
--- `hecate.core.ArgumentError` for a malformed path or option.
---@param path string  socket path
---@param options? hecate.reactor.PipeListenOptions  `backlog` and `mode`
---@return hecate.net.PipeListener listener  the listening pipe
function M.listen_pipe(path, options)
  return PipeListener(reactor.listen_pipe(path, options))
end

return M
