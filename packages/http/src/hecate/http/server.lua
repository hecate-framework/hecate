-- The HTTP/1.1 server over hecate.net streams (RFC 9110, RFC 9112; ADR 0003; ADR 0019).
--
-- Shape: `serve` accepts connections in a scope; each connection is one computation of that scope, and each request
-- one scope of its own with one computation running the action (concurrency.md, "Structured concurrency"). A
-- connection serves its requests one after the other, so the responses of pipelined requests come in request order
-- (RFC 9112, section 9.3.2). The parser is fed chunks of at most READ_SIZE bytes and closed when the connection ends.
--
-- The work is split into internal modules (not public API): `internal/server_options` (validation), `internal/server_response`
-- (the response writer) and `internal/server_connection` (reading, requests, connections). This file keeps the public
-- class, the accept loop and the lifecycle.
global <const> require, type, error, pcall, pairs, math, string, tostring

local core = require("hecate.core")
local reactor = require("hecate.reactor")
local net = require("hecate.net")
local log = require("hecate.log")
local server_options = require("hecate.http.internal.server_options")
local connection = require("hecate.http.internal.server_connection")

local run_connection = connection.run_connection

---@return boolean
local function is_cancellation(err) return core.is_instance_of(err, core.CancellationError) end
local function is_deadline(err) return core.is_instance_of(err, core.DeadlineExceededError) end

--- Options of the server. Every limit has a safe default; a server never runs unbounded.
---@class hecate.http.ServerOptions
---@field host? string  a NUMERIC address, IPv4 or IPv6, for `listen` (default "127.0.0.1": the loopback interface only); a name is refused
---@field port? integer  0 to 65535 for `listen`; 0 picks a free port (default 8080)
---@field backlog? integer  pending connections the kernel queues (default 128)
---@field max_connections? integer  connections served at once (default: no limit; an integer limits, and the others wait in the backlog)
---@field max_content? integer  bytes of request content (default 1048576; over it: 413)
---@field head_timeout? number  seconds to receive a request head once its first byte arrived (default 60; counted from the first byte of the head to its end, not between reads; then 408)
---@field idle_timeout? number  seconds a connection may wait for the next request (default 75; then closed silently)
---@field content_timeout? number  seconds between two reads of request content (default 60; a timeout between two reads, not a limit on the whole content; then 408)
---@field request_timeout? number  seconds from the end of a head to the last byte of its content (default 300; then 408); `content_timeout` still applies between reads
---@field drain_timeout? number  seconds to drain content the action left unread after the response (default 5; then the connection closes)
---@field write_timeout? number  seconds a write to the client may take (default 60; then the connection is closed)
---@field parser? hecate.http.parser.Options  limits of the message parser (target, field, head size, field count)
---@field tls? hecate.net.TlsServerOptions|hecate.net.TlsServerConfig  serve HTTPS: the options of `net.tls.server_config` (ALPN defaults to `http/1.1`), or a configuration built by it
---@field handshake_timeout? number  seconds a TLS handshake may take (default 10; the connection is dropped); needs `tls`
---@field max_handshakes? integer  TLS handshakes in progress at once (default 64); the other connections wait in the backlog; needs `tls`
---@field max_handshake_bytes? integer  bytes read from a client during its handshake (default 65536; over it the connection is dropped); needs `tls`
---@field logger? hecate.log.Logger  receives everything the server logs: an unhandled error of an action (`error`), the listening address, the failed handshakes with the peer address, accept failures (default: `log.default()`, OQ-79; an explicit logger replaces it)
---@field on_error? fun(err: any)  called with the failure of an action or a connection (the client only sees generic problem details)

