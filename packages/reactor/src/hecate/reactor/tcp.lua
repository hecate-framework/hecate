-- TCP transport as suspending calls over libuv stream handles (concurrency.md, "Model":
-- transparent I/O; ADR 0002: luv is wrapped once, here). Callbacks only record a result and
-- wake the coroutine; the scheduler resumes it (reactor/CLAUDE.md, known pitfalls).
--
-- Cancellation rules (reactor/CLAUDE.md invariant: cancellation runs `<close>` handlers):
--   * `read` and `accept` leave the handle intact: data or connections that arrive after the
--     coroutine was withdrawn are kept for the next call, never dropped.
--   * `write`, `shutdown` and `tcp_connect` cannot be withdrawn from libuv. When one is
--     cancelled before it completed, the handle is closed (libuv then cancels the request),
--     because the number of bytes sent is unknown; a cancelled connect never leaks its handle.
--   * `close` is idempotent, never suspends, and wakes every coroutine waiting on the handle.
global <const> type, error, require, pcall, tostring, math, pairs, table

local core = require("hecate.core")
local uv = require("luv")
local uv_call = require("hecate.reactor.internal.uv_call")
local context = require("hecate.reactor.internal.context")

--- Defaults of the transport options (OQ-30).
local DEFAULT_NODELAY = true
local DEFAULT_KEEPALIVE = false
local DEFAULT_KEEPALIVE_DELAY = 60 -- seconds before the first probe, when keep-alive is on
local DEFAULT_BACKLOG = 128
--- Bytes the stream reads ahead of its reader before it stops reading from the socket (back-pressure).
local READ_AHEAD = 64 * 1024

--- Options of a TCP connection.
---@class hecate.reactor.TcpOptions
---@field nodelay? boolean  disable Nagle's algorithm; default true
---@field keepalive? boolean  enable TCP keep-alive probes; default false
---@field keepalive_delay? integer  seconds of idleness before the first probe (a positive integer), default 60

--- Options of a TCP listener: those of a connection plus the backlog.
---@class hecate.reactor.TcpListenOptions: hecate.reactor.TcpOptions
---@field backlog? integer  length of the queue of pending connections, default 128
---@field reuseport? boolean  let several sockets (in several processes) listen on the same port, the kernel balancing the connections; see `reactor.supports_reuseport`

--- The address of a socket: IP address, port and family.
---@class hecate.reactor.SocketAddress
---@field ip string  numeric address
---@field port integer
---@field family string  "inet" or "inet6"

--- luv raises a Lua error for a malformed address; report it as libuv's EINVAL instead.
---@param fn function
---@param ... any
---@return any ok
---@return string? err
local function protected(fn, ...)
  local ok, result, err = pcall(fn, ...)
  if not ok then return nil, "EINVAL: invalid address (" .. tostring(result) .. ")" end
  return result, err
end

local KNOWN = { nodelay = true, keepalive = true, keepalive_delay = true, backlog = true, reuseport = true }

---@param name string
---@param options any
---@return table
local function check_options(name, options)
  if options == nil then return {} end
  if type(options) ~= "table" then
    error(core.ArgumentError(("%s expects an options table, got %s"):format(name, type(options))), 3)
  end
  for key in pairs(options) do
    if not KNOWN[key] then
      error(core.ArgumentError(("%s: unknown option %s"):format(name, tostring(key))), 3)
    end
  end
  if options.nodelay ~= nil and type(options.nodelay) ~= "boolean" then
    error(core.ArgumentError(name .. ": option nodelay must be a boolean"), 3)
  end
  if options.keepalive ~= nil and type(options.keepalive) ~= "boolean" then
    error(core.ArgumentError(name .. ": option keepalive must be a boolean"), 3)
  end
  if options.keepalive_delay ~= nil and (math.type(options.keepalive_delay) ~= "integer" or options.keepalive_delay < 1) then
    error(core.ArgumentError(name .. ": option keepalive_delay must be a positive integer number of seconds"), 3)
  end
  if options.backlog ~= nil and (math.type(options.backlog) ~= "integer" or options.backlog < 1) then
    error(core.ArgumentError(name .. ": option backlog must be a positive integer"), 3)
  end
  if options.reuseport ~= nil and type(options.reuseport) ~= "boolean" then
    error(core.ArgumentError(name .. ": option reuseport must be a boolean"), 3)
  end
  return options
