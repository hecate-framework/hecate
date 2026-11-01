-- multipart/form-data (RFC 7578), with the delimiters of RFC 2046 section 5.1 and the parameters of RFC 6266 and RFC 8187.
-- A streaming parser: it pulls chunks from a content stream only when a consumer asks, keeps at most one chunk, the
-- header block of a part and the tail of a possible delimiter in memory, and finds delimiters with a plain search
-- (CRLF "--" boundary), so a boundary inside content is content unless a line break and a valid ending frame it.
global <const> require, type, error, pcall, string, table, math, ipairs, pairs, tostring, tonumber, utf8

local core = require("hecate.core")
local Fields = require("hecate.http.fields")
local MediaType = require("hecate.http.media_type")
local ContentStream = require("hecate.http.content")
local form = require("hecate.http.form")

local failure = form.failure

--- Limits of the multipart parser, with their defaults.
---@class hecate.http.multipart.Limits
---@field max_parts? integer  parts in a message (default 100; over it: 413)
---@field max_header_size? integer  bytes of the header block of one part (default 8192; over it: 413)
---@field max_part_size? integer  bytes of the content of one part (default 1048576; over it: 413 `ContentError`)
---@field max_total_size? integer  bytes of the whole message (default 1048576; over it: 413). The `max_content` of the
---  server applies first.

--- Parts and delimiters of multipart/form-data.
---@class hecate.http.multipart
local multipart = {}

--- Defaults of the limits.
multipart.DEFAULTS = { max_parts = 100, max_header_size = 8192, max_part_size = 1048576, max_total_size = 1048576 }

local MAX_PADDING <const> = 64 -- transport padding after a delimiter (RFC 2046 section 5.1.1), bounded

-- A boundary: 1 to 70 characters of RFC 2046 `bchars`, the space excluded (a trailing space is not allowed and a
-- space inside is refused as well: nothing sends it and it is a parsing trap).
local function valid_boundary(boundary)
  return type(boundary) == "string" and #boundary >= 1 and #boundary <= 70 and string.find(boundary, "^[%w'()+_,%-./:=?]+$") ~= nil
end

--- Returns the `boundary` parameter of a `multipart/form-data` media type.
---
--- Raises `hecate.http.FormError`: `unsupported_media_type` (415) for any other type, `bad_boundary` (400) when the
--- parameter is missing, empty, longer than 70 characters or holds characters RFC 2046 does not allow.
---@param media hecate.http.MediaType?  nil (an absent or unparsable `Content-Type`) is refused as unsupported
---@return string boundary
function multipart.boundary_of(media)
  if media == nil or media:essence() ~= "multipart/form-data" then
    error(failure("unsupported_media_type", "the content is not multipart/form-data"), 2)
  end
  local boundary = media.parameters.boundary
  if not valid_boundary(boundary) then error(failure("bad_boundary", "the boundary is missing or not valid"), 2) end
  return boundary
end

