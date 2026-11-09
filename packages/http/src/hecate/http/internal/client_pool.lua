-- The pool of connections of the client: one entry per origin with its idle connections and its leases, the checks that a
-- pooled connection is still usable, the sweep of expired ones and the bound on idle connections.
-- Internal to `hecate.http`: not public API. Only `client.lua` and the other `internal/client_*` modules require it.
-- Every function takes the client (`self`) first: it reads the settings and the `_origins` table of the client.
global <const> require, pcall, pairs, ipairs, error, math, table

local core = require("hecate.core")
local reactor = require("hecate.reactor")
local net = require("hecate.net")
local Parser = require("hecate.http.parser")
local connections = require("hecate.http.internal.client_connection")

local discard, remaining, bounded = connections.discard, connections.remaining, connections.bounded

---@class hecate.http.internal.client_pool
local M = {}

---@return table
---@param self hecate.http.Client
function M.tls_client_config(self)
  if self._tls_config == nil then
    local config = {}
    for key, value in pairs(self._tls_options or {}) do config[key] = value end
    config.alpn = { "http/1.1" }
    self._tls_config = net.tls.client_config(config)
  end
  return self._tls_config
end

---@async
---@param self hecate.http.Client
function M.connect(self, parts, state)
  local seconds = bounded(state, self._connect_timeout)
  local stream
  if parts.scheme == "https" then
    local config = M.tls_client_config(self)
    stream = reactor.deadline(seconds, net.connect_tls, parts.host, parts.port, {
      tls_config = config, handshake_timeout = math.max(seconds, 0.001),
    })
  else
    stream = reactor.deadline(seconds, net.connect, parts.host, parts.port)
  end
  return {
    stream = stream, parser = Parser.response(self._limits), queue = {}, position = 1, tail = 0, eof = false,
    received = 0, last_used = reactor.now(), reusable = true,
  }
end

local function origin_of(self, origin)
  local entry = self._origins[origin]
  if entry == nil then
    entry = { idle = {}, leases = reactor.Semaphore(self._max_per_origin) }
    self._origins[origin] = entry
  end
  return entry
end

--- A pooled connection is usable when it is open, has not idled too long, and nothing arrived on it (a closed peer shows
--- as the end of stream; bytes nobody asked for are a protocol violation). It tries a read that expires at once, so it
--- belongs to the computations that may suspend.
---@async
local function alive(self, conn)
  if conn.stream:is_closed() or conn.eof or conn.failure ~= nil then return false end
  if reactor.now() - conn.last_used > self._idle_timeout then return false end
  if conn.tail >= conn.position or conn.parser:in_message() then return false end -- bytes nobody asked for
  local ok, chunk = pcall(reactor.deadline, 0, conn.stream.read, conn.stream, 1)
  if ok then return false end -- the end of the stream, or stray bytes
  return core.is_instance_of(chunk, core.DeadlineExceededError) -- nothing arrived: alive
end

local sweep -- defined below, with the pool's other bookkeeping

--- Takes a lease on the origin (waits when `max_connections_per_origin` are leased), then a pooled connection or a new one.
---@async
---@return hecate.http.client.Connection conn
---@return boolean reused
---@param self hecate.http.Client
function M.checkout(self, parts, state)
  sweep(self)
  local entry = origin_of(self, parts.origin)
  local wait = remaining(state)
  if wait == math.huge then
    entry.leases:acquire()
  else
    reactor.deadline(math.max(0, wait), entry.leases.acquire, entry.leases)
  end
  local ok, conn, reused = pcall(function()
    while #entry.idle > 0 do
      local candidate = table.remove(entry.idle)
      if alive(self, candidate) then return candidate, true end
      discard(candidate)
    end
    return self:_connect(parts, state), false
  end)
  if not ok then
    entry.leases:release()
    error(conn, 0)
  end
  conn.origin, conn.lease_entry = parts.origin, entry
  return conn, reused
end

--- Closes the idle connections that expired or were closed, in every origin; forgets the origins that have no idle
--- connection and no lease; then closes the least recently used idle connections beyond `max_idle_connections`.
function sweep(self)
  local now, count = reactor.now(), 0
  for origin, entry in pairs(self._origins) do
    local keep = {}
    for _, conn in ipairs(entry.idle) do
      if now - conn.last_used > self._idle_timeout or conn.stream:is_closed() or conn.dead then discard(conn) else keep[#keep + 1] = conn end
    end
    entry.idle = keep
    count = count + #keep
    if #keep == 0 and entry.leases:available() == self._max_per_origin and entry.leases:waiting() == 0 then
      self._origins[origin] = nil
    end
  end
  while count > self._max_idle do
    local oldest, holder
    for _, entry in pairs(self._origins) do
      for _, conn in ipairs(entry.idle) do
        if oldest == nil or conn.last_used < oldest.last_used then oldest, holder = conn, entry end
      end
    end
    if oldest == nil then break end
    for i, conn in ipairs(holder.idle) do
      if conn == oldest then table.remove(holder.idle, i) break end
    end
    discard(oldest)
    count = count - 1
  end
end

--- Returns a connection after its response was read: pooled when reusable, dropped otherwise; releases the lease.
local function checkin(self, conn)
  local entry = conn.lease_entry
  conn.lease_entry = nil
  if entry == nil then return end
  conn.last_used = reactor.now()
  if conn.reusable and not self._closed and not conn.dead and not conn.eof and conn.failure == nil and conn.tail < conn.position
    and not conn.parser:in_message() then
    entry.idle[#entry.idle + 1] = conn
  else
    discard(conn)
  end
  entry.leases:release()
  sweep(self)
end

--- The size of the pool: `idle` connections and the `origins` it keeps an entry for.
---@return { idle: integer, origins: integer }
---@param self hecate.http.Client
function M.stats(self)
  local idle, origins = 0, 0
  for _, entry in pairs(self._origins) do
    idle = idle + #entry.idle
    origins = origins + 1
  end
  return { idle = idle, origins = origins }
end

local function drop(conn)
  local entry = conn.lease_entry
  conn.lease_entry = nil
  discard(conn)
  if entry ~= nil then entry.leases:release() end
end

--- Closes the idle connections of every origin (the `close` of the client).
---@param self hecate.http.Client
function M.close_idle(self)
  for _, entry in pairs(self._origins) do
    for _, conn in ipairs(entry.idle) do discard(conn) end
    entry.idle = {}
  end
end

M.checkin = checkin
M.drop = drop

return M
