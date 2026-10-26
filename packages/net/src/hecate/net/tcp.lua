-- `net.connect` and `net.listen`: host names are resolved with `reactor.resolve`, then the
-- numeric address goes to the reactor transport (OQ-28, OQ-30, OQ-32). The net-level options
-- are validated here, before any resolution is paid for, so that a mistake names the net
-- function the caller used and not a reactor function reached after a DNS round trip.
global <const> require, type, error, pairs, ipairs, tostring, pcall, math, table

local core = require("hecate.core")
local reactor = require("hecate.reactor")
local TcpStream = require("hecate.net.tcp_stream")
local TcpListener = require("hecate.net.tcp_listener")
local dns = require("hecate.net.dns")

-- Documented on `hecate.net` (module class completed here so that the LuaLS export lists the
-- functions; coding-standards.md, "Annotations for the reference").

---@class hecate.net
local M = {}

-- The options each function accepts, in the order the error message lists them.
local CONNECT_OPTIONS = { "nodelay", "keepalive", "keepalive_delay", "family" }
local LISTEN_OPTIONS = { "nodelay", "keepalive", "keepalive_delay", "backlog", "reuseport", "family" }

--- Validates one net-level option value.
---@type table<string, fun(value: any): boolean, string>
local CHECKS = {
  nodelay = function(v) return type(v) == "boolean", "a boolean" end,
  keepalive = function(v) return type(v) == "boolean", "a boolean" end,
  keepalive_delay = function(v) return math.type(v) == "integer" and v > 0, "a positive integer number of seconds" end,
  backlog = function(v) return math.type(v) == "integer" and v > 0, "a positive integer" end,
  reuseport = function(v) return type(v) == "boolean", "a boolean" end,
  family = function(v) return v == "inet" or v == "inet6", '"inet" or "inet6"' end,
}

--- Validates the host and the options of `name` and splits the `family` option (net-level) from the
--- transport options (reactor-level).
---@param name string  the net function, for messages
---@param host any
---@param options any
---@param allowed string[]
---@return table transport
---@return string? family
local function split_options(name, host, options, allowed)
  if type(host) ~= "string" or host == "" then
    error(core.ArgumentError(("%s: expects a host name or address, got %s"):format(name, tostring(host))), 3)
  end
  if options == nil then return {}, nil end
  if type(options) ~= "table" then
    error(core.ArgumentError(("%s: expects an options table, got %s"):format(name, type(options))), 3)
  end
  local known = {}
  for _, key in ipairs(allowed) do known[key] = true end
  local transport = {}
  for key, value in pairs(options) do
    if not known[key] then
      error(core.ArgumentError(("%s: unknown option %s (options: %s)"):format(
        name, tostring(key), table.concat(allowed, ", "))), 3)
    end
    local valid, expected = CHECKS[key](value)
    if not valid then
      error(core.ArgumentError(("%s: option %s must be %s, got %s"):format(name, key, expected, tostring(value))), 3)
    end
    if key ~= "family" then transport[key] = value end
  end
  return transport, options.family
end

--- Validates a port before any resolution is paid for.
---@param name string
---@param port any
local function check_port(name, port)
  if math.type(port) ~= "integer" or port < 0 or port > 65535 then
    error(core.ArgumentError(("%s: expects a port in 0..65535, got %s"):format(name, tostring(port))), 3)
  end
end

---@param host string
---@param port integer
---@return string
local function endpoint(host, port)
  if host:find(":", 1, true) then return ("[%s]:%d"):format(host, port) end
  return ("%s:%d"):format(host, port)
end

-- libuv reports some failures as a bare name; these are the usual ones of connect and listen.
local DESCRIPTIONS = {
  ECONNREFUSED = "connection refused",
  ECONNRESET = "connection reset by peer",
  ETIMEDOUT = "connection timed out",
  ENETUNREACH = "network is unreachable",
  EHOSTUNREACH = "host is unreachable",
  EADDRINUSE = "address already in use",
  EADDRNOTAVAIL = "address not available",
  EACCES = "permission denied",
}

