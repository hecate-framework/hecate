-- The response writer of `hecate.http.Server`: framing, the head and the content of one response (RFC 9110, RFC 9112
-- section 6), and the problem answers sent before an action runs.
-- Internal to `hecate.http`: not public API. Only `server.lua` and the other `internal/server_*` modules require it.
-- Every function takes the server (`self`) first: it reads the settings and reports through `_report`.
global <const> require, type, error, pcall, ipairs, math, string, tostring, os

local core = require("hecate.core")
local reactor = require("hecate.reactor")
local json = require("hecate.json")
local Response = require("hecate.http.response")
local problem = require("hecate.http.problem")
local wire = require("hecate.http.wire")
local Status = require("hecate.http.status")
local Fields = require("hecate.http.fields")

---@class hecate.http.internal.server_response
local M = {}

---@return boolean
local function is_cancellation(err) return core.is_instance_of(err, core.CancellationError) end

---@async
local function send(self, conn, data)
  if data == "" then return end
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


--- The response an action produced, or the problem details for what went wrong. An action must return a `Response`
--- with a final status (200 to 599) and content that is nil, a string, a table (serialised as JSON) or a function.
---@param ok boolean
---@param result any
---@return hecate.http.Response response
---@return any? failure  the error that was replaced by a problem response
local function response_of(ok, result)
  if not ok then return problem.from_error(result), result end
  if not core.is_instance_of(result, Response) then
    return problem.response(500), core.Error("http.Server: the action returned " .. type(result) .. " instead of a Response")
  end
  local content = result.content
  local kind = type(content)
  if not Status.is_valid(result.status) or not core.is_instance_of(result.fields, Fields) or type(result.reason) ~= "string" then
    return problem.response(500), core.Error("http.Server: the action returned a response with an invalid status, reason or fields")
  end
  if result.status < 200 or not (content == nil or kind == "string" or kind == "table" or kind == "function") then
    return problem.response(500), core.Error("http.Server: the action returned a response the server cannot send")
  end
  return result, nil
end

---@param action function
---@param request hecate.http.Request
---@return table outcome  `{ ok, result }`
local function call_action(action, request)
  local ok, result = pcall(action, request)
  if not ok and is_cancellation(result) then error(result, 0) end
  return { ok, result }
end

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
  if kind == "table" then return "length", json.encode(content) end
  if kind == "function" then
    if has_declared then return "declared", declared end
    return version == "HTTP/1.0" and "close_delimited" or "chunked"
  end
  return "length", ""
end

--- Sends `response` as the answer to the request described by `info` (`method`, `version`, `keep_alive`) and returns
--- whether the connection stays open. HEAD and the statuses 1xx, 204 and 304 never carry content (RFC 9110, sections
--- 9.3.2, 15.2, 15.3.5 and 15.4.5); a function without a declared length is sent chunked (RFC 9112, section 7.1), or
--- delimited by the close for HTTP/1.0. The framing fields of the action are replaced by the server's own.
---@async
---@param info { method?: string, version: string, keep_alive: boolean }
---@param response hecate.http.Response
---@param force_close boolean
---@return boolean keep_alive
local function send_response(self, conn, info, response, force_close)
  local status = response.status
  local fields = response.fields:copy()
  local wants_close = force_close or not info.keep_alive or self._stopping
    or wire.has_connection_option(fields:combined("Connection"), "close")
  local declared = fields:get("Content-Length")
  for _, name in ipairs(HOP_BY_HOP) do fields:remove(name) end

  local mode, text = frame(status, response.content, declared, info.version)
  local head_request = info.method == "HEAD"
  if type(response.content) == "table" and mode == "length" and not fields:has("Content-Type") then
    fields:set("Content-Type", "application/json")
  end
  if mode == "length" then
    fields:set("Content-Length", tostring(#(text --[[@as string]])))
  elseif mode == "declared" or mode == "declared_only" then
    fields:set("Content-Length", text --[[@as string]])
  elseif mode == "chunked" and not head_request then
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

  send(self, conn, wire.head(status, response.reason, fields))
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
    return false -- the head is sent: the client cannot be told, the connection is closed
  end
  if mode == "declared" and remaining() ~= 0 then
    self:_report("a content writer stopped before the declared Content-Length", "short content")
    pcall(flush, self, conn)
    return false
  end
  if mode == "chunked" then send(self, conn, wire.LAST_CHUNK) end
  flush(self, conn)
  return not wants_close
end

--- Answers with problem details and reports that the connection must close. A failed write is ignored: the client is gone.
---@async
local function send_problem(self, conn, info, status, detail)
  local ok, err = pcall(send_response, self, conn, info, problem.response(status, detail), true)
  if not ok and is_cancellation(err) then error(err, 0) end
end

M.response_of = response_of
M.call_action = call_action
M.send = send
M.flush = flush
M.send_response = send_response
M.send_problem = send_problem

return M