end

---@param name string
---@param host any
---@param port any
local function check_endpoint(name, host, port)
  if type(host) ~= "string" then
    error(core.ArgumentError(("%s expects a numeric address string, got %s"):format(name, type(host))), 3)
  end
  if math.type(port) ~= "integer" or port < 0 or port > 65535 then
    error(core.ArgumentError(("%s expects a port in 0..65535, got %s"):format(name, tostring(port))), 3)
  end
end

--- Raises the `TransportError` of a handle that is closed (or was closed while a coroutine waited).
---@param operation string
---@param message string
local function fail_closed(operation, message)
  uv_call.fail_transport(operation, message)
end

---@param handle table
---@param options table
local function apply_options(handle, options)
  local nodelay = options.nodelay
  if nodelay == nil then nodelay = DEFAULT_NODELAY end
  local keepalive = options.keepalive
  if keepalive == nil then keepalive = DEFAULT_KEEPALIVE end
  local ok, err = handle:nodelay(nodelay)
  if not ok then uv_call.fail_transport("nodelay", tostring(err)) end
  ok, err = handle:keepalive(keepalive, options.keepalive_delay or DEFAULT_KEEPALIVE_DELAY)
  if not ok then uv_call.fail_transport("keepalive", tostring(err)) end
end

---@param handle table
---@param operation string
---@return hecate.reactor.SocketAddress
local function address_of(handle, operation)
  local address, err
  if operation == "peer_address" then address, err = handle:getpeername() else address, err = handle:getsockname() end
  if not address then uv_call.fail_transport(operation, tostring(err)) end
  return { ip = address.ip, port = address.port, family = address.family }
end

--- A connected TCP stream; its operations suspend until the data moves.
---@class hecate.reactor.TcpStream
---@overload fun(handle: table, options?: table): hecate.reactor.TcpStream
local TcpStream = core.class("TcpStream")