--- Defaults of the settings, exported so that documentation and tests read one source.
--- The defaults of the server's settings. Settings without an entry have no default value: `max_connections` (no limit; the
--- process descriptor limit and the timeouts bound it), `tls` (plain HTTP), `parser` (the parser's own limits), `logger`
--- (`log.default()`) and `on_error` (none).
---@class hecate.http.ServerDefaults
---@field host string
---@field port integer
---@field backlog integer
---@field max_content integer
---@field head_timeout number
---@field idle_timeout number
---@field content_timeout number
---@field write_timeout number
---@field request_timeout number
---@field drain_timeout number
---@field handshake_timeout number
---@field max_handshakes integer
---@field max_handshake_bytes integer

---@type hecate.http.ServerDefaults
local DEFAULTS <const> = {
  host = "127.0.0.1",
  port = 8080,
  backlog = 128,
  -- max_connections: absent, no limit (the file-descriptor limit of the process and the timeouts bound the resource)
  max_content = 1048576,
  head_timeout = 60,
  idle_timeout = 75,
  content_timeout = 60,
  write_timeout = 60,
  request_timeout = 300,
  drain_timeout = 5,
  handshake_timeout = 10,
  max_handshakes = 64,
  max_handshake_bytes = 65536,
}

--- An HTTP/1.1 server: `serve` accepts connections from a listener and answers each request with the action.
---@class hecate.http.Server
---@field DEFAULTS hecate.http.ServerDefaults  the defaults of the settings
---@overload fun(action: (fun(request: hecate.http.Request): hecate.http.Response), options?: hecate.http.ServerOptions): hecate.http.Server
local Server = core.class("Server")
Server.DEFAULTS = DEFAULTS

--- Creates a server; nothing is bound until `listen` or `serve`.
---
--- Raises `hecate.core.ArgumentError` for an action that is not a function, an unknown or invalid option, or a host
--- that is not a numeric address (a name would bind every address the resolver lists, networking.md "TCP").
---@param action fun(request: hecate.http.Request): hecate.http.Response  runs in its own scope, once per request; it returns a `Response` whose content is nil, a string or a function (a table is an error: the generic 500 problem details response and a log entry, `hecate.http.dispatch`)
---@param options? hecate.http.ServerOptions
function Server:init(action, options)
  local settings = server_options.validate(action, options, DEFAULTS)
  self._host = settings.host
  self._port = settings.port
  self._backlog = settings.backlog
  self._max_connections = settings.max_connections
  self._max_content = settings.max_content
  self._head_timeout = settings.head_timeout
  self._idle_timeout = settings.idle_timeout
  self._content_timeout = settings.content_timeout
  self._write_timeout = settings.write_timeout
  self._request_timeout = settings.request_timeout
  self._drain_timeout = settings.drain_timeout
  self._handshake_timeout = settings.handshake_timeout
  self._max_handshakes = settings.max_handshakes
  self._max_handshake_bytes = settings.max_handshake_bytes
  self._logger = settings.logger
  self._tls = settings.tls
  self._limits = settings.limits
  self._on_error = settings.on_error
  self._action = settings.action
  self._handshaking = {}
  self._handshakes = reactor.Semaphore(self._max_handshakes)
  self._listener = nil
  self._connections = {}
  self._stopping = false
  self._forced = false
  self._scope = nil
  self._accepting = nil
  self._serving = false
  self._slots = self._max_connections ~= nil and reactor.Semaphore(self._max_connections) or nil -- nil: no limit
  self._finished = reactor.Semaphore(0)
end

--- Reports a failure to `on_error` (an error of that function is discarded).
---@param message string
---@param err any
function Server:_report(message, err)
  local report = self._on_error
  if report ~= nil then
    pcall(report, core.is_instance_of(err, core.Error) and err or core.Error({ message = message .. ": " .. tostring(err) }))
  end
end

--- Logs through the `logger` option, or through `log.default()` (OQ-79) when none was given. Logging never raises.
---@param severity string
---@param message string
---@param fields? table
function Server:_log(severity, message, fields)
  local logger = self._logger or log.default()
  pcall(logger.log, logger, severity, message, fields)
end

--- The address the server listens on, `{ ip, port, family }`, or nil when it is not serving.
---@return hecate.reactor.SocketAddress?
function Server:local_address()
  return self._listener and self._listener:local_address() or nil
end

--- Whether `shutdown` was called (public: a kernel can refuse new work while the server drains). There is no `Server:close()`:
--- stopping suspends (it waits for the requests in flight), so the only stop is `shutdown`, which a `<close>` scope cannot do.
---@return boolean
function Server:is_stopping() return self._stopping end

---@async
local function accept_loop(self, scope)
  local listener = self._listener
  local failures = 0 -- consecutive accept failures: a burst
  while not self._stopping do
    if self._slots ~= nil then self._slots:acquire() end
    -- A handshake slot is taken before accepting: past the limit, connections wait in the kernel backlog.
    if self._tls ~= nil then self._handshakes:acquire() end
    local ok, stream = pcall(listener.accept, listener)
    if not ok then
      if self._slots ~= nil then self._slots:release() end
      if self._tls ~= nil then self._handshakes:release() end
      if self._stopping or is_cancellation(stream) or listener:is_closed() then return end
      -- Descriptor exhaustion (EMFILE, ENFILE) or another accept failure: existing connections keep serving, the
      -- loop backs off (50 ms, doubling to 1 s) instead of spinning, and the burst is reported once.
      failures = failures + 1
      if failures == 1 then
        local failure = stream --[[@as table]]
        local errno = failure.context and failure.context.errno or "error"
        self:_log("warning", "http.Server: accept failed", { reason = tostring(errno) })
        self:_report("accept failed", stream)
      end
      reactor.sleep(math.min(0.05 * 2 ^ (failures - 1), 1))
    else
      failures = 0
      scope:fork(run_connection, self, stream)
    end
  end
end

--- Binds the listening socket on the `host`, `port` and `backlog` options (suspends for the bind only) and returns
--- the listener. The default host is the numeric loopback address: serving every interface is an explicit choice
--- (`host = "0.0.0.0"` or `"::"`). Pass the listener to `serve`, or let `serve` call this.
---
--- Raises `hecate.reactor.TransportError` when the address cannot be bound.
---@async
---@return hecate.net.TcpListener
function Server:listen()
  return net.listen(self._host, self._port, { backlog = self._backlog })
end

--- Accepts connections from `listener` (bound by `listen` when omitted) and serves them until `shutdown` completes.
--- Each connection is a computation of an internal scope that ends only when every connection and request has ended;
--- a failure of a connection closes that connection only. Returns once every connection has ended.
---
--- Raises `hecate.core.ArgumentError` when already serving, a `TransportError` when binding fails, and the
--- cancellation of the caller.
---@async
---@param listener? hecate.net.TcpListener  any net listener whose `accept` returns a stream with `reader`, `writer`, `shutdown` and `close` (a `PipeListener` is expected to work and is not tested)
function Server:serve(listener)
  if self._serving then error(core.ArgumentError("http.Server:serve: the server is already serving; call shutdown first"), 2) end
  listener = listener or self:listen()
  self._listener = listener
  self._serving = true
  local known, address = pcall(listener.local_address, listener)
  if known and type(address) == "table" then
    local loopback = address.ip == "127.0.0.1" or address.ip == "::1"
    self:_log("informational",
      ("http.Server: listening on %s:%s%s"):format(tostring(address.ip), tostring(address.port), loopback and " (loopback only)" or ""),
      { hint = loopback and 'a container or another machine reaches the server only with host = "0.0.0.0" (or "::")' or nil })
  end
  local ok, err = pcall(reactor.scope, function(scope)
    self._scope = scope
    if self._stopping then return end
    self._accepting = scope:fork(accept_loop, self, scope)
  end)
  listener:close()
  self._serving = false
  self._finished:release()
  if not ok and not (self._forced and is_cancellation(err)) then error(err, 0) end
end

---@async
local function wait_finished(self)
  self._finished:acquire()
  self._finished:release() -- the next waiter
end

--- Stops accepting, closes the connections that wait for a request, lets the requests in flight finish (each answer
--- carries `Connection: close`), and returns when `serve` has returned. When `grace_timeout` seconds pass first, the
--- remaining requests are cancelled (the grace period of ADR 0023). Calling it again waits for the same end.
---
--- Raises `hecate.core.ArgumentError` for a `grace_timeout` that is not a non-negative finite number of seconds.
---@async
---@param grace_timeout? number  seconds to let requests finish (default 30)
function Server:shutdown(grace_timeout)
  if grace_timeout == nil then grace_timeout = 30 end
  if type(grace_timeout) ~= "number" or grace_timeout ~= grace_timeout or grace_timeout < 0 or grace_timeout == math.huge then
    error(core.ArgumentError("http.Server:shutdown: grace_timeout must be a non-negative finite number of seconds"), 2)
  end
  if not self._stopping then
    self._stopping = true
    if self._accepting ~= nil then self._accepting:cancel() end
    if self._listener ~= nil then self._listener:close() end
    for conn in pairs(self._connections) do
      if conn.waiting then conn.stream:close() end
    end
    for limited in pairs(self._handshaking) do limited:close() end
  end
  if not self._serving then return end
  local ok, err = pcall(reactor.deadline, grace_timeout, wait_finished, self)
  if ok then return end
  if not is_deadline(err) then error(err, 0) end
  self._forced = true
  self._scope:cancel()
  reactor.deadline(5, wait_finished, self)
end

return core.finalise(Server)
