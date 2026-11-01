-- The incremental HTTP/1.1 message parser: a thin wrapper over the llhttp binding (ADR 0019, csrc/native.c).
-- llhttp runs in strict mode and no lenient flag is reachable. The parser turns bytes into events (a head, data,
-- the end of the message, trailers, an upgrade) and never raises for malformed input: it returns a ParseError, which
-- the server answers with `context.status` and a closed connection (RFC 9112 section 9.6 and 11.2).
global <const> require, type, error, ipairs, pcall, tostring

local core = require("hecate.core")
local Fields = require("hecate.http.fields")
local native = require("hecate.http.native")

--- A message that is not valid HTTP/1.1, or that exceeds a limit of the parser.
---
--- `context.reason` is the llhttp reason (or the limit that was exceeded), `context.code` the llhttp error name,
--- `context.position` the 0-based offset in the chunk where the parse failed, and `context.status` the status code to
--- answer with: 414 for a request target over its limit, 431 for a field, a head or a field count over its limit,
--- 400 otherwise (RFC 9110 sections 15.5.1, 15.5.15 and 15.5.32).
---@class hecate.http.ParseError : hecate.core.Error
---@field context { reason: string, code: string, position: integer, status: integer }
local ParseError = core.error_class("ParseError", "hecate.http.ParseError")

--- The head of a message (request line or status line, and its fields).
---@class hecate.http.parser.Head
---@field type "head"
---@field method? string  requests
---@field target? string  requests, as received (RFC 9112 section 3.2)
---@field status? integer  responses
---@field reason? string  responses
---@field version string  "HTTP/1.0" or "HTTP/1.1"
---@field fields hecate.http.Fields
---@field keep_alive boolean  whether the connection stays open after this message (RFC 9112 section 9.3)
---@field upgrade boolean  the message asks to leave HTTP (Upgrade, or CONNECT)
---@field chunked boolean  the content is chunked
---@field content_length? integer  the declared Content-Length

--- A piece of the content.
---@class hecate.http.parser.Data
---@field type "data"
---@field data string

--- The end of a message.
---@class hecate.http.parser.Complete
---@field type "complete"
---@field trailers? hecate.http.Fields  the trailer section, when there was one (RFC 9112 section 7.1.2)

--- The connection leaves HTTP: the bytes of the chunk after `position` belong to the new protocol.
---@class hecate.http.parser.Upgrade
---@field type "upgrade"
---@field position integer  0-based offset in the chunk just fed

---@alias hecate.http.parser.Event hecate.http.parser.Head|hecate.http.parser.Data|hecate.http.parser.Complete|hecate.http.parser.Upgrade

--- Limits of the parser; every one has a safe default.
---@class hecate.http.parser.Options
---@field max_target_size? integer  request target, bytes (default 8192; over it: 414)
---@field max_field_size? integer  one field name or value, bytes (default 8192; over it: 431)
---@field max_head_size? integer  all field names and values of a head or of a trailer section, bytes (default 65536; 431)
---@field max_fields? integer  fields in a head or a trailer section (default 100; 431)

--- An incremental parser of one direction of one connection.
---@class hecate.http.Parser
---@field native table  the llhttp binding (hecate.http.native); not part of the public API
---@field ParseError hecate.http.ParseError
local Parser = core.class("Parser")
Parser.ParseError = ParseError
Parser.native = native

---@param handle table  the native parser
function Parser:init(handle)
  self._handle = handle
end

local TOO_LARGE_TARGET = { ["request target too long"] = 414 }
local TOO_LARGE_FIELD = {
  ["field name too large"] = true,
  ["field value too large"] = true,
  ["header section too large"] = true,
  ["too many fields"] = true,
  ["reason phrase too long"] = true,
}

local function failure(raw)
  local status = TOO_LARGE_TARGET[raw.reason] or (TOO_LARGE_FIELD[raw.reason] and 431) or 400
  return ParseError({
    message = "HTTP message rejected: " .. raw.reason,
    context = { reason = raw.reason, code = raw.code, position = raw.position, status = status },
  })
