-- Validation of the options of `hecate.http.Server`: the known keys, the checks and the settings `Server:init` stores.
-- Internal to `hecate.http`: not public API, and not part of the stable surface (ADR 0001). Only `server.lua` requires it.
global <const> require, type, error, pairs, ipairs, math, string

local core = require("hecate.core")
local net = require("hecate.net")
local Parser = require("hecate.http.parser")
local option_text = require("hecate.http.options")

---@class hecate.http.internal.server_options
local M = {}

local KNOWN <const> = {
  host = true, port = true, backlog = true, max_connections = true, max_content = true, head_timeout = true,
  idle_timeout = true, content_timeout = true, request_timeout = true, drain_timeout = true, write_timeout = true, parser = true, on_error = true,
  tls = true, handshake_timeout = true, max_handshakes = true, max_handshake_bytes = true, logger = true,
}

---@param host string
---@return boolean
local function is_numeric_address(host)
  local a, b, c, d = string.match(host, "^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
  if a then
    for _, octet in ipairs({ a, b, c, d }) do
      if #octet > 3 or math.tointeger(octet) > 255 then return false end
    end
    return true
  end
  return string.find(host, ":", 1, true) ~= nil and string.find(host, "^[%x:%.]+$") ~= nil
end

local function bad(name, expected, value)
  error(core.ArgumentError(("http.Server: invalid %s %s: expected %s"):format(name, option_text.show(value), expected)), 5)
end

--- Validates `action` and `options` and returns the settings `Server:init` stores (a field `_x` of the server is the key
--- `x` here). Raises `hecate.core.ArgumentError`; the error levels count the frame of this function, so that the
--- message still points at the caller of `Server(...)`.
---@param action any
---@param options any
---@param DEFAULTS hecate.http.ServerDefaults
---@return table settings
function M.validate(action, options, DEFAULTS)
  local settings = {}
  if type(action) ~= "function" then error(core.ArgumentError("http.Server: the action must be a function"), 4) end
  options = options or {}
  if type(options) ~= "table" then error(core.ArgumentError("http.Server: options must be a table"), 4) end
  for key in pairs(options) do
    if not KNOWN[key] then error(core.ArgumentError(option_text.unknown("http.Server", key, KNOWN)), 4) end
  end
  local host = options.host
  if host == nil then host = DEFAULTS.host end
  if type(host) ~= "string" or not is_numeric_address(host) then
    bad("host", "a numeric address. Use \"127.0.0.1\" (this machine only), \"0.0.0.0\" (every IPv4 interface) or \"::\" (every IPv6 interface); a name would bind every address it resolves to", host)
  end
  ---@return integer
  local function integer(name, minimum, maximum)
    local value = options[name]
    if value == nil then return DEFAULTS[name] --[[@as integer]] end
    if math.type(value) ~= "integer" or value < minimum or value > maximum then
      bad(name, ("an integer from %d to %d"):format(minimum, maximum), value)
    end
    return value
  end
  ---@return number
  local function seconds(name)
    local value = options[name]
    if value == nil then return DEFAULTS[name] --[[@as number]] end
    if type(value) ~= "number" or value ~= value or value <= 0 or value == math.huge then
      bad(name, "a positive finite number of seconds", value)
    end
    return value
  end
  if options.on_error ~= nil and type(options.on_error) ~= "function" then bad("on_error", "a function", options.on_error) end
  if options.tls == nil then
    for _, name in ipairs({ "handshake_timeout", "max_handshakes", "max_handshake_bytes" }) do
      if options[name] ~= nil then bad(name, "unset: it applies to TLS only, and no `tls` option was given", options[name]) end
    end
  end
  if options.logger ~= nil and (type(options.logger) ~= "table" or type(options.logger.log) ~= "function") then
    bad("logger", "a hecate.log.Logger", options.logger)
  end
  settings.action = action
  settings.host = host
  settings.port = integer("port", 0, 65535)
  settings.backlog = integer("backlog", 1, 65535)
  settings.max_connections = options.max_connections ~= nil and integer("max_connections", 1, 1000000) or nil
  settings.max_content = integer("max_content", 0, 1099511627776)
  settings.head_timeout = seconds("head_timeout")
  settings.idle_timeout = seconds("idle_timeout")
  settings.content_timeout = seconds("content_timeout")
  settings.write_timeout = seconds("write_timeout")
  settings.request_timeout = seconds("request_timeout")
  settings.drain_timeout = seconds("drain_timeout")
  settings.handshake_timeout = seconds("handshake_timeout")
  settings.max_handshakes = integer("max_handshakes", 1, 1000000)
  settings.max_handshake_bytes = integer("max_handshake_bytes", 1, 16777216)
  settings.logger = options.logger
  local tls = options.tls
  if type(tls) == "table" then
    local config = {}
    for key, value in pairs(tls) do config[key] = value end
    if config.alpn == nil then config.alpn = { "http/1.1" } end
    tls = net.tls.server_config(config)
  elseif tls ~= nil and type(tls) ~= "userdata" then
    bad("tls", "a table of net.tls.server_config options or a configuration it built", tls)
  end
  settings.tls = tls
  if options.parser ~= nil then Parser.request(options.parser):close() end -- validates the limits now
  settings.limits = options.parser
  settings.on_error = options.on_error
  return settings
end

return M
