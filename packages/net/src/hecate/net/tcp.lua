-- `net.connect` and `net.listen`: host names are resolved with `reactor.resolve`, then the
-- numeric address goes to the reactor transport (OQ-28, OQ-30, OQ-32).
global <const> require, type, error, pairs, tostring, pcall, table

local core = require("hecate.core")
local reactor = require("hecate.reactor")
local TcpStream = require("hecate.net.tcp_stream")
local TcpListener = require("hecate.net.tcp_listener")

-- Documented on `hecate.net` (module class completed here so that the LuaLS export lists the
-- functions; coding-standards.md, "Annotations for the reference").

---@class hecate.net
local M = {}

--- Splits the `family` option (net-level) from the transport options (reactor-level).
---@param name string
---@param host any
---@param options any
---@return table transport
---@return string? family
local function split_options(name, host, options)
  if type(host) ~= "string" or host == "" then
    error(core.ArgumentError(("%s expects a host name or address, got %s"):format(name, tostring(host))), 3)
  end
  if options == nil then return {}, nil end
  if type(options) ~= "table" then
    error(core.ArgumentError(("%s expects an options table, got %s"):format(name, type(options))), 3)
  end
  local transport = {}
  for key, value in pairs(options) do
    if key ~= "family" then transport[key] = value end
  end
  return transport, options.family
end

--- Connects to `host:port`. A host name is resolved first and its addresses are tried in the
--- resolver's order until one connects (no parallel attempts, OQ-32). Options: `nodelay` (default
--- true), `keepalive` (default false), `keepalive_delay`, `family` (`"inet"` or `"inet6"`). There is
--- no timeout option: bound the whole call, resolution included, with
--- `reactor.deadline(seconds, net.connect, host, port)`.
---
--- Raises `hecate.reactor.TransportError` (the last one) when no address connects, and
--- `hecate.core.ArgumentError` for a malformed host, port or option.
---@async
---@param host string  host name or numeric address
---@param port integer  TCP port
---@param options? hecate.reactor.TcpOptions | { family?: "inet"|"inet6" }  transport options and address family
---@return hecate.net.TcpStream stream  the connected stream
function M.connect(host, port, options)
  local transport, family = split_options("connect", host, options)
  local addresses = reactor.resolve(host, { family = family })
  local last
  for i = 1, #addresses do
    local ok, result = pcall(reactor.tcp_connect, addresses[i].ip, port, transport)
    if ok then return TcpStream(result) end
    -- Only a failed attempt moves on to the next address; cancellation and misuse propagate.
    if not core.is_instance_of(result, reactor.TransportError) then error(result, 0) end
    last = result
  end
  error(last, 0)
end

--- Binds and listens on `host:port` (port 0 picks a free port, see `TcpListener:local_address`).
--- A host name is resolved and its first address is used. Suspends only for the resolution.
--- Options: those of `connect` plus `backlog` (default 128).
---
--- Raises `hecate.reactor.TransportError` when the name does not resolve or binding or listening
--- fails, and `hecate.core.ArgumentError` for a malformed host, port or option.
---@async
---@param host string  host name or numeric address
---@param port integer  TCP port; 0 picks a free port
---@param options? hecate.reactor.TcpListenOptions | { family?: "inet"|"inet6" }  transport options, backlog and address family
---@return hecate.net.TcpListener listener  the listening socket
function M.listen(host, port, options)
  local transport, family = split_options("listen", host, options)
  local addresses = reactor.resolve(host, { family = family })
  return TcpListener(reactor.tcp_listen(addresses[1].ip, port, transport))
end

return M
