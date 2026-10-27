-- `net.tls`: configurations, handshakes and `net.connect_tls` over the native rustls module
-- (ADR 0021). Verification is always on and cannot be disabled (OQ-41): a client configuration
-- trusts the operating system's store (ADR 0024) plus the anchors of `ca_pem`, and `system_roots =
-- false` narrows trust to `ca_pem`. Options are validated here, in Lua, against a per-function
-- allow-list: an unknown key (a typo, `verify = false`, a server option given to a client) raises
-- `ArgumentError` instead of being ignored. Revocation checking by the operating system's
-- verifier (macOS, Windows) may perform blocking I/O on the reactor thread (ADR 0024).
global <const> require, pcall, type, error, pairs, ipairs, tostring, table, math

local core = require("hecate.core")
local reactor = require("hecate.reactor")
local errors = require("hecate.net.errors")
local TlsError = errors.TlsError
local TlsStream = require("hecate.net.tls_stream")
local tcp = require("hecate.net.tcp")

local loaded, native = pcall(require, "hecate.net.tls_native")
local BUILD_HINT = "the native TLS module hecate.net.tls_native is not built (run `lua tools/run.lua build-native net`;"
  .. " installed rocks will ship the module once distribution lands)"

--- Default time allowed for a TLS handshake, in seconds.
local DEFAULT_HANDSHAKE_DEADLINE = 10

--- TLS configuration and handshakes.
---@class hecate.net.tls
local M = {}

--- A reusable client configuration built by `tls.client_config` (native userdata).
---@class hecate.net.TlsClientConfig

--- A reusable server configuration built by `tls.server_config` (native userdata).
---@class hecate.net.TlsServerConfig

--- Options of `tls.client_config`. Any other key raises `ArgumentError`.
---@class hecate.net.TlsClientOptions
---@field ca_pem? string  PEM trust anchors added to the system trust store (the only ones with `system_roots = false`)
---@field system_roots? boolean  trust the operating system's store (default true); false trusts only `ca_pem`
---@field alpn? string[]  application protocols to offer, in preference order (non-empty list of non-empty strings of at most 255 bytes)
---@field cert_pem? string  client certificate chain (mutual TLS), with `key_pem`
---@field key_pem? string  client private key (PKCS#8, PKCS#1 or SEC1 PEM)

--- Options of `tls.server_config`. Any other key raises `ArgumentError`.
---@class hecate.net.TlsServerOptions
---@field cert_pem string  certificate chain, end-entity first
---@field key_pem string  private key
---@field alpn? string[]  accepted application protocols, in preference order
---@field client_ca_pem? string  require and verify client certificates against these anchors

--- Options of `tls.connect` and `tls.accept`.
---@class hecate.net.TlsHandshakeOptions
---@field handshake_deadline? number  seconds allowed for the whole handshake (positive, default 10)

--- Options of `net.connect_tls`: the client options, the transport options of `net.connect`
--- and the connect path's own.
---@class hecate.net.TlsConnectOptions : hecate.net.TlsClientOptions, hecate.reactor.TcpOptions
---@field server_name? string  SNI and certificate identity (RFC 6125); default `host`
---@field tls_config? hecate.net.TlsClientConfig  a prebuilt `tls.client_config`; excludes the client options
---@field family? "inet"|"inet6"  address family used to resolve `host`
---@field handshake_deadline? number  seconds allowed for the TLS handshake (positive, default 10); the TCP connect is bounded by the caller

--- Why a TLS operation failed, as `TlsError.context.reason`.
---@alias hecate.net.TlsFailureReason
---| "untrusted_issuer"
---| "name_mismatch"
---| "expired"
---| "not_yet_valid"
---| "revoked"
---| "alpn_mismatch"
---| "truncated"
---| "transport_ended"
---| "stalled"
---| "native_missing"

--- True when the native TLS module is built and loadable.
---@return boolean available
---@return string? reason  why not
function M.available()
  if loaded then return true end
  return false, BUILD_HINT .. ": " .. tostring(native)
end

---@param call string  the public call, for the message
local function require_native(call)
  if not loaded then error(errors.qualify(errors.tls_failure(BUILD_HINT, "native_missing"), call), 0) end
end

--- Converts a native failure (a text, or a `{ kind, message }` table) into a `TlsError`.
---@param failure any
---@param call string  the public call, for the message
---@return hecate.net.TlsError
local function native_error(failure, call)
  return errors.qualify(errors.tls_failure(failure), call)
end

local function set(list)
  local result = {}
  for _, key in ipairs(list) do result[key] = true end
  return result
end

local CLIENT_KEYS = set({ "ca_pem", "system_roots", "alpn", "cert_pem", "key_pem" })
local SERVER_KEYS = set({ "cert_pem", "key_pem", "alpn", "client_ca_pem" })
local HANDSHAKE_KEYS = set({ "handshake_deadline" })
local TRANSPORT_KEYS = set({ "nodelay", "keepalive", "keepalive_delay", "family" })
local CONNECT_KEYS = {}
for _, keys in ipairs({ CLIENT_KEYS, HANDSHAKE_KEYS, TRANSPORT_KEYS, set({ "server_name", "tls_config" }) }) do
  for key in pairs(keys) do CONNECT_KEYS[key] = true end
end

-- Keys that other libraries use to turn verification off: named in the message (OQ-41).
local VERIFICATION_SWITCHES = set({ "verify", "insecure", "skip_verify", "danger_accept_invalid_certs" })

local function sorted_keys(keys)
  local list = {}
  for key in pairs(keys) do list[#list + 1] = key end
  table.sort(list)
  return table.concat(list, ", ")
end

--- Raises `ArgumentError` naming the first key of `options` that is not in `allowed`.
---@param name string  the public function, for the message
---@param options table
---@param allowed table<string, boolean>
---@param kind "client"|"server"|"connect"|"handshake"
local function reject_unknown(name, options, allowed, kind)
  local unknown = {}
  for key in pairs(options) do
    if not allowed[key] then unknown[#unknown + 1] = tostring(key) end
  end
  if #unknown == 0 then return end
  table.sort(unknown)
  local key = unknown[1]
  local message = ("%s: unknown option %s"):format(name, key)
  if kind == "server" and (key == "ca_pem" or key == "system_roots") then
    message = message .. " (ca_pem and system_roots are client options; use client_ca_pem to require client certificates)"
  elseif kind ~= "server" and key == "client_ca_pem" then
    message = message .. " (client_ca_pem is a server option: it requires clients to present a certificate;"
      .. " to verify the server use ca_pem and system_roots)"
  elseif VERIFICATION_SWITCHES[key] then
    message = message .. " (certificate verification cannot be disabled)"
  else
    message = message .. " (valid options: " .. sorted_keys(allowed) .. ")"
  end
  error(core.ArgumentError(message), 4)
end

--- Validates `alpn`: a non-empty sequence of non-empty strings of at most 255 bytes (RFC 7301
--- section 3.1).
local function check_alpn(name, alpn)
  local valid = type(alpn) == "table"
  local count = 0
  if valid then
    for key, value in pairs(alpn) do
      count = count + 1
      if math.type(key) ~= "integer" or type(value) ~= "string" or value == "" or #value > 255 then valid = false break end
    end
    valid = valid and count > 0 and #alpn == count
  end
  if not valid then
    error(core.ArgumentError(("%s: option alpn must be a non-empty list of non-empty strings of at most 255 bytes"):format(name)), 4)
  end
end

--- Validates the PEM options named in `keys` (strings) and `alpn`.
local function check_values(name, options, keys)
  for _, key in ipairs(keys) do
    if options[key] ~= nil and type(options[key]) ~= "string" then
      error(core.ArgumentError(("%s: option %s must be a PEM string"):format(name, key)), 4)
    end
  end
  if options.alpn ~= nil then check_alpn(name, options.alpn) end
end

--- Validates the trust options shared by `client_config` and `connect_tls`.
---@param name string
---@param options table
local function check_trust(name, options)
  if options.system_roots ~= nil and type(options.system_roots) ~= "boolean" then
    error(core.ArgumentError(("%s: option system_roots must be a boolean"):format(name)), 4)
  end
  if options.system_roots == false and options.ca_pem == nil then
    error(core.ArgumentError(("%s: option ca_pem is required when system_roots is false (nothing else would be trusted)"):format(name)), 4)
  end
  if (options.cert_pem == nil) ~= (options.key_pem == nil) then
    error(core.ArgumentError(("%s: cert_pem and key_pem must be given together"):format(name)), 4)
  end
end

--- Validates `handshake_deadline` (a positive, finite number of seconds).
local function check_deadline(name, options)
  local seconds = options.handshake_deadline
  if seconds == nil then return end
  if type(seconds) ~= "number" or seconds ~= seconds or seconds <= 0 or seconds == math.huge then
    error(core.ArgumentError(("%s: option handshake_deadline must be a positive number of seconds, got %s"):format(name, tostring(seconds))), 4)
  end
end

--- Validates the transport options `connect_tls` hands to `net.connect`, before any work is done.
local function check_transport(name, options)
  for _, key in ipairs({ "nodelay", "keepalive" }) do
    if options[key] ~= nil and type(options[key]) ~= "boolean" then
      error(core.ArgumentError(("%s: option %s must be a boolean, got %s"):format(name, key, type(options[key]))), 4)
    end
  end
  local delay = options.keepalive_delay
  if delay ~= nil and (math.type(delay) ~= "integer" or delay <= 0) then
    error(core.ArgumentError(("%s: option keepalive_delay must be a positive integer number of seconds, got %s"):format(name, tostring(delay))), 4)
  end
  if options.family ~= nil and options.family ~= "inet" and options.family ~= "inet6" then
    error(core.ArgumentError(("%s: option family must be \"inet\" or \"inet6\", got %s"):format(name, tostring(options.family))), 4)
  end
end

--- Validates the options table of a configuration builder.
local function check_table(name, options)
  if type(options) ~= "table" then
    error(core.ArgumentError(("%s: expects an options table, got %s"):format(name, type(options))), 3)
  end
end

--- Validates the stream a handshake takes over. On an argument error the caller keeps it.
local function check_stream(name, stream)
  if type(stream) ~= "table" or type(stream.read) ~= "function" or type(stream.write) ~= "function"
    or type(stream.close) ~= "function" then
    error(core.ArgumentError(("%s: expects a stream (an object with read, write and close), got %s"):format(name, type(stream))), 3)
  end
end

--- Builds a client configuration (reusable across connections). The server certificate is
--- verified against the operating system's trust store, plus `ca_pem` when given; verification
--- cannot be disabled (ADR 0024). Raises `ArgumentError` for a malformed or unknown option and
--- `TlsError` when a PEM cannot be parsed or the system trust store cannot be loaded.
---@param options? hecate.net.TlsClientOptions
---@return hecate.net.TlsClientConfig config
function M.client_config(options)
  options = options or {}
  check_table("net.tls.client_config", options)
  reject_unknown("net.tls.client_config", options, CLIENT_KEYS, "client")
  check_values("net.tls.client_config", options, { "ca_pem", "cert_pem", "key_pem" })
  check_trust("net.tls.client_config", options)
  require_native("net.tls.client_config")
  local ok, config = pcall(native.client_config, options)
  if not ok then error(native_error(config, "net.tls.client_config"), 0) end
  return config
end

--- Builds a server configuration (reusable across connections). Raises `ArgumentError` for a
--- missing, malformed or unknown option and `TlsError` when a PEM cannot be parsed.
---@param options hecate.net.TlsServerOptions
---@return hecate.net.TlsServerConfig config
function M.server_config(options)
  check_table("net.tls.server_config", options)
  reject_unknown("net.tls.server_config", options, SERVER_KEYS, "server")
  for _, key in ipairs({ "cert_pem", "key_pem" }) do
    if type(options[key]) ~= "string" then
      error(core.ArgumentError(("net.tls.server_config: option %s is required (a PEM string)"):format(key)), 3)
    end
  end
  check_values("net.tls.server_config", options, { "client_ca_pem" })
  require_native("net.tls.server_config")
  local ok, config = pcall(native.server_config, options)
  if not ok then error(native_error(config, "net.tls.server_config"), 0) end
  return config
end

--- Runs `tls.handshake` under the handshake deadline; on any failure (expiry and cancellation
--- included) closes the stream and rethrows.
---@async
---@param stream hecate.net.Stream
---@param session userdata
---@param options hecate.net.TlsHandshakeOptions
---@param call string  the public call, for the message
local function handshake(stream, session, options, call)
  local tls = TlsStream(stream, session)
  local done, failure = pcall(reactor.deadline, options.handshake_deadline or DEFAULT_HANDSHAKE_DEADLINE, tls.handshake, tls)
  if not done then
    tls:close()
    error(errors.qualify(failure, call), 0)
  end
  return tls
end

--- Runs a TLS client handshake over `stream`, which the result owns: it is closed when the native
--- session or the handshake fails (a deadline included), and left to the caller when an argument
--- is malformed. `server_name` is sent as SNI and the certificate must match it (RFC 6125).
--- The handshake must finish within `options.handshake_deadline` seconds (default 10); on expiry
--- `hecate.core.DeadlineExceededError` is raised.
--- This is the low-level step for a stream you already hold (any `Stream`); to open a TCP connection and
--- secure it, call `net.connect_tls`, the client entry point.
---@async
---@param stream hecate.net.Stream
---@param server_name string
---@param config hecate.net.TlsClientConfig|userdata  from `client_config`
---@param options? hecate.net.TlsHandshakeOptions
---@return hecate.net.TlsStream
function M.connect(stream, server_name, config, options)
  check_stream("net.tls.connect", stream)
  if type(server_name) ~= "string" or server_name == "" then
    error(core.ArgumentError("net.tls.connect: expects a server name"), 2)
  end
  options = options or {}
  check_table("net.tls.connect", options)
  reject_unknown("net.tls.connect", options, HANDSHAKE_KEYS, "handshake")
  check_deadline("net.tls.connect", options)
  if type(config) ~= "userdata" then
    error(core.ArgumentError("net.tls.connect: expects a configuration from tls.client_config"), 2)
  end
  require_native("net.tls.connect")
  local ok, session = pcall(native.client, config, server_name)
  if not ok then
    stream:close()
    error(native_error(session, "net.tls.connect"), 0)
  end
  return handshake(stream, session, options, "net.tls.connect")
end

--- Runs a TLS server handshake over an accepted `stream`, which the result owns: it is closed when
--- the session or the handshake fails (a deadline included), and left to the caller when an
--- argument is malformed. The handshake must finish within `options.handshake_deadline` seconds
--- (default 10); on expiry `hecate.core.DeadlineExceededError` is raised.
---@async
---@param stream hecate.net.Stream
---@param config hecate.net.TlsServerConfig|userdata  from `server_config`
---@param options? hecate.net.TlsHandshakeOptions
---@return hecate.net.TlsStream
function M.accept(stream, config, options)
  check_stream("net.tls.accept", stream)
  options = options or {}
  check_table("net.tls.accept", options)
  reject_unknown("net.tls.accept", options, HANDSHAKE_KEYS, "handshake")
  check_deadline("net.tls.accept", options)
  if type(config) ~= "userdata" then
    error(core.ArgumentError("net.tls.accept: expects a configuration from tls.server_config"), 2)
  end
  require_native("net.tls.accept")
  local ok, session = pcall(native.server, config)
  if not ok then
    stream:close()
    error(native_error(session, "net.tls.accept"), 0)
  end
  return handshake(stream, session, options, "net.tls.accept")
end

-- Default client configurations (system roots, no `ca_pem`, no client certificate), one per ALPN
-- list: building one loads the operating system's trust store, which is costly. Bounded so that
-- varying lists cannot grow it without limit.
local default_configs = {}
local default_count = 0
local MAX_DEFAULT_CONFIGS = 16

--- Returns the cached default client configuration for `alpn`, building it on first use.
---@param alpn string[]?
---@return hecate.net.TlsClientConfig
local function default_config(alpn)
  local parts = {}
  for i, protocol in ipairs(alpn or {}) do parts[i] = #protocol .. ":" .. protocol end
  local key = table.concat(parts, ",")
  local config = default_configs[key]
  if config == nil then
    config = M.client_config({ alpn = alpn })
    if default_count < MAX_DEFAULT_CONFIGS then
      default_configs[key] = config
      default_count = default_count + 1
    end
  end
  return config
end

--- Forgets the cached default client configurations (tests).
---@private
function M._clear_default_configs()
  default_configs, default_count = {}, 0
end

--- Connects to `host:port` over TCP, then runs a TLS client handshake. With no option the server
--- certificate is verified against the operating system's trust store. Options: the transport
--- options of `net.connect` (`nodelay`, `keepalive`, `keepalive_delay`, `family`), `ca_pem`
--- (trust anchors added to the system store, for a private CA), `system_roots` (false trusts only
--- `ca_pem`), `alpn`, `cert_pem` and `key_pem` (mutual TLS), `server_name` (default `host`: SNI
--- and certificate identity), `tls_config` (a prebuilt `tls.client_config`, reusable across
--- connections) and `handshake_deadline` (seconds, default 10, TLS handshake only: bound the
--- TCP connect with `reactor.deadline`). Certificate verification cannot be disabled and an unknown
--- option raises `ArgumentError`. Every option is validated before any name is resolved and
--- before the configuration is built. The default configuration (system roots, no `ca_pem`) is built
--- once per ALPN list and reused; pass `tls_config` to share any other configuration.
---
--- Raises `hecate.net.TlsError` for a failed handshake or verification,
--- `hecate.core.DeadlineExceededError` when the handshake outlasts `handshake_deadline`,
--- `hecate.reactor.TransportError` for a TCP failure, `hecate.core.ArgumentError` for a malformed option.
---@async
---@param host string
---@param port integer
---@param options? hecate.net.TlsConnectOptions
---@return hecate.net.TlsStream stream
function M.connect_tls(host, port, options)
  options = options or {}
  if type(options) ~= "table" then
    error(core.ArgumentError("net.connect_tls: expects an options table"), 2)
  end
  if type(host) ~= "string" or host == "" then
    error(core.ArgumentError(("net.connect_tls: expects a host name or address, got %s"):format(tostring(host))), 2)
  end
  if math.type(port) ~= "integer" or port < 0 or port > 65535 then
    error(core.ArgumentError(("net.connect_tls: expects a port in 0..65535, got %s"):format(tostring(port))), 2)
  end
  reject_unknown("net.connect_tls", options, CONNECT_KEYS, "connect")
  check_transport("net.connect_tls", options)
  check_deadline("net.connect_tls", options)
  local config = options.tls_config
  if config ~= nil then
    if options.ca_pem ~= nil or options.system_roots ~= nil or options.cert_pem ~= nil or options.key_pem ~= nil
      or options.alpn ~= nil then
      error(core.ArgumentError("net.connect_tls: tls_config cannot be combined with ca_pem, system_roots, cert_pem, key_pem or alpn"), 2)
    end
    if type(config) ~= "userdata" then
      error(core.ArgumentError("net.connect_tls: option tls_config must come from tls.client_config"), 2)
    end
  else
    check_values("net.connect_tls", options, { "ca_pem", "cert_pem", "key_pem" })
    check_trust("net.connect_tls", options)
  end
  if options.server_name ~= nil and (type(options.server_name) ~= "string" or options.server_name == "") then
    error(core.ArgumentError("net.connect_tls: option server_name must be a non-empty string"), 2)
  end
  require_native("net.connect_tls")
  if config == nil then
    if options.ca_pem == nil and options.system_roots ~= false and options.cert_pem == nil then
      config = default_config(options.alpn)
    else
      config = M.client_config({
        ca_pem = options.ca_pem, system_roots = options.system_roots, alpn = options.alpn,
        cert_pem = options.cert_pem, key_pem = options.key_pem,
      })
    end
  end
  local transport = {}
  for key in pairs(TRANSPORT_KEYS) do transport[key] = options[key] end
  local stream = tcp.connect_for("net.connect_tls", host, port, transport)
  local ok, result = pcall(M.connect, stream, options.server_name or host, config, { handshake_deadline = options.handshake_deadline })
  if ok then return result end
  local failure = errors.qualify(result, "net.connect_tls") --[[@as hecate.core.Error]]
  -- An unknown issuer is the usual failure of a system trust store that lacks the server's CA.
  if core.is_instance_of(failure, TlsError) and failure.context and failure.context.reason == "untrusted_issuer"
    and options.tls_config == nil and options.system_roots ~= false then
    error(TlsError({
      message = (failure.message or tostring(failure)) .. " (the issuer is not in the system trust store; on Linux"
        .. " install the system CA certificates, for example the ca-certificates package; on macOS and Windows the"
        .. " operating system's store is used; for a private CA pass ca_pem)",
      context = { reason = "untrusted_issuer" },
      cause = failure,
    }), 0)
  end
  error(failure, 0)
end

return M
