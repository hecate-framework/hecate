-- The HTTP/1.1 client over hecate.net streams (RFC 9110, RFC 9112): a connection pool per origin, redirects, deadlines,
-- TLS and streaming in both directions. One request is one computation of the caller's scope: cancelling the scope
-- cancels the request, and the connection of a cancelled request is dropped, never reused.
--
-- The work is split into internal modules (not public API): `internal/client_connection` (connection state and parser
-- events), `internal/client_pool` (the pool per origin), `internal/client_exchange` (one request and its response) and
-- `internal/client_redirect` (the redirect loop). This file keeps the public class, the option validation and `request`.
global <const> require, type, error, pairs, ipairs, math, string, tostring

local core = require("hecate.core")
local reactor = require("hecate.reactor")
local json = require("hecate.json")
local Parser = require("hecate.http.parser")
local Fields = require("hecate.http.fields")
local grammar = require("hecate.http.grammar")
local url = require("hecate.http.url")
local option_text = require("hecate.http.options")
local form = require("hecate.http.form")
local multipart = require("hecate.http.multipart")
local pool = require("hecate.http.internal.client_pool")
local exchange = require("hecate.http.internal.client_exchange")
local redirect = require("hecate.http.internal.client_redirect")

--- Settings of a client and their defaults. Every limit has one.
---@class hecate.http.ClientOptions
---@field connect_timeout? number  seconds to connect and, for https, to handshake (default 10)
---@field head_timeout? number  seconds from the end of the request to the end of the response head (default 30)
---@field content_timeout? number  seconds between two reads of response content (default 60)
---@field write_timeout? number  seconds a write to the server may take (default 60)
---@field request_timeout? number  seconds for the whole exchange, redirects and content included (default 300; overridden per request; a streaming download longer than that sets a larger value)
---@field max_content? integer  bytes `response:read_content()` accepts (default 10485760, 10 MiB)
---@field max_redirects? integer  redirects followed per request (default 10)
---@field allow_downgrade? boolean  follow a redirect from https to http (default false)
---@field max_connections_per_origin? integer  connections to one origin, in use or idle (default 8)
---@field max_idle_connections? integer  idle connections in the whole pool (default 64; the least recently used is closed beyond it)
---@field cross_origin_redirects? boolean  follow a 307 or 308 to another origin when it would send the request content again (default false)
---@field strip_on_redirect? string[]  more field names removed when a redirect changes the origin (always removed: Authorization, Cookie, Proxy-Authorization, X-Api-Key, X-Auth-Token)
---@field idle_timeout? number  seconds a pooled connection may idle (default 30: shorter than the 75 s of `http.Server`)
---@field expect_timeout? number  seconds to wait for `100 Continue` when a request asks for it (default 1)
---@field user_agent? string  the `User-Agent` field (default "hecate-http")
---@field tls? { ca_pem?: string, system_roots?: boolean, cert_pem?: string, key_pem?: string }  trust and client certificate for https (ADR 0024: the system store by default; `ca_pem` adds an anchor)
---@field parser? hecate.http.parser.Options  limits on the response head (target is unused; field size, head size, field count)

