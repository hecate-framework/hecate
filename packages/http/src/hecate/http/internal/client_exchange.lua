-- One exchange of the client: the request written on a pooled or new connection, the response head, and the response
-- whose content stream hands the connection back to the pool (RFC 9112, sections 6 and 9; RFC 9110, section 10.1.1).
-- Internal to `hecate.http`: not public API. Only `client.lua` and the other `internal/client_*` modules require it.
global <const> require, type, error, pcall, math, string, table

local core = require("hecate.core")
local reactor = require("hecate.reactor")
local Response = require("hecate.http.response")
local Status = require("hecate.http.status")
local ContentStream = require("hecate.http.content")
local ContentError = ContentStream.ContentError
local wire = require("hecate.http.wire")
local connections = require("hecate.http.internal.client_connection")
local pool = require("hecate.http.internal.client_pool")

local bounded, next_event = connections.bounded, connections.next_event
local end_of_stream, protocol_error = connections.end_of_stream, connections.protocol_error
local checkin, drop = pool.checkin, pool.drop

---@class hecate.http.internal.client_exchange
local M = {}

local IDEMPOTENT <const> = { GET = true, HEAD = true, PUT = true, DELETE = true, OPTIONS = true, TRACE = true }

---@async
local function write(self, conn, state, data)
  if data == "" then return end
  reactor.deadline(bounded(state, self._write_timeout), conn.stream.write, conn.stream, data)
end

