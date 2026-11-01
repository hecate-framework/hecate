-- TcpListener: accepts `TcpStream`s over one reactor TCP listener per bound address (OQ-28, OQ-32 (3)).
global <const> require, ipairs, pcall, error, table, type

local core = require("hecate.core")
local reactor = require("hecate.reactor")
local TcpStream = require("hecate.net.tcp_stream")

---@param operation string
---@return hecate.core.NetworkError
local function closed_error(operation)
  return reactor.TransportError({
    message = "net.TcpListener." .. operation .. ": EBADF: the listener is closed",
    context = { operation = operation, errno = "EBADF" },
  })
end

---@param operation string
local function raise_closed(operation) error(closed_error(operation), 0) end

--- A listening TCP socket that accepts `TcpStream`s. A host name that resolves to several addresses
--- gives one socket per address, on one port; `accept` takes the next connection from any of them.
---@class hecate.net.TcpListener
---@overload fun(inner: hecate.reactor.TcpListener | hecate.reactor.TcpListener[]): hecate.net.TcpListener
local TcpListener = core.class("TcpListener")

--- Wraps one reactor listener, or several (one per address, same port), which this listener owns from
--- now on. Prefer `net.listen`.
---@param inner hecate.reactor.TcpListener | hecate.reactor.TcpListener[]
---@private
function TcpListener:init(inner)
  local sockets = inner[1] ~= nil and inner or { inner }
  for _, socket in ipairs(sockets) do
    ---@diagnostic disable-next-line: inject-field  -- the reactor listener names this class in its messages
    socket._label = "net.TcpListener"
  end
  self._sockets = sockets
  self._pending_failure = nil -- an accept failure that came next to a connection, raised by the next `accept`
  self._ready = {} -- connections taken from another socket than the one that won an `accept`
end

--- Waits for a connection on every socket and returns the first. The other sockets are cancelled
--- inside a scope that ends only when they are done, so a connection one of them had already
--- taken is kept for the next `accept`, also when this call itself is cancelled.
---@async
---@return hecate.reactor.TcpStream
---@private
function TcpListener:_accept_any()
  local taken, failures = {}, {}
  local ok, err = pcall(reactor.scope, function(scope)
    local futures = {}
    for i, socket in ipairs(self._sockets) do
      futures[i] = scope:fork(function()
        local accepted, result = pcall(socket.accept, socket)
        if accepted then
          taken[#taken + 1] = result
        elseif not core.is_instance_of(result, core.CancellationError) then
          failures[#failures + 1] = result
        end
      end)
    end
    reactor.select(table.unpack(futures))
    for _, future in ipairs(futures) do future:cancel() end
  end)
  local first = table.remove(taken, 1)
  if self._sockets[1]:is_closed() then
    -- Closed while this call ran: nobody will take these connections, so none may leak.
    if first then first:close() end
    for _, stream in ipairs(taken) do stream:close() end
    if not ok then error(err, 0) end
    error(failures[1] or closed_error("accept"), 0)
  end
  local ready = self._ready
  for _, stream in ipairs(taken) do ready[#ready + 1] = stream end
  -- An accept failure (EMFILE, ECONNABORTED) next to a connection is kept for the next `accept`.
  if first and failures[1] then self._pending_failure = failures[1] end
  if not ok then
    if first then table.insert(ready, 1, first) end
    error(err, 0)
  end
  if first then return first end
  error(failures[1], 0)
end

--- Suspends until a connection arrives. Cancelling keeps the listener open and the queued
--- connections. With one socket, connections are taken one per call, so a slow acceptor leaves the rest in the
--- kernel backlog (back-pressure); with several sockets, connections that completed together are
--- queued in the listener and returned by the next calls. An accept failure that came with a connection
--- (`EMFILE`, `ECONNABORTED`) is raised by the next call. Raises `TransportError` (`EBADF`,
--- `context.operation` `accept`) when the listener is closed.
---@async
---@return hecate.net.TcpStream
function TcpListener:accept()
  if self:is_closed() then raise_closed("accept") end
  local pending = self._pending_failure
  if pending then
    self._pending_failure = nil
    error(pending, 0)
  end
  local ready = self._ready
  if #ready > 0 then return TcpStream(table.remove(ready, 1)) end
  if #self._sockets == 1 then return TcpStream(self._sockets[1]:accept()) end
  return TcpStream(self:_accept_any())
end

--- Stops listening on every socket. Idempotent, never suspends; a coroutine waiting in `accept` fails with
--- `TransportError` (`ECANCELED`). Accepted streams are unaffected; connections that were taken but
--- not yet returned by `accept` are closed.
function TcpListener:close()
  for _, socket in ipairs(self._sockets) do socket:close() end
  for _, stream in ipairs(self._ready) do stream:close() end
  self._ready = {}
  self._pending_failure = nil
end

--- Closes at the end of a `<close>` scope.
function TcpListener:__close() self:close() end

--- Returns whether the listener is closed.
---@return boolean
function TcpListener:is_closed() return self._sockets[1]:is_closed() end

--- Address the listener is bound to (use it to learn the port chosen for port 0). With several
--- sockets, the address of the first one (the first the resolver listed); the port is the same.
---@return hecate.reactor.SocketAddress
function TcpListener:local_address() return self._sockets[1]:local_address() end

return core.finalise(TcpListener)
