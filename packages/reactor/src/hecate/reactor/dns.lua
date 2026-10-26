-- Name resolution as a suspending call over libuv `getaddrinfo` (concurrency.md, "Model":
-- transparent I/O; ADR 0002: luv is wrapped once, here). The request runs on libuv's thread
-- pool and cannot be withdrawn: a cancelled caller is released at once and the late result is
-- discarded (the request owns no handle, so nothing leaks).
global <const> type, error, require, pcall, tostring, ipairs, pairs

local core = require("hecate.core")
local uv = require("luv")
local uv_call = require("hecate.reactor.internal.uv_call")
local context = require("hecate.reactor.internal.context")

--- Options of `reactor.resolve`.
---@class hecate.reactor.ResolveOptions
---@field family? "inet"|"inet6"  restrict the answer to one address family; default both

--- A numeric address returned by `reactor.resolve`.
---@class hecate.reactor.ResolvedAddress
---@field ip string  numeric address
---@field family string  "inet" or "inet6"

-- Documented on `hecate.reactor` (module class completed here so that the LuaLS export lists the
-- function; coding-standards.md, "Annotations for the reference").

---@class hecate.reactor
local M = {}

--- Resolves `host` to numeric addresses, in the order the system resolver prefers. A numeric
--- address resolves to itself. Bound it with `reactor.deadline`.
---
--- Raises `hecate.reactor.TransportError` (`context.errno`, for example `EAI_NONAME`) when the name
--- does not resolve, and `hecate.core.ArgumentError` for a malformed host or option.
---@async
---@param host string  a host name or a numeric address
---@param options? hecate.reactor.ResolveOptions  `family` restricts the answer to one address family
---@return hecate.reactor.ResolvedAddress[] addresses  the distinct addresses, in resolver order
function M.resolve(host, options)
  if type(host) ~= "string" or host == "" then
    error(core.ArgumentError(("reactor.resolve: expects a host name, got %s"):format(tostring(host))), 2)
  end
  local family
  if options ~= nil then
    if type(options) ~= "table" then
      error(core.ArgumentError("reactor.resolve: expects an options table"), 2)
    end
    for key in pairs(options) do
      if key ~= "family" then
        error(core.ArgumentError(("reactor.resolve: unknown option %s"):format(tostring(key))), 2)
      end
    end
    family = options.family
    if family ~= nil and family ~= "inet" and family ~= "inet6" then
      error(core.ArgumentError('reactor.resolve: option family must be "inet" or "inet6"'), 2)
    end
  end
  uv_call.begin("reactor.resolve")
  local state = {}
  local ok, failure = pcall(context.suspend, function(wake)
    local started, err = uv.getaddrinfo(host, nil, { family = family, socktype = "stream" }, function(e, result)
      state.done, state.err, state.result = true, e, result
      wake()
    end)
    if not started then
      state.done, state.err = true, tostring(err)
      wake()
    end
  end)
  if not ok then error(failure, 0) end
  if state.err then uv_call.fail_transport("reactor.resolve", "resolve " .. host, state.err) end
  local addresses, seen = {}, {}
  for _, entry in ipairs(state.result or {}) do
    local key = entry.addr
    if key and not seen[key] then
      seen[key] = true
      addresses[#addresses + 1] = { ip = entry.addr, family = entry.family }
    end
  end
  if #addresses == 0 then uv_call.fail_transport("reactor.resolve", "resolve " .. host, "EAI_NONAME: no address") end
  return addresses
end

return M