---@param handle table  a connected libuv TCP handle, owned by the stream from now on
---@param options? table
---@private
function TcpStream:init(handle, options)
  self._handle = handle
  self._closed = false
  self._inbox = nil -- bytes received and not yet returned, from `_offset` on
  self._offset = 1
  self._eof = false
  self._failure = nil -- libuv error string of a failed read
  self._reading = false -- a coroutine is waiting in `read`
  self._started = false -- libuv delivers data to `_on_read`
  self._demanded = false -- `read` was called at least once: reading ahead is allowed
  self._wake = nil -- wakes the coroutine waiting in `read`
  self._options = options or {}
  -- One callback for the life of the stream (not one closure per `read`).
  self._on_read = function(e, data)
    if e then
      self._failure = e
    elseif data == nil then
      self._eof = true
    elseif #data > 0 then
      local inbox = self._inbox
      if inbox == nil then
        self._inbox, self._offset = data, 1
      else
        self._inbox = inbox:sub(self._offset) .. data
        self._offset = 1
      end
    end
    -- Back-pressure: stop reading at the end of the stream, on failure, or once enough is buffered.
    if e or data == nil or (self._inbox ~= nil and #self._inbox - self._offset + 1 >= READ_AHEAD) then
      self:_stop_reading()
    end
    local wake = self._wake
    self._wake = nil
    if wake then wake() end
  end
end

--- Starts delivering data to the stream (idempotent).
---@return boolean? ok
---@return string? err
---@private
function TcpStream:_start_reading()
  if self._started then return true end
  local ok, err = self._handle:read_start(self._on_read)
  if ok then self._started = true end
  return ok, err
end

--- Stops delivering data (idempotent); data already received stays in the inbox.
---@private
function TcpStream:_stop_reading()
  if not self._started then return end
  self._started = false
  if not self._closed then self._handle:read_stop() end
end

--- Raises when the stream is closed.
---@param operation string
local function require_open(self, operation)
  if self._closed then fail_closed(operation, "EBADF: stream is closed") end
end

--- Suspends until a libuv request completes. `start(callback)` must return the request, or
--- nil and an error string. A cancellation that arrives before completion closes the stream.
---@async
---@param operation string
---@param start fun(callback: fun(err: string?)): any, string?
---@private
function TcpStream:_await(operation, start)
  require_open(self, operation)
  uv_call.begin(operation)
  local state = {}
  local ok, failure = pcall(context.suspend, function(wake)
    local started, err = start(function(e)
      state.done, state.err = true, e
      wake()
    end)
    if not started then
      state.done, state.err = true, tostring(err)
      wake()
    end
  end)
  if not ok then
    if not state.done then self:close() end
    error(failure, 0)
  end
  if state.err then uv_call.fail_transport(operation, state.err) end
end

--- Reads at most `max` bytes (default: whatever the next receive delivers). Returns nil at
--- end of stream (the peer shut down its side); never returns an empty string. Cancelling a
--- suspended read keeps the stream open and loses no data. One coroutine reads at a time.
---
--- Once a first read was made the stream reads ahead of its reader by up to 64 KiB (it keeps
--- libuv reading between two calls instead of restarting it for every call), then stops reading
--- from the socket until the reader caught up: the kernel buffers apply back-pressure to the peer.
---@async
---@param max? integer
---@return string?
function TcpStream:read(max)
  uv_call.begin("read")
  if max ~= nil and (math.type(max) ~= "integer" or max < 1) then
    error(core.ArgumentError(("read expects a positive integer, got %s"):format(tostring(max))), 2)
  end
  require_open(self, "read")
  if self._reading then error(core.Error("read: another coroutine is already reading this stream"), 2) end
  self._demanded = true
  while self._inbox == nil and not self._eof and self._failure == nil do
    self._reading = true
    local ok, failure = pcall(context.suspend, function(wake)
      self._wake = wake
      local started, err = self:_start_reading()
      if not started then
        self._failure = tostring(err)
        self._wake = nil
        wake()
      end
      return function() self._wake = nil end -- data that still arrives is kept in the inbox
    end)
    self._reading = false
    if not ok then error(failure, 0) end
    if self._closed then fail_closed("read", "ECANCELED: stream closed while reading") end
  end
  local data = self._inbox
  if data ~= nil then
    local offset = self._offset
    local available = #data - offset + 1
    local result
    if max ~= nil and available > max then
      result = data:sub(offset, offset + max - 1)
      self._offset = offset + max
    else
      result = offset == 1 and data or data:sub(offset)
      self._inbox, self._offset = nil, 1
    end
    -- The reader caught up: let libuv read ahead again.
    if not self._started and not self._eof and self._failure == nil and not self._closed
        and (self._inbox == nil or #self._inbox - self._offset + 1 < READ_AHEAD) then
      self:_start_reading()
    end
    return result
  end
  if self._failure ~= nil then uv_call.fail_transport("read", self._failure) end
  return nil
end

--- Writes `data`; returns once libuv has handed every byte to the operating system, so a slow
--- peer suspends the writer (back-pressure). A cancelled write closes the stream.
---@async
---@param data string
function TcpStream:write(data)
  if type(data) ~= "string" then
    error(core.ArgumentError(("write expects a string, got %s"):format(type(data))), 2)
  end
  uv_call.begin("write")
  require_open(self, "write")
  if #data == 0 then return end
  self:_await("write", function(callback) return self._handle:write(data, callback) end)
end

--- Half-close: signals end of stream to the peer once pending writes are flushed; the stream
--- stays readable. A cancelled shutdown closes the stream.
---@async
function TcpStream:shutdown()
  self:_await("shutdown", function(callback) return self._handle:shutdown(callback) end)
end

--- Closes the stream. Idempotent, never suspends; coroutines waiting on it are woken with an
--- `TransportError` (`ECANCELED`). Pending writes are abandoned.
function TcpStream:close()
  if self._closed then return end
  self._closed = true
  self._started = false
  local wake = self._wake
  self._wake = nil
  if not self._handle:is_closing() then self._handle:close() end
  if wake then wake() end
end

--- Closing at the end of a `<close>` scope, including on cancellation.
function TcpStream:__close() self:close() end

--- Returns whether the stream is closed.
---@return boolean
function TcpStream:is_closed() return self._closed end

--- Address of the remote end.
---@return hecate.reactor.SocketAddress
function TcpStream:peer_address()
  require_open(self, "peer_address")
  return address_of(self._handle, "peer_address")
end

--- Address of the local end.
---@return hecate.reactor.SocketAddress
function TcpStream:local_address()
  require_open(self, "local_address")
  return address_of(self._handle, "local_address")
end

--- Enables or disables Nagle's algorithm (`true` disables it).
---@param enabled boolean
function TcpStream:set_nodelay(enabled)
  require_open(self, "set_nodelay")
  if type(enabled) ~= "boolean" then
    error(core.ArgumentError(("set_nodelay expects a boolean, got %s"):format(type(enabled))), 2)
  end
  local ok, err = self._handle:nodelay(enabled)
  if not ok then uv_call.fail_transport("set_nodelay", tostring(err)) end
end

--- Enables or disables keep-alive probes; `delay` is the idle time in seconds before the first
--- (a positive integer).
---@param enabled boolean
---@param delay? integer  a positive integer, default 60
function TcpStream:set_keepalive(enabled, delay)
  require_open(self, "set_keepalive")
  if type(enabled) ~= "boolean" then
    error(core.ArgumentError(("set_keepalive expects a boolean, got %s"):format(type(enabled))), 2)
  end
  if delay ~= nil and (math.type(delay) ~= "integer" or delay < 1) then
    error(core.ArgumentError("set_keepalive: delay must be a positive integer number of seconds"), 2)
  end
  local ok, err = self._handle:keepalive(enabled, delay or DEFAULT_KEEPALIVE_DELAY)
  if not ok then uv_call.fail_transport("set_keepalive", tostring(err)) end
end

core.finalise(TcpStream)

--- A listening TCP socket that accepts streams.
---@class hecate.reactor.TcpListener
---@overload fun(handle: table, options: table): hecate.reactor.TcpListener
local TcpListener = core.class("TcpListener")

---@param handle table  a listening libuv TCP handle
---@param options table
---@private
function TcpListener:init(handle, options)
  self._handle = handle
  self._options = options
  self._closed = false
  self._incoming = 0 -- connections libuv announced and `accept` has not taken
  self._failure = nil
  self._wake = nil
  self._accepting = false
end

--- Errors that mean the peer of an accepted connection is already gone (it reset the connection
--- before the options were applied; BSD and macOS report it on `setsockopt`): the connection is
--- dropped and `accept` goes on with the next one.
local DROPPED = { EINVAL = true, ENOTCONN = true, ECONNRESET = true, ECONNABORTED = true }

--- Suspends until a connection arrives and returns it as a `TcpStream`. Cancelling keeps the
--- listener open; connections that arrive meanwhile stay queued. Connections are taken one
--- per call, so a slow acceptor leaves the rest in the kernel backlog (back-pressure). A
--- connection whose peer already reset it (the options cannot be applied: `EINVAL`, `ENOTCONN`,
--- `ECONNRESET`) is closed and skipped; any other failure is raised.
---@async
---@return hecate.reactor.TcpStream
function TcpListener:accept()
  uv_call.begin("accept")
  require_open(self, "accept")
  if self._accepting then error(core.Error("accept: another coroutine is already accepting"), 2) end
  while true do
    while self._incoming == 0 and self._failure == nil do
      self._accepting = true
      local ok, failure = pcall(context.suspend, function(wake)
        self._wake = wake
        return function() self._wake = nil end
      end)
      self._accepting = false
      if not ok then error(failure, 0) end
      if self._closed then fail_closed("accept", "ECANCELED: listener closed while accepting") end
    end
    if self._incoming == 0 then
      local failure = self._failure
      self._failure = nil
      uv_call.fail_transport("accept", failure --[[@as string]])
    end
    local client = self:_new_handle()
    local accepted, err = self._handle:accept(client)
    if not accepted then
      client:close()
      uv_call.fail_transport("accept", tostring(err))
    end
    self._incoming = self._incoming - 1
    local wrapped, result = pcall(self._wrap, self, client)
    if wrapped then return result end
    client:close()
    local errno = core.is_instance_of(result, uv_call.TransportError) and result.context.errno or nil
    if not (errno and DROPPED[errno]) then error(result, 0) end
  end
end

--- Creates the libuv handle of an accepted connection (overridden by pipe listeners).
---@return table
---@private
function TcpListener:_new_handle() return uv.new_tcp() end

--- Wraps an accepted handle in a stream (overridden by pipe listeners).
---@param client table
---@return hecate.reactor.TcpStream
---@private
function TcpListener:_wrap(client)
  apply_options(client, self._options)
  return TcpStream(client, self._options)
end

--- Stops listening. Idempotent, never suspends; a coroutine waiting in `accept` is woken with an
--- `TransportError` (`ECANCELED`). Connections already accepted are unaffected.
function TcpListener:close()
  if self._closed then return end
  self._closed = true
  local wake = self._wake
  self._wake = nil
  if not self._handle:is_closing() then self._handle:close() end
  if wake then wake() end
end

--- Closing at the end of a `<close>` scope.
function TcpListener:__close() self:close() end

--- Returns whether the listener is closed.
---@return boolean
function TcpListener:is_closed() return self._closed end

--- Address the listener is bound to (use it to learn the port chosen for port 0).
---@return hecate.reactor.SocketAddress
function TcpListener:local_address()
  require_open(self, "local_address")
  return address_of(self._handle, "local_address")
end

core.finalise(TcpListener)

local M = { TcpStream = TcpStream, TcpListener = TcpListener, fail_closed = fail_closed }

-- Documented on `hecate.reactor` (module class completed here so that the LuaLS export lists the
-- functions; coding-standards.md, "Annotations for the reference").

---@class hecate.reactor
local api = {}

--- Connects to a numeric address. Name resolution is not part of this call (a host name
--- raises `TransportError` `EINVAL`). Bound it with `reactor.deadline`; cancellation abandons the
--- attempt and closes its handle. Options: see `hecate.reactor.TcpOptions`.
---
--- Raises `hecate.reactor.TransportError` when the connection fails or `host` is not a numeric
--- address, and `hecate.core.ArgumentError` for a malformed port or option.
---@async
---@param host string  numeric IPv4 or IPv6 address
---@param port integer  TCP port
---@param options? hecate.reactor.TcpOptions  `nodelay`, `keepalive` and `keepalive_delay`
---@return hecate.reactor.TcpStream stream  the connected stream
function api.tcp_connect(host, port, options)
  check_endpoint("tcp_connect", host, port)
  options = check_options("tcp_connect", options)
  uv_call.begin("tcp_connect")
  local handle = uv.new_tcp()
  local state = {}
  local ok, failure = pcall(context.suspend, function(wake)
    local started, err = protected(handle.connect, handle, host, port, function(e)
      state.done, state.err = true, e
      wake()
    end)
    if not started then
      state.done, state.err = true, tostring(err)
      wake()
    end
  end)
  if not ok then
    handle:close()
    error(failure, 0)
  end
  if state.err then
    handle:close()
    uv_call.fail_transport("connect " .. host .. ":" .. port, state.err)
  end
  local applied, apply_failure = pcall(apply_options, handle, options)
  if not applied then
    handle:close()
    error(apply_failure, 0)
  end
  return TcpStream(handle, options)
end

--- Binds and listens on a numeric address (port 0 picks a free port; see `local_address`).
--- Does not suspend. Accepted streams get the listener's `nodelay` and `keepalive` options.
---
--- With `reuseport = true` several sockets, in several processes, listen on the same port and the
--- kernel balances the connections among them (Linux); without luv support (OQ-43) the call raises
--- `TransportError` `ENOTSUP` instead of silently binding a socket that fails later.
---
--- Raises `hecate.reactor.TransportError` when binding or listening fails, and
--- `hecate.core.ArgumentError` for a malformed host, port or option.
---@param host string  numeric IPv4 or IPv6 address
---@param port integer  TCP port; 0 picks a free port
---@param options? hecate.reactor.TcpListenOptions  stream options and `backlog`
---@return hecate.reactor.TcpListener listener  the listening socket
function api.tcp_listen(host, port, options)
  check_endpoint("tcp_listen", host, port)
  options = check_options("tcp_listen", options)
  uv_call.begin("tcp_listen")
  local handle = uv.new_tcp()
  if options.reuseport and not api.supports_reuseport() then
    handle:close()
    uv_call.fail_transport("bind " .. host .. ":" .. port,
      "ENOTSUP: reuseport is not available (platform or luv without TCP reuseport; see reactor.supports_reuseport)")
  end
  local bound, bind_err = protected(handle.bind, handle, host, port, options.reuseport and { reuseport = true } or nil)
  if not bound then
    handle:close()
    uv_call.fail_transport("bind " .. host .. ":" .. port, tostring(bind_err))
  end
  local listener = TcpListener(handle, options)
  local listening, listen_err = handle:listen(options.backlog or DEFAULT_BACKLOG, function(e)
    if e then
      listener._failure = e
    else
      listener._incoming = listener._incoming + 1
    end
    local wake = listener._wake
    listener._wake = nil
    if wake then wake() end
  end)
  if not listening then
    listener:close()
    uv_call.fail_transport("listen " .. host .. ":" .. port, tostring(listen_err))
  end
  return listener
end

local reuseport_supported

--- Returns whether this platform and this luv let several TCP sockets listen on one port
--- (`reuseport = true`). The first call probes with two loopback sockets and caches the answer.
--- It says nothing about balance: macOS accepts the flag and gives every connection to one
--- socket, which is why the listening strategy lives above (ADR 0023). Does not suspend.
---@return boolean supported  whether `tcp_listen` accepts `reuseport = true`
function api.supports_reuseport()
  if reuseport_supported ~= nil then return reuseport_supported end
  local first, second = uv.new_tcp(), uv.new_tcp()
  local flags = { reuseport = true }
  local supported = false
  if protected(first.bind, first, "127.0.0.1", 0, flags) then
    local address = first:getsockname()
    if address and protected(second.bind, second, "127.0.0.1", address.port, flags)
        and first:listen(1, function() end) and second:listen(1, function() end) then
      supported = true
    end
  end
  first:close(); second:close()
  reuseport_supported = supported
  return supported
end

--- Forgets the probe of `supports_reuseport` (tests only: the answer is cached for good).
function M.reset_reuseport_probe() reuseport_supported = nil end

M.supports_reuseport = api.supports_reuseport
M.tcp_connect = api.tcp_connect
M.tcp_listen = api.tcp_listen

return M