--- The part of a transport failure message after its operation: `ECONNREFUSED connection refused`.
---@param failure hecate.core.Error
---@return string
local function describe(failure)
  local text = failure.message or tostring(failure)
  local operation = failure.context and failure.context.operation
  if operation and text:sub(1, #operation + 2) == operation .. ": " then text = text:sub(#operation + 3) end
  local name, rest = text:match("^(%u[%u%d_]*):%s*(.*)$")
  if name == nil and text:match("^%u[%u%d_]*$") then name, rest = text, "" end
  if name == nil then return text end
  if rest == "" then rest = DESCRIPTIONS[name] or "" end
  return rest == "" and name or (name .. " " .. rest)
end

--- Rebuilds a transport failure with a message that names the endpoint, keeping its class, its
--- `context.errno` and `context.operation`, and setting `cause`.
---@param failure hecate.core.Error
---@param action string  for example "connect to example.org:80"
---@param extra table  more context
---@param suffix? string
---@return hecate.core.Error
local function rewrap(failure, action, extra, suffix)
  local context = {}
  for key, value in pairs(failure.context or {}) do context[key] = value end
  for key, value in pairs(extra) do context[key] = value end
  return reactor.TransportError({
    message = ("%s failed: %s%s"):format(action, describe(failure), suffix or ""),
    context = context,
    cause = failure,
  })
end

--- Connects to `host:port`. A host name is resolved first and its addresses are tried in the
--- resolver's order until one connects (no parallel attempts, OQ-32). Options: `nodelay` (default
--- true), `keepalive` (default false), `keepalive_delay` (positive integer, seconds, default 60),
--- `family` (`"inet"` or `"inet6"`). There is no timeout option: bound the whole call, resolution
--- included, with `reactor.deadline(seconds, net.connect, host, port)`.
---
--- Raises `hecate.reactor.TransportError` (the last failure, rewrapped with the endpoint in its
--- message, `context.host`, `context.port`, the `context.errno` of the failure and its `cause`)
--- when no address connects. `context.attempts` lists `{ address, errno }` of every attempt (the
--- first failures are otherwise lost). A malformed host, port or option raises
--- `hecate.core.ArgumentError` before anything is resolved. Cancellation, and a deadline, propagate
--- at once instead of trying the next address.
---@async
---@param host string  host name or numeric address
---@param port integer  TCP port
---@param options? hecate.reactor.TcpOptions | { family?: "inet"|"inet6" }  transport options and address family
---@return hecate.net.TcpStream stream  the connected stream
function M.connect(host, port, options)
  local transport, family = split_options("connect", host, options, CONNECT_OPTIONS)
  check_port("connect", port)
  local addresses = dns.resolve(host, { family = family })
  ---@type hecate.core.Error?
  local last
  local attempts = {}
  local tried = {}
  for i = 1, #addresses do
    local ok, result = pcall(reactor.connect_tcp, addresses[i].ip, port, transport)
    if ok then return TcpStream(result) end
    -- Only a failed attempt moves on to the next address; cancellation and misuse propagate.
    if not core.is_instance_of(result, reactor.TransportError) then error(result, 0) end
    local failure = result --[[@as hecate.core.Error]]
    attempts[#attempts + 1] = { address = addresses[i].ip, errno = failure.context and failure.context.errno }
    tried[#tried + 1] = addresses[i].ip
    last = failure
  end
  ---@cast last hecate.core.Error
  error(rewrap(last, "connect to " .. endpoint(host, port), { host = host, port = port, attempts = attempts },
    #tried > 1 and (" (tried %s)"):format(table.concat(tried, ", ")) or nil), 0)
end

--- Binds and listens on `host:port` (port 0 picks a free port, see `TcpListener:local_address`).
--- A host name is resolved and only its first address is bound: `listen("localhost", ...)` listens
--- on whichever of `127.0.0.1` and `::1` the resolver lists first. Pass a numeric address, or the
--- `family` option, when the address matters. Suspends only for the resolution.
--- Options: those of `connect` plus `backlog` (default 128) and `reuseport`
--- (see `reactor.supports_reuseport`).
---
--- Raises `hecate.reactor.TransportError` when the name does not resolve or binding or listening
--- fails (the message names the endpoint, `context.errno` is the libuv name, `cause` the original
--- failure), and `hecate.core.ArgumentError` for a malformed host, port or option.
---@async
---@param host string  host name or numeric address
---@param port integer  TCP port; 0 picks a free port
---@param options? hecate.reactor.TcpListenOptions | { family?: "inet"|"inet6" }  transport options, backlog and address family
---@return hecate.net.TcpListener listener  the listening socket
function M.listen(host, port, options)
  local transport, family = split_options("listen", host, options, LISTEN_OPTIONS)
  check_port("listen", port)
  local addresses = dns.resolve(host, { family = family })
  local ok, result = pcall(reactor.listen_tcp, addresses[1].ip, port, transport)
  if ok then return TcpListener(result) end
  if not core.is_instance_of(result, reactor.TransportError) then error(result, 0) end
  error(rewrap(result --[[@as hecate.core.Error]], "listen on " .. endpoint(host, port), { host = host, port = port }), 0)
end

return M