--- A name that is safe to use as the last element of a path, from a filename a client sent: directories (both `/` and
--- `\`), control characters and leading dots are removed. Returns nil when nothing is left. The package never opens a
--- file by this name or any other: the caller decides, and should still not use a client's name as a path.
---@param filename string?
---@return string?
function multipart.basename(filename)
  if type(filename) ~= "string" then return nil end
  local name = string.match(filename, "([^/\\]*)$")
  name = string.gsub(name, "[%c\127]", "")
  name = string.gsub(name, "^%.+", "")
  if name == "" then return nil end
  return name
end

-- Parts -----------------------------------------------------------------------------------------------------------

--- One part of a message.
---@class hecate.http.multipart.Part
---@field name string  the `name` of its `Content-Disposition` (raw: browsers percent-encode `"` and line breaks)
---@field filename? string  the `filename`, or the decoded `filename*`: RAW and never to be trusted
---@field content_type? string  the `Content-Type` field of the part, as sent
---@field fields hecate.http.Fields  every field of the part
local Part = core.class("Part")

---@param name string
---@param filename string?
---@param fields hecate.http.Fields
---@param content hecate.http.ContentStream
function Part:init(name, filename, fields, content)
  self.name, self.filename, self.fields = name, filename, fields
  self.content_type = fields:get("Content-Type")
  self._content = content
end

--- The content of the part as a stream (limited by `max_part_size`).
---@return hecate.http.ContentStream
function Part:stream_content() return self._content end

--- The whole content of the part, bounded by `limit` and by `max_part_size`.
---
--- Raises `hecate.http.ContentError` (413) beyond the limit and `hecate.http.FormError` when the message is cut.
---@async
---@param limit? integer
---@return string
function Part:read_content(limit) return self._content:read_all(limit) end

--- `multipart.basename` of the filename, or nil.
---@return string?
function Part:safe_filename() return multipart.basename(self.filename) end

Part = core.finalise(Part)

-- The parser ------------------------------------------------------------------------------------------------------

--- A reader of the parts of a message, over a content stream.
---@class hecate.http.multipart.Reader
---@overload fun(source: hecate.http.ContentStream, boundary: string, limits?: hecate.http.multipart.Limits): hecate.http.multipart.Reader
local Reader = core.class("MultipartReader")

--- Creates a reader. `source` is a `ContentStream` (`request:stream_content()`); nothing is read yet.
---
--- Raises `hecate.http.FormError` (`bad_boundary`) for a boundary RFC 2046 does not allow, and
--- `hecate.core.ArgumentError` for bad limits.
---@param source hecate.http.ContentStream
---@param boundary string
---@param limits? hecate.http.multipart.Limits
function Reader:init(source, boundary, limits)
  if not valid_boundary(boundary) then error(failure("bad_boundary", "the boundary is missing or not valid"), 3) end
  if limits ~= nil and type(limits) ~= "table" then error(core.ArgumentError("http.multipart.Reader: limits must be a table"), 3) end
  local resolved = {}
  for key, default in pairs(multipart.DEFAULTS) do resolved[key] = default end
  for key, value in pairs(limits or {}) do
    if multipart.DEFAULTS[key] == nil or math.type(value) ~= "integer" or value < 0 then
      error(core.ArgumentError("http.multipart.Reader: invalid limit " .. tostring(key)), 3)
    end
    resolved[key] = value
  end
  self._source = source
  self._limits = resolved
  self._delimiter = "\r\n--" .. boundary
  self._buffer = "\r\n" -- the first delimiter needs no line break before it (RFC 2046 section 5.1.1)
  self._total = 0
  self._eof = false
  self._parts = 0
  self._phase = "preamble" -- preamble, delimiter (just after one), headers, body, done
  self._current = nil
  self._failure = nil
end

local function truncated()
  return failure("truncated", "the multipart message ended before its final boundary")
end

--- Appends the next chunk of the source; false at its end.
---@async
function Reader:_more()
  if self._eof then return false end
  local chunk = self._source:read()
  if chunk == nil then
    self._eof = true
    return false
  end
  self._total = self._total + #chunk
  if self._total > self._limits.max_total_size then error(failure("total_too_large", "the multipart message exceeds its size limit"), 0) end
  self._buffer = self._buffer .. chunk
  return true
end

--- What follows a delimiter occurrence at `after`: "final" (`--`), "part" (optional blanks, then a line break), "no" (anything
--- else: the occurrence is content), or nil when the buffer is too short to tell.
---@param buffer string
---@param after integer
---@return string?
local function classify(buffer, after)
  local two = string.sub(buffer, after, after + 1)
  if two == "--" then return "final" end
  if two == "" or two == "-" then return nil end
  local padding = string.match(buffer, "^[ \t]*", after)
  if #padding > MAX_PADDING then return "no" end
  local following = string.sub(buffer, after + #padding, after + #padding + 1)
  if following == "\r\n" then return "part" end
  if following == "" or following == "\r" then return nil end
  return "no"
end

--- Looks for a delimiter in the buffer. Returns `"final"` or `"part"`, the index where it starts and the index just after
--- its text (before what follows it); or nil and the number of leading bytes that are surely content (the tail that could
--- be the start of a delimiter stays). An occurrence counts only when `--` or optional blanks and a line break follow it.
---@async
function Reader:_find()
  local delimiter = self._delimiter
  local from = 1
  while true do
    local buffer = self._buffer
    local start = string.find(buffer, delimiter, from, true)
    if start == nil then return nil, math.max(0, #buffer - #delimiter + 1) end
    local after = start + #delimiter
    local kind = classify(buffer, after)
    if kind == nil then
      if not self:_more() then kind = "no" end -- the stream ended: what follows is all there will be
    end
    if kind == "final" or kind == "part" then return kind, start, after end
    if kind == "no" then from = start + 1 end
  end
end

--- Consumes the text after a delimiter that `_find` classified: the closing `--`, or blanks and the line break.
function Reader:_consume_follow(kind, after)
  local buffer = self._buffer
  if kind == "final" then
    self._buffer = ""
    self._phase = "done"
  else
    local padding = string.match(buffer, "^[ \t]*", after)
    self._buffer = string.sub(buffer, after + #padding + 2)
    self._phase = "headers"
  end
end

--- Moves to the first delimiter, skipping the preamble.
---@async
function Reader:_skip_preamble()
  while true do
    local kind, start, after = self:_find()
    if kind ~= nil then
      self:_consume_follow(kind, after)
      return
    end
    local safe = start --[[@as integer]]
    self._buffer = string.sub(self._buffer, safe + 1)
    if not self:_more() then error(truncated(), 0) end
  end
end

-- The parameters of a Content-Disposition, read with the media type parser (quoted strings, escapes, first wins).
local function parse_disposition(value)
  local media = MediaType.parse("content-disposition/" .. value)
  if media == nil or media.subtype ~= "form-data" then return nil end
  return media.parameters
end

local function decode_extended(value)
  local charset, rest = string.match(value, "^([%w%-]+)'[%w%-]*'(.*)$")
  if charset == nil or string.lower(charset) ~= "utf-8" then return nil end
  if string.find(rest, "%%%x?[^%x]") or string.find(rest, "%%%x?$") then return nil end
  local text = string.gsub(rest, "%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
  if not utf8.len(text) or string.find(text, "%z") then return nil end
  return text
end

---@param block string  the header lines of a part, without the final blank line
---@return string name
---@return string? filename
---@return hecate.http.Fields fields
local function parse_headers(block)
  local fields = Fields()
  if block ~= "" then
    for line in string.gmatch(block .. "\r\n", "(.-)\r\n") do
      local name, value = string.match(line, "^([^:]+):(.*)$")
      if name == nil or string.find(line, "[\r\n%z]") then error(failure("bad_part_header", "a part has a malformed header field"), 0) end
      local ok = pcall(fields.add, fields, name, value)
      if not ok then error(failure("bad_part_header", "a part has a malformed header field"), 0) end
    end
  end
  local disposition = fields:get("Content-Disposition")
  if disposition == nil then error(failure("missing_name", "a part has no Content-Disposition"), 0) end
  local parameters = parse_disposition(disposition)
  if parameters == nil then error(failure("bad_part_header", "a part is not form-data"), 0) end
  local name = parameters.name
  if name == nil then error(failure("missing_name", "a part has no name"), 0) end
  local filename = parameters.filename
  if parameters["filename*"] ~= nil then filename = decode_extended(parameters["filename*"]) or filename end
  for _, text in ipairs({ name, filename or "" }) do
    if string.find(text, "%z") then error(failure("bad_part_header", "a part name holds a NUL byte"), 0) end
  end
  return name, filename, fields
end

---@async
function Reader:_read_headers()
  local limit = self._limits.max_header_size
  while true do
    local buffer = self._buffer
    if string.sub(buffer, 1, 2) == "\r\n" then return "" end -- no header fields; the CRLF is the separator of the content
    local stop = string.find(buffer, "\r\n\r\n", 1, true)
    if stop ~= nil then
      if stop - 1 > limit then error(failure("part_header_too_large", "a part header block exceeds its size limit"), 0) end
      self._buffer = string.sub(buffer, stop + 2) -- the last CRLF stays: it separates the header fields from the content
      return string.sub(buffer, 1, stop - 1)
    end
    if #buffer > limit + 3 then error(failure("part_header_too_large", "a part header block exceeds its size limit"), 0) end
    if not self:_more() then error(truncated(), 0) end
  end
end

--- Pulls the next piece of the content of the current part: a chunk, or nil at its delimiter.
---@async
function Reader:_pull_content()
  local part = self._current
  if part.done then return nil end
  while true do
    local kind, start, after = self:_find()
    if not part.started and not (kind ~= nil and start == 1) then
      -- The buffer starts with the CRLF that separates the header fields from the content (RFC 2046 section 5.1.1:
      -- `[CRLF *OCTET]`), unless the delimiter follows at once (no content). Drop it and look again.
      part.started = true
      self._buffer = string.sub(self._buffer, 3)
      goto again
    end
    part.started = true
    if kind ~= nil then
      local chunk = string.sub(self._buffer, 1, start - 1)
      self._buffer = string.sub(self._buffer, start) -- keeps the delimiter for `_consume_follow`
      part.done = true
      self._pending = { kind = kind, after = after - start + 1 }
      if chunk ~= "" then return chunk end
      return nil
    end
    local safe = start --[[@as integer]]
    if safe > 0 then
      local chunk = string.sub(self._buffer, 1, safe)
      self._buffer = string.sub(self._buffer, safe + 1)
      return chunk
    end
    if not self:_more() then error(truncated(), 0) end
    ::again::
  end
end

--- The next part, or nil after the last one. A part the caller did not read to its end is skipped (within
--- `max_part_size`). Any failure is sticky.
---
--- Raises `hecate.http.FormError` (see `context.kind`): `truncated`, `bad_part_header`, `missing_name`,
--- `too_many_parts`, `part_header_too_large`, `total_too_large`; `hecate.http.ContentError` for a part over
--- `max_part_size`; and what the source raises (a deadline, a transport failure).
---@async
---@return hecate.http.multipart.Part?
function Reader:next_part()
  if self._failure ~= nil then error(self._failure, 0) end
  local ok, result = pcall(function()
    if self._current ~= nil then
      local stream = self._current.stream
      while not stream:is_finished() do stream:read() end
      self._current = nil
      self:_consume_follow(self._pending.kind, self._pending.after)
    end
    if self._phase == "preamble" then self:_skip_preamble() end
    if self._phase == "done" then return nil end
    self._parts = self._parts + 1
    if self._parts > self._limits.max_parts then error(failure("too_many_parts", "the message has too many parts"), 0) end
    local name, filename, fields = parse_headers(self:_read_headers())
    local state = { done = false }
    local stream = ContentStream(function() return self:_pull_content() end, { limit = self._limits.max_part_size })
    state.stream = stream
    self._current = state
    self._phase = "body"
    return Part(name, filename, fields, stream)
  end)
  if not ok then
    self._failure = result
    error(result, 0)
  end
  if result == nil then self._phase = "done" end
  return result
end

--- Creates a reader over `source` for the media type of the request (`multipart.boundary_of` then `Reader`).
---@param source hecate.http.ContentStream
---@param media hecate.http.MediaType?
---@param limits? hecate.http.multipart.Limits
---@return hecate.http.multipart.Reader
function multipart.parts(source, media, limits)
  return Reader(source, multipart.boundary_of(media), limits)
end

multipart.Reader = core.finalise(Reader)
multipart.Part = Part

-- Building (the client) -------------------------------------------------------------------------------------------

-- Browsers percent-encode the double quote and the line breaks in names and filenames (WHATWG HTML, multipart/form-data
-- encoding algorithm); a NUL byte is refused.
local function quote(text, what)
  if type(text) ~= "string" or string.find(text, "%z") then
    error(core.ArgumentError("http.multipart.build: " .. what .. " must be a string without NUL"), 3)
  end
  return (string.gsub(text, '[%c"]', function(c)
    if c == '"' or c == "\r" or c == "\n" then return string.format("%%%02X", string.byte(c)) end
    return c
  end))
end

local function random_boundary()
  local out = {}
  for i = 1, 32 do out[i] = string.format("%x", math.random(0, 15)) end
  return "hecate-" .. table.concat(out)
end

--- Builds a multipart/form-data message from a list of parts `{ name, filename?, content_type?, content }`, where
--- `content` is a string or a function `content(write)` that streams. Returns the content (one string when every
--- part is a string, else a function that writes the message in pieces) and the `Content-Type` value. The boundary is
--- random and verified absent from the string parts; a function part cannot be checked (the boundary has 128 random
--- bits).
---
--- Raises `hecate.core.ArgumentError` for a part without a name, a name or filename with NUL, a content type with CR,
--- LF or NUL, or content that is neither a string nor a function.
---@param parts table[]
---@return string|fun(write: fun(chunk: string)) content
---@return string content_type
function multipart.build(parts)
  if type(parts) ~= "table" then error(core.ArgumentError("http.multipart.build expects a list of parts"), 2) end
  local heads, streaming = {}, false
  for i, part in ipairs(parts) do
    if type(part) ~= "table" then error(core.ArgumentError("http.multipart.build: a part is a table"), 2) end
    if type(part.name) ~= "string" then error(core.ArgumentError("http.multipart.build: a part needs a name"), 2) end
    local head = 'Content-Disposition: form-data; name="' .. quote(part.name, "a name") .. '"'
    if part.filename ~= nil then head = head .. '; filename="' .. quote(part.filename, "a filename") .. '"' end
    if part.content_type ~= nil then
      if type(part.content_type) ~= "string" or string.find(part.content_type, "[%c]") then
        error(core.ArgumentError("http.multipart.build: a content type is a string without control characters"), 2)
      end
      head = head .. "\r\nContent-Type: " .. part.content_type
    end
    if type(part.content) == "function" then
      streaming = true
    elseif type(part.content) ~= "string" then
      error(core.ArgumentError("http.multipart.build: the content of a part is a string or a function"), 2)
    end
    heads[i] = head
  end
  local boundary
  for _ = 1, 8 do
    local candidate = random_boundary()
    local clash = false
    for _, part in ipairs(parts) do
      if type(part.content) == "string" and string.find(part.content, candidate, 1, true) then clash = true end
    end
    if not clash then boundary = candidate break end
  end
  if boundary == nil then error(core.Error("http.multipart.build: no boundary absent from the parts was found"), 2) end
  local function emit(write)
    for i, part in ipairs(parts) do
      write("--" .. boundary .. "\r\n" .. heads[i] .. "\r\n\r\n")
      if type(part.content) == "function" then part.content(write) else write(part.content) end
      write("\r\n")
    end
    write("--" .. boundary .. "--\r\n")
  end
  local content_type = "multipart/form-data; boundary=" .. boundary
  if streaming then return emit, content_type end
  local pieces = {}
  emit(function(chunk) pieces[#pieces + 1] = chunk end)
  return table.concat(pieces), content_type
end

return multipart