end

local function to_fields(flat)
  local fields = Fields()
  for i = 1, #flat, 2 do fields:add(flat[i], flat[i + 1]) end
  return fields
end

-- Replaces the raw field lists of the events by Fields. Returns a ParseError when llhttp accepted a field the
-- message model refuses (it does not happen for a token name and a value without CR, LF and NUL, which llhttp enforces).
local function convert(events)
  for _, event in ipairs(events) do
    local flat = event.fields or event.trailers
    if flat then
      local ok, fields = pcall(to_fields, flat)
      if not ok then
        return ParseError({
          message = "HTTP message rejected: field refused by the message model",
          context = { reason = "invalid field", code = "HPE_INVALID_HEADER_TOKEN", position = 0, status = 400 },
        })
      end
      if event.fields then event.fields = fields else event.trailers = fields end
    end
  end
  return nil
end

local function result(events, raw)
  local err = convert(events)
  if err == nil and raw ~= nil then err = failure(raw) end
  if err ~= nil then
    -- Nothing from a message that failed in its head is delivered: a head event is kept only when its message
    -- finished before the failure (events of earlier pipelined messages stay).
    local complete = {}
    local pending = {}
    for _, event in ipairs(events) do
      pending[#pending + 1] = event
      if event.type == "complete" then
        for _, kept in ipairs(pending) do complete[#complete + 1] = kept end
        pending = {}
      end
    end
    events = complete
  end
  return events, err
end

--- Creates a parser.
---
--- Raises `hecate.core.ArgumentError` for an unknown kind or an invalid limit.
---@param kind "request"|"response"
---@param options? hecate.http.parser.Options
---@return hecate.http.Parser
function Parser.new(kind, options)
  if kind ~= "request" and kind ~= "response" then
    error(core.ArgumentError("http.Parser: kind must be \"request\" or \"response\""), 2)
  end
  local native_options
  if options ~= nil then
    native_options = {
      max_target_size = options.max_target_size,
      max_field_size = options.max_field_size,
      max_head_size = options.max_head_size,
      max_fields = options.max_fields,
    }
  end
  local ok, handle = pcall(native.new, kind, native_options)
  if not ok then error(core.ArgumentError("http.Parser: " .. tostring(handle)), 2) end
  return Parser(handle)
end

--- A parser of requests (the server side).
---@param options? hecate.http.parser.Options
---@return hecate.http.Parser
function Parser.request(options) return Parser.new("request", options) end

--- A parser of responses (the client side).
---@param options? hecate.http.parser.Options
---@return hecate.http.Parser
function Parser.response(options) return Parser.new("response", options) end

--- Feeds bytes. Returns the events they complete, in order, and a `ParseError` when the bytes are not valid
--- HTTP/1.1 or exceed a limit. The events returned with an error are those of messages that finished before it; once an
--- error is returned the parser keeps returning it, and the connection is to be closed.
---
--- Raises `hecate.core.ArgumentError` when `chunk` is not a string.
---@param chunk string
---@return hecate.http.parser.Event[] events
---@return hecate.http.ParseError? err
function Parser:feed(chunk)
  if type(chunk) ~= "string" then
    error(core.ArgumentError("http.Parser:feed expects a string, got " .. type(chunk)), 2)
  end
  return result(self._handle:execute(chunk))
end

--- Tells the parser that the peer closed the connection. Returns the events that closing completes (a response
--- whose content ends with the connection) and a `ParseError` when a message was cut short.
---@return hecate.http.parser.Event[] events
---@return hecate.http.ParseError? err
function Parser:finish()
  return result(self._handle:finish())
end

--- Declares that the next message has no content whatever its fields say: the response to a HEAD request or a
--- 304 (RFC 9112 section 6.3, rule 1).
function Parser:skip_body()
  self._handle:skip_body()
end

return core.finalise(Parser)
