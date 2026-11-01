-- The incremental HTTP/1.1 message parser: a thin wrapper over the llhttp binding (ADR 0019, csrc/native.c).
-- llhttp runs in strict mode and no lenient flag is reachable. The parser turns bytes into events (a head, data,
-- the end of the message, trailers, an upgrade) and never raises for malformed input: it returns a ParseError, which
-- the server answers with `context.status` and a closed connection (RFC 9112 section 9.6 and 11.2).
global <const> require, type, error, ipairs, pcall, tostring, string

local core = require("hecate.core")
local Fields = require("hecate.http.fields")
local errors = require("hecate.http.errors")
local native = require("hecate.http.native")

local ParseError = errors.ParseError

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

--- Limits of the parser; every one has a safe default. Each is an integer between 1 and 16777216; an unknown key is
--- an `ArgumentError`.
---@class hecate.http.parser.Options
---@field max_target_size? integer  request target, bytes (default 8192; over it: 414)
---@field max_field_size? integer  one field name or value, or the reason phrase, bytes (default 8192; over it: 431)
---@field max_head_size? integer  raw bytes of a section, whitespace included: a head from its first byte to its end
---  (empty lines before the request line included), the bytes between two chunks of content (size digits and
---  extensions), a trailer section (default 65536; over it: 431)
---@field max_fields? integer  fields in a head or a trailer section (default 100; over it: 431)
---@field max_events? integer  events the native parser records before it pauses and `feed` continues (default 1024)

--- An incremental parser of one direction of one connection.
---@class hecate.http.Parser
---@field ParseError hecate.http.ParseError
local Parser = core.class("Parser")
Parser.ParseError = ParseError

---@param handle table  the native parser
---@param kind string
function Parser:init(handle, kind)
  self._handle = handle
  self._kind = kind
end

-- Status to answer with, by the stable identifier of a failure of the binding (never by matching its text).
local STATUS_OF_KIND = {
  target_too_long = 414,
  field_name_too_large = 431,
  field_value_too_large = 431,
  head_too_large = 431,
  too_many_fields = 431,
  out_of_memory = 500,
  no_progress = 500,
}

local function failure(raw)
  return ParseError({
    message = "http.Parser:feed: message rejected: " .. raw.reason,
    context = {
      reason = raw.kind or (raw.code and string.lower((string.gsub(raw.code, "^HPE_", ""))) or "parse_error"),
      detail = raw.reason,
      code = raw.code,
      position = raw.position,
      status = STATUS_OF_KIND[raw.kind] or 400,
    },
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
          message = "http.Parser:feed: message rejected: field refused by the message model",
          context = { reason = "invalid_field", detail = "invalid field", code = "HPE_INVALID_HEADER_TOKEN", position = 0, status = 400 },
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
    -- Nothing from a message that failed before its end is delivered: events are kept up to the last message that
    -- finished (those of earlier pipelined messages stay).
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
    error(core.ArgumentError("http.Parser.new: kind must be \"request\" or \"response\""), 2)
  end
  if options ~= nil and type(options) ~= "table" then
    error(core.ArgumentError("http.Parser.new: options must be a table"), 2)
  end
  local ok, handle = pcall(native.new, kind, options)
  if not ok then error(core.ArgumentError("http.Parser.new: " .. tostring(handle)), 2) end
  return Parser(handle, kind)
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
    error(core.ArgumentError("http.Parser:feed: expected a string, got " .. type(chunk)), 2)
  end
  local handle = self._handle
  if self._terminal ~= nil then return {}, self._terminal end
  local all, start, raw, stalled = {}, 0, nil, false
  for _ = 1, #chunk + 2 do
    local events, failed, consumed = handle:execute(chunk, start)
    for _, event in ipairs(events) do all[#all + 1] = event end
    raw = failed
    if failed ~= nil or consumed >= #chunk then break end
    if consumed <= start then
      -- No progress and no failure: a defect of the binding. Never loop on it: fail, and stay failed.
      raw = { reason = "the native parser made no progress", code = "HPE_INTERNAL", kind = "no_progress", position = start }
      stalled = true
      break
    end
    start = consumed
  end
  local events, err = result(all, raw)
  if stalled then self._terminal = err end
  return events, err
end

--- Tells the parser that the peer closed the connection. Returns the events that closing completes (a response
--- whose content ends with the connection) and a `ParseError` when a message was cut short.
---@return hecate.http.parser.Event[] events
---@return hecate.http.ParseError? err
function Parser:finish()
  if self._terminal ~= nil then return {}, self._terminal end
  local events, failed = self._handle:finish()
  return result(events, failed)
end

--- Declares that the next final response (status 200 or above) has no content whatever its fields say: the response to
--- a HEAD request or a 304 (RFC 9112 section 6.3, rule 1). An interim response (1xx) does not consume it.
--- Raises `hecate.core.ArgumentError` on a parser of requests.
function Parser:skip_content()
  if self._kind ~= "response" then error(core.ArgumentError("http.Parser:skip_content is for a parser of responses"), 2) end
  self._handle:skip_content()
end

--- Reports whether a message has begun and not yet ended: the bytes of a head, or of content, are still expected. After a
--- chunk whose last message completed this is false; with the first bytes of the next head already fed it is true.
---@return boolean
function Parser:in_message()
  return self._handle:in_message()
end

--- Releases the memory of the parser. Calling `feed`, `finish` or `skip_content` afterwards raises; closing twice is
--- harmless. A parser that is not closed is released when it is collected.
function Parser:close()
  self._handle:close()
end

return core.finalise(Parser)
