-- `net.tls`: configurations, handshakes and `net.connect_tls` over the native rustls module
-- (ADR 0021). Verification is always on: a client configuration needs trust anchors
-- (`ca_pem`), there is no bundled or system store yet and no switch to turn it off (OQ-41).
global <const> require, pcall, type, error, pairs, ipairs, tostring

local core = require("hecate.core")
local errors = require("hecate.net.errors")
local TlsError = errors.TlsError
local TlsStream = require("hecate.net.tls_stream")
local tcp = require("hecate.net.tcp")

local loaded, native = pcall(require, "hecate.net.tls_native")
local BUILD_HINT = "the native TLS module hecate.net.tls_native is not built (run `lua tools/run.lua build-native`)"

--- TLS configuration and handshakes.
---@class hecate.net.tls
local M = {}

--- Options of `tls.client_config`.
---@class hecate.net.TlsClientOptions
---@field ca_pem? string  PEM trust anchors added to the system trust store (the only ones with `system_roots = false`)
---@field system_roots? boolean  trust the operating system's store (default true); false trusts only `ca_pem`
---@field alpn? string[]  application protocols to offer, in preference order
---@field cert_pem? string  client certificate chain (mutual TLS), with `key_pem`
---@field key_pem? string  client private key (PKCS#8, PKCS#1 or SEC1 PEM)

--- Options of `tls.server_config`.
---@class hecate.net.TlsServerOptions
---@field cert_pem string  certificate chain, end-entity first
---@field key_pem string  private key
---@field alpn? string[]  accepted application protocols, in preference order
---@field client_ca_pem? string  require and verify client certificates against these anchors

--- True when the native TLS module is built and loadable.
---@return boolean available
---@return string? reason  why not
function M.available()
  if loaded then return true end
  return false, BUILD_HINT .. ": " .. tostring(native)
end

local function require_native()
  if not loaded then error(errors.tls_failure(BUILD_HINT, "native_missing"), 0) end
end

--- Converts a native failure into a `TlsError` without its Lua stack traceback.
---@param failure any
---@return hecate.net.TlsError
local function native_error(failure)
  return errors.tls_failure((tostring(failure):gsub("\nstack traceback:.*$", "")))
end

--- Validates an options table.
local function check(name, options, required)
  if type(options) ~= "table" then
    error(core.ArgumentError(("%s expects an options table, got %s"):format(name, type(options))), 3)
  end
  for _, key in ipairs(required) do
    if type(options[key]) ~= "string" then error(core.ArgumentError(("%s: option %s is required (a PEM string)"):format(name, key)), 3) end
  end
end

--- Validates the trust options shared by `client_config` and `connect_tls`.
---@param name string
---@param options table
local function check_trust(name, options)
  if options.ca_pem ~= nil and type(options.ca_pem) ~= "string" then
    error(core.ArgumentError(("%s: option ca_pem must be a PEM string"):format(name)), 3)
  end
  if options.system_roots ~= nil and type(options.system_roots) ~= "boolean" then
    error(core.ArgumentError(("%s: option system_roots must be a boolean"):format(name)), 3)
  end
  if options.system_roots == false and options.ca_pem == nil then
    error(core.ArgumentError(("%s: option ca_pem is required when system_roots is false (nothing else would be trusted)"):format(name)), 3)
  end
end

--- Builds a client configuration (reusable across connections). The server certificate is
--- verified against the operating system's trust store, plus `ca_pem` when given; verification
--- cannot be disabled (ADR 0024). Raises `ArgumentError` for a malformed option and `TlsError` when
--- a PEM cannot be parsed or the system trust store cannot be loaded.
---@param options? hecate.net.TlsClientOptions
---@return userdata config
function M.client_config(options)
  options = options or {}
  check("client_config", options, {})
  check_trust("client_config", options)
  require_native()
  local ok, config = pcall(native.client_config, options)
  if not ok then error(native_error(config), 0) end
  return config
end

--- Builds a server configuration (reusable across connections).
---@param options hecate.net.TlsServerOptions
---@return userdata config
function M.server_config(options)
  check("server_config", options, { "cert_pem", "key_pem" })
  require_native()
  local ok, config = pcall(native.server_config, options)
  if not ok then error(native_error(config), 0) end
  return config
end

--- Runs a TLS client handshake over `stream` (which the result owns; it is closed when the native
--- session or the handshake fails, and left to the caller when an argument is malformed).
--- `server_name` is sent as SNI and the certificate must match it (RFC 6125).
---@async
---@param stream hecate.net.Stream
---@param server_name string
---@param config userdata  from `client_config`
---@return hecate.net.TlsStream
function M.connect(stream, server_name, config)
  if type(server_name) ~= "string" or server_name == "" then
    error(core.ArgumentError("tls.connect expects a server name"), 2)
  end
  if type(config) ~= "userdata" then
    error(core.ArgumentError("tls.connect expects a configuration from tls.client_config"), 2)
  end
  require_native()
  local ok, session = pcall(native.client, config, server_name)
  if not ok then
    stream:close()
    error(native_error(session), 0)
  end
  local tls = TlsStream(stream, session)
  local done, failure = pcall(tls.handshake, tls)
  if not done then
    tls:close()
    error(failure, 0)
  end
  return tls
end

--- Runs a TLS server handshake over an accepted `stream` (owned by the result, closed when the
--- session or the handshake fails, and left to the caller when `config` is malformed).
---@async
---@param stream hecate.net.Stream
---@param config userdata  from `server_config`
---@return hecate.net.TlsStream
function M.accept(stream, config)
  if type(config) ~= "userdata" then
    error(core.ArgumentError("tls.accept expects a configuration from tls.server_config"), 2)
  end
  require_native()
  local ok, session = pcall(native.server, config)
  if not ok then
    stream:close()
    error(native_error(session), 0)
  end
  local tls = TlsStream(stream, session)
  local done, failure = pcall(tls.handshake, tls)
  if not done then
    tls:close()
    error(failure, 0)
  end
  return tls
end

local TLS_KEYS = { ca_pem = true, system_roots = true, alpn = true, cert_pem = true, key_pem = true, server_name = true, tls_config = true }

--- Connects to `host:port` over TCP, then runs a TLS client handshake. With no option the server
--- certificate is verified against the operating system's trust store. Options: those of
--- `net.connect` plus `ca_pem` (trust anchors added to the system store, for a private CA),
--- `system_roots` (false trusts only `ca_pem`), `alpn`, `cert_pem` and `key_pem` (mutual TLS),
--- `server_name` (default `host`: SNI and certificate identity) and `tls_config` (a prebuilt
--- `tls.client_config`). Certificate verification cannot be disabled.
---
--- Raises `hecate.net.TlsError` for a failed handshake or verification, `reactor.TransportError`
--- for a TCP failure, `hecate.core.ArgumentError` for a malformed option.
---@async
---@param host string
---@param port integer
---@param options? hecate.net.TlsClientOptions | table
---@return hecate.net.TlsStream stream
function M.connect_tls(host, port, options)
  options = options or {}
  if type(options) ~= "table" then
    error(core.ArgumentError("connect_tls expects an options table"), 2)
  end
  local config = options.tls_config
  if config ~= nil then
    if options.ca_pem ~= nil or options.system_roots ~= nil or options.cert_pem ~= nil or options.key_pem ~= nil
      or options.alpn ~= nil then
      error(core.ArgumentError("connect_tls: tls_config cannot be combined with ca_pem, system_roots, cert_pem, key_pem or alpn"), 2)
    end
  else
    check_trust("connect_tls", options)
  end
  if (options.cert_pem == nil) ~= (options.key_pem == nil) then
    error(core.ArgumentError("connect_tls: cert_pem and key_pem must be given together"), 2)
  end
  if options.server_name ~= nil and (type(options.server_name) ~= "string" or options.server_name == "") then
    error(core.ArgumentError("connect_tls: option server_name must be a non-empty string"), 2)
  end
  require_native()
  if config == nil then config = M.client_config(options) end
  local transport = {}
  for key, value in pairs(options) do
    if not TLS_KEYS[key] then transport[key] = value end
  end
  local stream = tcp.connect(host, port, transport)
  local ok, result = pcall(M.connect, stream, options.server_name or host, config)
  if ok then return result end
  local failure = result --[[@as hecate.core.Error]]
  -- An unknown issuer is the usual failure of a system trust store that lacks the server's CA.
  if core.is_instance_of(failure, TlsError) and tostring(failure):find("UnknownIssuer", 1, true)
    and options.tls_config == nil and options.system_roots ~= false then
    error(TlsError({
      message = (failure.message or tostring(failure)) .. " (the issuer is not in the system trust store: install"
        .. " the system CA certificates, for example the ca-certificates package, or pass ca_pem)",
      context = { reason = "untrusted_issuer" },
      cause = failure,
    }), 0)
  end
  error(result, 0)
end

return M
