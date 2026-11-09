-- The response writer of `hecate.http.Server`: framing, the head and the content of one response (RFC 9110, RFC 9112
-- section 6), and the problem answers sent before an action runs.
-- Internal to `hecate.http`: not public API. Only `server.lua` and the other `internal/server_*` modules require it.
-- Every function takes the server (`self`) first: it reads the settings and reports through `_report`.
global <const> require, type, error, pcall, ipairs, math, string, tostring, os

local core = require("hecate.core")
local reactor = require("hecate.reactor")
local problem = require("hecate.http.problem")
local wire = require("hecate.http.wire")

---@class hecate.http.internal.server_response
local M = {}

---@return boolean
local function is_cancellation(err) return core.is_instance_of(err, core.CancellationError) end

---@async
local function send(self, conn, data)
  if data == "" then return end
  conn.bytes = (conn.bytes or 0) + #data
  reactor.deadline(self._write_timeout, conn.writer.write, conn.writer, data)
end

---@async
local function flush(self, conn)
  reactor.deadline(self._write_timeout, conn.writer.flush, conn.writer)
end

---@type integer, string
local last_date_time, last_date = 0, ""
local function date_now()
  local now = os.time()
  if now ~= last_date_time then last_date_time, last_date = now, wire.http_date(now) end
  return last_date
end

local HOP_BY_HOP <const> = { "Connection", "Keep-Alive", "Proxy-Connection", "Transfer-Encoding", "Content-Length" }


--- Builds the functions given to a response whose content is a function: `write(chunk)` codes the chunk (or counts the
--- bytes of a declared length) and sends it, `flush()` pushes what is buffered to the client, `remaining()` is for the
--- server (bytes still owed under a declared length, or nil).
local function content_writer(server, conn, mode, remaining)
  local function write(data)
    if type(data) ~= "string" then error(core.ArgumentError("http.Server: a chunk of content must be a string"), 2) end
    if data == "" then return end
    if remaining ~= nil then
      remaining = remaining - #data
      if remaining < 0 then
        error(core.ArgumentError("http.Server: more bytes written than the declared Content-Length"), 2)
      end
      send(server, conn, data)
    elseif mode == "chunked" then
      send(server, conn, wire.chunk(data))
    else
      send(server, conn, data)
    end
  end
  local function flush_content() flush(server, conn) end
  return write, flush_content, function() return remaining end
end

--- Chooses how the content is framed (RFC 9112, section 6): the mode, and its text (the content, or the length).
---@param status integer
---@param content any
---@param declared string?  a Content-Length the action set
---@param version string  protocol version of the request
---@return string mode  none, declared_only, length, declared, chunked or close_delimited
---@return string? text
local function frame(status, content, declared, version)
  local has_declared = declared ~= nil and string.find(declared, "^%d+$") ~= nil
  if status < 200 or status == 204 then return "none" end
  if status == 304 then return has_declared and "declared_only" or "none", declared end
  local kind = type(content)
  if kind == "string" then return "length", content end
  if kind == "function" then
    if has_declared then return "declared", declared end
    return version == "HTTP/1.0" and "close_delimited" or "chunked"
  end
  return "length", ""
end