--- The defaults of the client's settings. Settings without an entry have no default value: `tls` (the system trust store),
--- `strip_on_redirect` (only the built-in list) and `parser` (the parser's own limits).
---@class hecate.http.ClientDefaults
---@field connect_timeout number
---@field head_timeout number
---@field content_timeout number
---@field write_timeout number
---@field request_timeout number
---@field max_content integer
---@field max_redirects integer
---@field allow_downgrade boolean
---@field max_connections_per_origin integer
---@field max_idle_connections integer
---@field cross_origin_redirects boolean
---@field idle_timeout number
---@field expect_timeout number
---@field user_agent string

---@type hecate.http.ClientDefaults
local DEFAULTS <const> = {
  connect_timeout = 10,
  head_timeout = 30,
  content_timeout = 60,
  write_timeout = 60,
  max_content = 10485760,
  max_redirects = 10,
  allow_downgrade = false,
  max_connections_per_origin = 8,
  max_idle_connections = 64,
  request_timeout = 300,
  cross_origin_redirects = false,
  idle_timeout = 30,
  expect_timeout = 1,
  user_agent = "hecate-http",
}

--- An HTTP/1.1 client with a pool of connections per origin.
---@class hecate.http.Client
---@field DEFAULTS hecate.http.ClientDefaults
---@overload fun(options?: hecate.http.ClientOptions): hecate.http.Client
local Client = core.class("Client")
Client.DEFAULTS = DEFAULTS

-- The options of one request (the other settings belong to the client).
local REQUEST_OPTIONS <const> = {
  fields = true, content = true, form = true, multipart = true, redirects = true, expect_continue = true,
  cross_origin_redirects = true, request_timeout = true, head_timeout = true, content_timeout = true, max_content = true,
  max_redirects = true,
}

local KNOWN <const> = {
  connect_timeout = true, head_timeout = true, content_timeout = true, write_timeout = true, request_timeout = true,
  max_content = true, max_redirects = true, allow_downgrade = true, max_connections_per_origin = true,
  idle_timeout = true, expect_timeout = true, user_agent = true, tls = true, parser = true,
  max_idle_connections = true, cross_origin_redirects = true, strip_on_redirect = true,
}

local function bad(name, expected, value)
  error(core.ArgumentError(("http.Client: invalid %s %s: expected %s"):format(name, option_text.show(value), expected)), 4)
end

--- Creates a client. Nothing is connected until the first request.
---
--- Raises `hecate.core.ArgumentError` for an unknown or invalid option.
---@param options? hecate.http.ClientOptions
function Client:init(options)
  options = options or {}
  if type(options) ~= "table" then error(core.ArgumentError("http.Client: options must be a table"), 3) end
  for key in pairs(options) do
    if not KNOWN[key] then error(core.ArgumentError(option_text.unknown("http.Client", key, KNOWN)), 3) end
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
  ---@return integer
  local function integer(name, minimum, maximum)
    local value = options[name]
    if value == nil then return DEFAULTS[name] --[[@as integer]] end
    if math.type(value) ~= "integer" or value < minimum or value > maximum then
      bad(name, ("an integer from %d to %d"):format(minimum, maximum), value)
    end
    return value
  end
  self._connect_timeout = seconds("connect_timeout")
  self._head_timeout = seconds("head_timeout")
  self._content_timeout = seconds("content_timeout")
  self._write_timeout = seconds("write_timeout")
  self._idle_timeout = seconds("idle_timeout")
  self._expect_timeout = seconds("expect_timeout")
  self._request_timeout = seconds("request_timeout")
  self._max_content = integer("max_content", 0, 1099511627776)
  self._max_redirects = integer("max_redirects", 0, 100)
  self._max_per_origin = integer("max_connections_per_origin", 1, 10000)
  self._max_idle = integer("max_idle_connections", 0, 100000)
  for _, name in ipairs({ "cross_origin_redirects" }) do
    if options[name] ~= nil and type(options[name]) ~= "boolean" then bad(name, "a boolean", options[name]) end
  end
  self._cross_origin_redirects = options.cross_origin_redirects or false
  local strip = { "Authorization", "Cookie", "Proxy-Authorization", "X-Api-Key", "X-Auth-Token" }
  if options.strip_on_redirect ~= nil then
    if type(options.strip_on_redirect) ~= "table" then bad("strip_on_redirect", "a list of field names", options.strip_on_redirect) end
    for _, name in ipairs(options.strip_on_redirect) do
      if not grammar.is_token(name) then bad("strip_on_redirect", "a list of field names (tokens)", tostring(name)) end
      strip[#strip + 1] = name
    end
  end
  self._strip_on_redirect = strip
  if options.allow_downgrade ~= nil and type(options.allow_downgrade) ~= "boolean" then
    bad("allow_downgrade", "a boolean", options.allow_downgrade)
  end
  self._allow_downgrade = options.allow_downgrade or false
  local agent = options.user_agent
  if agent == nil then agent = DEFAULTS.user_agent end
  if not grammar.is_field_value(agent) or agent == "" then bad("user_agent", "a non-empty string without CR, LF or NUL", agent) end
  self._user_agent = agent
  -- A table of `net.tls.client_config` options, or a configuration that function built (a native userdata: `net` offers
  -- no class to test an instance against, and checks the same way).
  if options.tls ~= nil and type(options.tls) ~= "table" and type(options.tls) ~= "userdata" then
    bad("tls", "a table of TLS client options or a configuration built by net.tls.client_config", options.tls)
  end
  self._tls_options = type(options.tls) == "table" and options.tls or nil
  self._tls_config = type(options.tls) == "userdata" and options.tls or nil
  if options.parser ~= nil then Parser.response(options.parser):close() end -- validates the limits now
  self._limits = options.parser
  self._origins = {}
  self._closed = false
end

---@return table
function Client:_tls_client_config() return pool.tls_client_config(self) end

---@async
function Client:_connect(parts, state) return pool.connect(self, parts, state) end

--- Takes a lease on the origin (waits when `max_connections_per_origin` are leased), then a pooled connection or a new one.
---@async
---@return hecate.http.client.Connection conn
---@return boolean reused
function Client:_checkout(parts, state) return pool.checkout(self, parts, state) end

--- The size of the pool: `idle` connections and the `origins` it keeps an entry for.
---@return { idle: integer, origins: integer }
function Client:pool_stats() return pool.stats(self) end

--- One request and its response head on a pooled or new connection, retried once on a new connection when a reused one
--- turns out dead before any byte of the response arrived (idempotent methods and replayable content only).
---@async
function Client:_exchange(parts, method, fields, content, state, final_url)
  return exchange.exchange(self, parts, method, fields, content, state, final_url)
end

--- Sends a request and returns the response once its head has arrived; the content is read through
--- `response:read_content()` or `response:stream_content()`. The response holds its connection until the content is read
--- to its end or the response is closed. Redirects (301, 302, 303, 307, 308) are followed up to `max_redirects`.
---
--- `options`: `cross_origin_redirects` (this request may repeat its content to another origin on a 307 or 308), `form` (pairs, sent as `application/x-www-form-urlencoded`), `multipart` (parts for `multipart.build`, sent as
--- `multipart/form-data` with a random boundary; a function part streams the message, which is then not replayable), `fields` (a `Fields`, or a table for `Fields`), `content` (a string, sent with its length; a function
--- `content(write)`, streamed chunked and never replayed; a table, serialised as JSON), `redirects` (false: return the 3xx
--- response), `expect_continue` (send `Expect: 100-continue` and wait before the content; default false), `request_timeout`
--- (this request's total seconds, overrides the client's), and `head_timeout`, `content_timeout`, `max_content` and `max_redirects`
--- (this request's values of those settings). An unknown key is an `ArgumentError`.
---
--- Raises `hecate.core.ArgumentError` for an invalid method, URL (relative, userinfo, whitespace, control characters),
--- field or option; `hecate.reactor.TransportError` (as `net` raises it: its message and context may name the addresses
--- the name resolved to, so never forward them to a peer), `hecate.core.DeadlineExceededError` (`connect_timeout`,
--- `head_timeout`, `write_timeout`, or the whole-exchange `request_timeout`), `hecate.net.EndOfStreamError`,
--- `hecate.http.ParseError` and `hecate.core.ProtocolError` (a refused reason phrase, too many redirects, a redirect
--- loop, a downgrade to http) for failures, and `hecate.core.StateError` once the client is closed. Reading the content
--- of the response raises `hecate.http.ContentError` with `context.reason` `too_large` (beyond `max_content`) or
--- `timeout` (no content for `content_timeout` seconds), without a `context.status`: a status is the server's to give.
---@async
---@param method string
---@param target string  an absolute http or https URL
---@param options? { fields?: hecate.http.Fields|table, content?: string|table|function, form?: string[][], multipart?: table[], cross_origin_redirects?: boolean, head_timeout?: number, content_timeout?: number, max_content?: integer, max_redirects?: integer, redirects?: boolean, expect_continue?: boolean, request_timeout?: number }
---@return hecate.http.Response
function Client:request(method, target, options)
  if self._closed then error(core.StateError("http.Client:request: the client is closed"), 2) end
  options = options or {}
  if type(options) ~= "table" then error(core.ArgumentError("http.Client:request: options must be a table"), 2) end
  if not grammar.is_token(method) then error(core.ArgumentError("http.Client:request: the method must be a token"), 2) end
  for key in pairs(options) do
    if not REQUEST_OPTIONS[key] then error(core.ArgumentError(option_text.unknown("http.Client:request", key, REQUEST_OPTIONS)), 2) end
  end
  local parts, reason = url.parse(target)
  if parts == nil then error(core.ArgumentError("http.Client:request: invalid URL: " .. tostring(reason)), 2) end
  local fields
  if type(options.fields) == "table" and core.is_instance_of(options.fields, Fields) then
    fields = options.fields:copy()
  else
    fields = Fields(options.fields)
  end
  for _, name in ipairs({ "Host", "Content-Length", "Transfer-Encoding" }) do fields:remove(name) end
  if not fields:has("User-Agent") then fields:set("User-Agent", self._user_agent) end
  local content = options.content
  if (options.form ~= nil and 1 or 0) + (options.multipart ~= nil and 1 or 0) + (content ~= nil and 1 or 0) > 1 then
    error(core.ArgumentError("http.Client:request: content, form and multipart exclude each other"), 2)
  end
  if options.form ~= nil then
    content = form.encode_urlencoded(options.form)
    if not fields:has("Content-Type") then fields:set("Content-Type", "application/x-www-form-urlencoded") end
  elseif options.multipart ~= nil then
    local built, content_type = multipart.build(options.multipart)
    content = built
    fields:set("Content-Type", content_type)
  elseif type(content) == "table" then
    content = json.encode(content)
    if not fields:has("Content-Type") then fields:set("Content-Type", "application/json") end
  elseif content ~= nil and type(content) ~= "string" and type(content) ~= "function" then
    error(core.ArgumentError("http.Client:request: content must be a string, a table or a function"), 2)
  end
  local function per_request(name, kind)
    local value = options[name]
    if value == nil then return self["_" .. name] end
    if kind == "seconds" and (type(value) ~= "number" or value ~= value or value <= 0 or value == math.huge) then
      error(core.ArgumentError(("http.Client:request: %s must be a positive finite number of seconds"):format(name)), 3)
    end
    if kind == "count" and (math.type(value) ~= "integer" or value < 0) then
      error(core.ArgumentError(("http.Client:request: %s must be a non-negative integer"):format(name)), 3)
    end
    return value
  end
  local total = options.request_timeout or self._request_timeout
  if total ~= nil and (type(total) ~= "number" or total ~= total or total <= 0 or total == math.huge) then
    error(core.ArgumentError("http.Client:request: request_timeout must be a positive finite number of seconds"), 2)
  end
  local state = {
    deadline_at = total ~= nil and (reactor.now() + total) or nil, expect = options.expect_continue == true,
    head_timeout = per_request("head_timeout", "seconds"), content_timeout = per_request("content_timeout", "seconds"),
    max_content = per_request("max_content", "count"), max_redirects = per_request("max_redirects", "count"),
  }
  return redirect.follow(self, parts, method, fields, content, state, options)
end

---@param options? table
---@param content any
---@return table
local function with_content(options, content)
  local merged = {}
  for key, value in pairs(options or {}) do merged[key] = value end
  merged.content = content
  return merged
end

--- `request("GET", target, options)`: a request without content.
---@async
---@param target string
---@param options? table
---@return hecate.http.Response
function Client:get(target, options) return self:request("GET", target, options) end

--- `request("HEAD", target, options)`: a request without content.
---@async
---@param target string
---@param options? table
---@return hecate.http.Response
function Client:head(target, options) return self:request("HEAD", target, options) end

--- `request("DELETE", target, options)`: a request without content.
---@async
---@param target string
---@param options? table
---@return hecate.http.Response
function Client:delete(target, options) return self:request("DELETE", target, options) end

--- `request("OPTIONS", target, options)`: a request without content.
---@async
---@param target string
---@param options? table
---@return hecate.http.Response
function Client:options(target, options) return self:request("OPTIONS", target, options) end

--- `request("POST", target, options)` with `options.content` set to `content`.
---@async
---@param target string
---@param content? string|table|function
---@param options? table
---@return hecate.http.Response
function Client:post(target, content, options) return self:request("POST", target, with_content(options, content)) end

--- `request("PUT", target, options)` with `options.content` set to `content`.
---@async
---@param target string
---@param content? string|table|function
---@param options? table
---@return hecate.http.Response
function Client:put(target, content, options) return self:request("PUT", target, with_content(options, content)) end

--- `request("PATCH", target, options)` with `options.content` set to `content`.
---@async
---@param target string
---@param content? string|table|function
---@param options? table
---@return hecate.http.Response
function Client:patch(target, content, options) return self:request("PATCH", target, with_content(options, content)) end

--- Closes the idle pooled connections; connections in use are closed when their response ends. Idempotent, never
--- suspends; also the `<close>` protocol. A closed client refuses requests.
function Client:close()
  self._closed = true
  pool.close_idle(self)
end

--- Closes at the end of a `<close>` scope.
function Client:__close() self:close() end

return core.finalise(Client)