--- Writes the request: the head, then the content (a string with its length, a function chunked).
---@async
local function write_request(self, conn, state, method, parts, fields, content)
  local head = { method, " ", parts.target, " HTTP/1.1\r\nHost: ", parts.authority, "\r\n" }
  for name, value in fields:lines() do head[#head + 1] = name .. ": " .. value .. "\r\n" end
  -- RFC 9110 section 10.1.1: ask the server for its 100 Continue (or a final status) before the content is sent; a field the
  -- caller gave is kept as it is, never duplicated.
  if state.expect and content ~= nil and not fields:has("Expect") then head[#head + 1] = "Expect: 100-continue\r\n" end
  if type(content) == "string" then
    head[#head + 1] = "Content-Length: " .. #content .. "\r\n"
  elseif type(content) == "function" then
    head[#head + 1] = "Transfer-Encoding: chunked\r\n"
  elseif method == "POST" or method == "PUT" or method == "PATCH" then
    head[#head + 1] = "Content-Length: 0\r\n"
  end
  head[#head + 1] = "\r\n"
  local text = table.concat(head)
  local expecting = state.expect and content ~= nil
  if expecting then
    write(self, conn, state, text)
    -- RFC 9110 section 10.1.1: wait for 100 Continue, or a final status that makes the content useless, or give up. Other
    -- interim responses (102, 103) are skipped; a connection that ends meanwhile is a failure.
    local give_up = reactor.now() + self._expect_timeout
    while true do
      local ok, event, err = pcall(next_event, conn, bounded(state, math.max(0, give_up - reactor.now())))
      if not ok then
        if core.is_instance_of(event, core.DeadlineExceededError) then break end
        error(event, 0)
      end
      if event == nil then
        if err == "eof" then error(end_of_stream("the connection closed before the request content was sent"), 0) end
        error(err, 0)
      end
      if event.type == "head" and event.status == 100 then
        next_event(conn, bounded(state, self._expect_timeout)) -- its `complete`
        break
      elseif event.type == "head" and event.status < 200 then
        next_event(conn, bounded(state, self._expect_timeout)) -- skip it and its `complete`
      elseif event.type == "head" then
        conn.early = event -- a final answer: the content is not sent and the connection not reused
        conn.reusable = false
        return
      else
        error(protocol_error("unexpected data while waiting for 100 Continue", "unexpected_data"), 0)
      end
    end
    text = ""
  end
  if type(content) == "string" then
    write(self, conn, state, text .. content)
  elseif type(content) == "function" then
    write(self, conn, state, text)
    local function send(chunk)
      if type(chunk) ~= "string" then error(core.ArgumentError("http.Client: a chunk of content must be a string"), 2) end
      write(self, conn, state, wire.chunk(chunk))
    end
    content(send)
    write(self, conn, state, wire.LAST_CHUNK)
  else
    write(self, conn, state, text)
  end
end

--- Reads the response head, skipping interim responses.
---@async
local function read_head(self, conn, state, method)
  local limit = reactor.now() + state.head_timeout
  local skip_complete = false
  while true do
    local event, err
    if conn.early ~= nil then
      event, conn.early = conn.early, nil
    else
      event, err = next_event(conn, bounded(state, math.max(0, limit - reactor.now())))
    end
    if event == nil then
      if err == "eof" then
        if conn.received == 0 then error(end_of_stream("the connection closed before the response"), 0) end
        error(end_of_stream("the connection closed inside the response head"), 0)
      end
      error(err, 0)
    end
    if event.type == "head" then
      if not Status.is_valid(event.status) then
        error(core.ProtocolError({ message = "http.Client: the response status is not a valid status code", context = { reason = "status" } }), 0)
      end
      -- OQ-67: the reason phrase carries no control character (RFC 9112 section 4); llhttp lets them through.
      if event.reason ~= nil and string.find(event.reason, "[%c\127]") and not string.find(event.reason, "^[\t%g ]*$") then
        error(core.ProtocolError({ message = "http.Client: the response reason phrase holds control characters", context = { reason = "reason_phrase" } }), 0)
      end
      if event.status == 101 then
        error(core.ProtocolError({ message = "http.Client: unexpected 101 Switching Protocols", context = { reason = "upgrade" } }), 0)
      end
      if event.status >= 200 then return event end
      skip_complete = true
    elseif event.type == "complete" and skip_complete then
      skip_complete = false
    elseif event.type == "upgrade" then
      error(core.ProtocolError({ message = "http.Client: the response switches protocols", context = { reason = "upgrade" } }), 0)
    else
      error(core.ProtocolError({ message = "http.Client: unexpected data before the response head", context = { reason = "unexpected_data" } }), 0)
    end
  end
end

--- Builds the response: its content stream pulls from the connection, which goes back to the pool when the content ends.
---@param head hecate.http.parser.Head
local function make_response(self, conn, state, head, final_url)
  local finished = false
  local function finish()
    if finished then return end
    finished = true
    if head.keep_alive and not wire.has_connection_option(state.fields:combined("Connection"), "close") then
      checkin(self, conn)
    else
      drop(conn)
    end
  end
  local function pull()
    if finished then return nil end
    while true do
      local seconds = bounded(state, state.content_timeout)
      local ok, event, err = pcall(next_event, conn, seconds)
      if not ok then
        drop(conn)
        finished = true
        -- The read deadline is this wait's own (an outer deadline cancels it instead): when `content_timeout`, not
        -- what is left of `request_timeout`, bounded it, the content stalled (OQ-82, as on the server).
        if seconds >= state.content_timeout and core.is_instance_of(event, core.DeadlineExceededError) then
          error(ContentError({
            message = "http.Client: the response content stalled longer than content_timeout",
            cause = event, context = { reason = "timeout" },
          }), 0)
        end
        error(event, 0)
      end
      if event == nil then
        drop(conn)
        finished = true
        if err == "eof" then error(end_of_stream("the connection closed inside the response content"), 0) end
        error(err, 0)
      end
      if event.type == "data" then return event.data end
      if event.type == "complete" then
        finish()
        return nil
      end
      drop(conn)
      finished = true
      error(core.ProtocolError({ message = "http.Client: unexpected event in the response content", context = { reason = "unexpected_event" } }), 0)
    end
  end
  local stream = ContentStream(pull, { limit = state.max_content, client = true }) -- max_content bounds `read_content` and `stream_content` alike
  local response = Response(head.status, {
    reason = head.reason, fields = head.fields, content_stream = stream, max_content = state.max_content,
    discard = function()
      if not finished then
        finished = true
        drop(conn)
      end
    end,
  })
  response.url = final_url
  -- No content (HEAD, 204, 304, a zero length): the message is complete already, give the connection back now.
  local nxt = conn.queue[conn.position]
  if nxt ~= nil and nxt.type == "complete" then
    conn.queue[conn.position] = nil
    conn.position = conn.position + 1
    finish()
    stream = nil
    response._content_stream = ContentStream.of("")
  end
  return response
end

--- One request and its response head on a pooled or new connection, retried once on a new connection when a reused one
--- turns out dead before any byte of the response arrived (idempotent methods and replayable content only).
---@async
---@param self hecate.http.Client
function M.exchange(self, parts, method, fields, content, state, final_url)
  local replayable = content == nil or type(content) == "string"
  for attempt = 1, 2 do
    local conn, reused = self:_checkout(parts, state)
    state.fields = fields
    conn.received = 0 -- counts the bytes of this exchange: a failure before any is safe to retry
    if method == "HEAD" then conn.parser:skip_content() end
    if wire.has_connection_option(fields:combined("Connection"), "close") then conn.reusable = false end
    local ok, result = pcall(function()
      write_request(self, conn, state, method, parts, fields, content)
      return read_head(self, conn, state, method)
    end)
    if ok then return make_response(self, conn, state, result, final_url) end
    local failure_before_bytes = conn.received == 0
    drop(conn)
    local transient = core.is_instance_of(result, core.NetworkError)
    if not (reused and attempt == 1 and IDEMPOTENT[method] and replayable and failure_before_bytes and transient) then
      error(result, 0)
    end
  end
end

return M