--- Normalises the frame and the fields of `response` as the answer to the request described by `info` (`method`,
--- `version`, `keep_alive`), without touching a socket. HEAD and the statuses 1xx, 204 and 304 never carry content (RFC
--- 9110, sections 9.3.2, 15.2, 15.3.5 and 15.4.5); a function without a declared length is chunked (RFC 9112, section
--- 7.1), or delimited by the close for HTTP/1.0. The framing fields of the action are replaced by the server's own:
--- `Content-Length`, `Transfer-Encoding` and `Connection` (RFC 9110, section 7.6.1), and `Date` is added (section 6.6.1).
--- Raises `hecate.core.ArgumentError` for content that is not nil, a string or a function (`dispatch` refuses it first).
---@param info { method?: string, version: string, keep_alive: boolean }
---@param response hecate.http.Response
---@param close boolean  close the connection after the response (forced, or the server is stopping)
---@return hecate.http.Fields fields  a copy: the response is not modified
---@return string mode  none, declared_only, length, declared, chunked or close_delimited
---@return string? text  the content (mode length) or the declared length
---@return boolean wants_close
local function normalise(info, response, close)
  local status = response.status
  local fields = response.fields:copy()
  local wants_close = close or not info.keep_alive
    or wire.has_connection_option(fields:combined("Connection"), "close")
  local declared = fields:get("Content-Length")
  for _, name in ipairs(HOP_BY_HOP) do fields:remove(name) end

  local kind = type(response.content)
  if not (response.content == nil or kind == "string" or kind == "function") then
    error(core.ArgumentError("http.Server: content must be nil, a string or a function"), 2)
  end
  local mode, text = frame(status, response.content, declared, info.version)
  if mode == "length" then
    fields:set("Content-Length", tostring(#(text --[[@as string]])))
  elseif mode == "declared" or mode == "declared_only" then
    fields:set("Content-Length", text --[[@as string]])
  elseif mode == "chunked" and info.method ~= "HEAD" then
    fields:set("Transfer-Encoding", "chunked")
  elseif mode == "close_delimited" then
    wants_close = true
  end
  if not fields:has("Date") then fields:set("Date", date_now()) end
  if wants_close then
    fields:set("Connection", "close")
  elseif info.version == "HTTP/1.0" then
    fields:set("Connection", "keep-alive")
  end
  return fields, mode, text, wants_close
end

--- Sends `response` as the answer to the request described by `info` and returns whether the connection stays open
--- (the frame and the fields come from `normalise`).
---@async
---@param info { method?: string, version: string, keep_alive: boolean }
---@param response hecate.http.Response
---@param force_close boolean
---@return boolean keep_alive
---@return boolean? failed  true when a content writer failed or stopped short (the head was sent)
local function write_response(self, conn, info, response, force_close)
  local fields, mode, text, wants_close = normalise(info, response, force_close or self._stopping)
  local head_request = info.method == "HEAD"

  send(self, conn, wire.head(response.status, response.reason, fields))
  if head_request or mode == "none" or mode == "declared_only" then
    flush(self, conn)
    return not wants_close
  end
  if mode == "length" then
    send(self, conn, text --[[@as string]])
    flush(self, conn)
    return not wants_close
  end

  flush(self, conn) -- the head reaches the client now: a streamed response is useful before its end
  local write, flush_content, remaining = content_writer(self, conn, mode, mode == "declared" and math.tointeger(text) or nil)
  local ok, err = pcall(response.content --[[@as function]], write, flush_content)
  if not ok then
    if is_cancellation(err) then error(err, 0) end
    self:_report("a content writer failed", err)
    pcall(flush, self, conn) -- what was written reaches the client, which sees the content cut short
    return false, true -- the head is sent: the client cannot be told, the connection is closed
  end
  if mode == "declared" and remaining() ~= 0 then
    self:_report("a content writer stopped before the declared Content-Length", "short content")
    pcall(flush, self, conn)
    return false, true
  end
  if mode == "chunked" then send(self, conn, wire.LAST_CHUNK) end
  flush(self, conn)
  return not wants_close
end

--- Sends `response` (see `write_response`) and calls the `on_response` hook once with what happened: `method`, `target`,
--- `status`, `bytes` written (head included), `duration` in seconds including the sending, `failed` (the write failed,
--- the connection ended, or a content writer failed) and `refused` (an answer sent before any action ran, OQ-81). A
--- failure of the hook is discarded; an error of the write is raised after the hook ran.
---@async
---@param info { method?: string, target?: string, version: string, keep_alive: boolean }
---@param response hecate.http.Response
---@param force_close boolean
---@param refused? boolean
---@return boolean keep_alive
local function send_response(self, conn, info, response, force_close, refused)
  local hook = self._on_response
  if hook == nil then return (write_response(self, conn, info, response, force_close)) end
  conn.bytes = 0
  local started = reactor.now()
  local ok, keep, failed = pcall(write_response, self, conn, info, response, force_close)
  if not ok and is_cancellation(keep) then error(keep, 0) end
  pcall(hook, {
    method = info.method, target = info.target, status = response.status, bytes = conn.bytes,
    duration = reactor.now() - started, failed = (not ok) or failed == true, refused = refused == true,
  })
  if not ok then error(keep, 0) end
  return keep
end

--- Answers with problem details and reports that the connection must close. A failed write is ignored: the client is gone.
---@async
local function send_problem(self, conn, info, status, detail)
  local ok, err = pcall(send_response, self, conn, info, problem.response(status, detail), true, true)
  if not ok and is_cancellation(err) then error(err, 0) end
end

M.normalise = normalise
M.send = send
M.flush = flush
M.send_response = send_response
M.send_problem = send_problem

return M
