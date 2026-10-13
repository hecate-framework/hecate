-- TCP transport as suspending calls over libuv stream handles (concurrency.md, "Model":
-- transparent I/O; ADR 0002: luv is wrapped once, here). Callbacks only record a result and
-- wake the task; the scheduler resumes it (reactor/CLAUDE.md, known pitfalls).
--
-- Cancellation rules (reactor/CLAUDE.md invariant: cancellation runs `<close>` handlers):
--   * `read` and `accept` leave the handle intact: data or connections that arrive after the
--     task was withdrawn are kept for the next call, never dropped.
--   * `write`, `shutdown` and `tcp_connect` cannot be withdrawn from libuv. When one is
--     cancelled before it completed, the handle is closed (libuv then cancels the request),
--     because the number of bytes sent is unknown; a cancelled connect never leaks its handle.
--   * `close` is idempotent, never suspends, and wakes every task waiting on the handle.
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

---@class hecate.reactor.TcpOptions
---@field nodelay? boolean  disable Nagle's algorithm; default true
---@field keepalive? boolean  enable TCP keep-alive probes; default false
---@field keepalive_delay? number  seconds of idleness before the first probe, default 60

---@class hecate.reactor.TcpListenOptions: hecate.reactor.TcpOptions
---@field backlog? integer  length of the queue of pending connections, default 128

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

local KNOWN = { nodelay = true, keepalive = true, keepalive_delay = true, backlog = true }

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
  if options.keepalive_delay ~= nil and (type(options.keepalive_delay) ~= "number" or options.keepalive_delay < 0) then
    error(core.ArgumentError(name .. ": option keepalive_delay must be a non-negative number of seconds"), 3)
  end
  if options.backlog ~= nil and (math.type(options.backlog) ~= "integer" or options.backlog < 1) then
    error(core.ArgumentError(name .. ": option backlog must be a positive integer"), 3)
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

--- Raises the `TransportError` of a handle that is closed (or was closed while a task waited).
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

---@class hecate.reactor.TcpStream
---@overload fun(handle: table, options?: table): hecate.reactor.TcpStream
local TcpStream = core.class("TcpStream")

---@param handle table  a connected libuv TCP handle, owned by the stream from now on
---@param options? table
---@private
function TcpStream:init(handle, options)
  self._handle = handle
  self._closed = false
  self._inbox = nil -- bytes received and not yet returned
  self._eof = false
  self._failure = nil -- libuv error string of a failed read
  self._reading = false
  self._wake = nil -- wakes the task waiting in `read`
  self._options = options or {}
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
--- suspended read keeps the stream open and loses no data. One task reads at a time.
---@async
---@param max? integer
---@return string?
function TcpStream:read(max)
  uv_call.begin("read")
  if max ~= nil and (math.type(max) ~= "integer" or max < 1) then
    error(core.ArgumentError(("read expects a positive integer, got %s"):format(tostring(max))), 2)
  end
  require_open(self, "read")
  if self._reading then error(core.Error("read: another task is already reading this stream"), 2) end
  while self._inbox == nil and not self._eof and self._failure == nil do
    self._reading = true
    local ok, failure = pcall(context.suspend, function(wake)
      self._wake = wake
      local started, err = self._handle:read_start(function(e, data)
        self._handle:read_stop()
        if e then
          self._failure = e
        elseif data ~= nil and #data > 0 then
          self._inbox = data
        elseif data == nil then
          self._eof = true
        end
        local wake_reader = self._wake
        self._wake = nil
        if wake_reader then wake_reader() end
      end)
      if not started then
        self._failure = tostring(err)
        self._wake = nil
        wake()
      end
      return function()
        self._wake = nil
        if not self._closed then self._handle:read_stop() end
      end
    end)
    self._reading = false
    if not ok then error(failure, 0) end
    if self._closed then fail_closed("read", "ECANCELED: stream closed while reading") end
  end
  local data = self._inbox
  if data ~= nil then
    if max ~= nil and #data > max then
      self._inbox = data:sub(max + 1)
      return data:sub(1, max)
    end
    self._inbox = nil
    return data
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

--- Closes the stream. Idempotent, never suspends; tasks waiting on it are woken with an
--- `TransportError` (`ECANCELED`). Pending writes are abandoned.
function TcpStream:close()
  if self._closed then return end
  self._closed = true
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
  local ok, err = self._handle:nodelay(enabled)
  if not ok then uv_call.fail_transport("set_nodelay", tostring(err)) end
end

--- Enables or disables keep-alive probes; `delay` is the idle time in seconds before the first.
---@param enabled boolean
---@param delay? number  default 60
function TcpStream:set_keepalive(enabled, delay)
  require_open(self, "set_keepalive")
  local ok, err = self._handle:keepalive(enabled, delay or DEFAULT_KEEPALIVE_DELAY)
  if not ok then uv_call.fail_transport("set_keepalive", tostring(err)) end
end

core.finalise(TcpStream)

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

--- Suspends until a connection arrives and returns it as a `TcpStream`. Cancelling keeps the
--- listener open; connections that arrive meanwhile stay queued. Connections are taken one
--- per call, so a slow acceptor leaves the rest in the kernel backlog (back-pressure).
---@async
---@return hecate.reactor.TcpStream
function TcpListener:accept()
  uv_call.begin("accept")
  require_open(self, "accept")
  if self._accepting then error(core.Error("accept: another task is already accepting"), 2) end
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
  local client = uv.new_tcp()
  local accepted, err = self._handle:accept(client)
  if not accepted then
    client:close()
    uv_call.fail_transport("accept", tostring(err))
  end
  self._incoming = self._incoming - 1
  local applied, apply_failure = pcall(apply_options, client, self._options)
  if not applied then
    client:close()
    error(apply_failure, 0)
  end
  return TcpStream(client, self._options)
end

--- Stops listening. Idempotent, never suspends; a task waiting in `accept` is woken with an
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

local M = { TcpStream = TcpStream, TcpListener = TcpListener }

--- Connects to a numeric address. Name resolution is not part of this call (a host name
--- raises `TransportError` `EINVAL`). Bound it with `reactor.deadline`; cancellation abandons the
--- attempt and closes its handle. Options: see `hecate.reactor.TcpOptions`.
---@async
---@param host string  numeric IPv4 or IPv6 address
---@param port integer
---@param options? hecate.reactor.TcpOptions
---@return hecate.reactor.TcpStream
function M.connect(host, port, options)
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
---@param host string  numeric IPv4 or IPv6 address
---@param port integer
---@param options? hecate.reactor.TcpListenOptions
---@return hecate.reactor.TcpListener
function M.listen(host, port, options)
  check_endpoint("tcp_listen", host, port)
  options = check_options("tcp_listen", options)
  uv_call.begin("tcp_listen")
  local handle = uv.new_tcp()
  local bound, bind_err = protected(handle.bind, handle, host, port)
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

return M
