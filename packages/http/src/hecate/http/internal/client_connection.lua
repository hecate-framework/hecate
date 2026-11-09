-- The connection of the client: its state, the whole-request deadline and the parser events of one connection.
-- Internal to `hecate.http`: not public API. Only `client.lua` and the other `internal/client_*` modules require it.
global <const> require, ipairs, math

local core = require("hecate.core")
local reactor = require("hecate.reactor")
local net = require("hecate.net")

local READ_SIZE <const> = 16384

---@class hecate.http.internal.client_connection
local M = {}

---@class hecate.http.client.Connection
---@field stream any
---@field parser hecate.http.Parser
---@field queue table
---@field position integer
---@field tail integer
---@field eof boolean
---@field failure any
---@field received integer  bytes read since the connection was opened
---@field last_used number
---@field reusable boolean

local function discard(conn)
  if conn.dead then return end
  conn.dead = true
  conn.parser:close()
  conn.stream:close()
end

--- The seconds left of the whole-request deadline, or math.huge.
local function remaining(state)
  if state.deadline_at == nil then return math.huge end
  return state.deadline_at - reactor.now()
end

--- `seconds` limited by the whole-request deadline (at least 0: an expired deadline fails at the first suspension).
local function bounded(state, seconds)
  return math.max(0, math.min(seconds, remaining(state)))
end

---@async
local function read_chunk(conn, seconds)
  local stream = conn.stream
  local chunk = reactor.deadline(seconds, stream.read, stream, READ_SIZE)
  if chunk ~= nil then conn.received = conn.received + #chunk end
  return chunk
end

--- The next parser event of the connection, or nil and a reason (a `ParseError`, or "eof"). Waits at most `seconds`.
---@async
local function next_event(conn, seconds)
  while true do
    local event = conn.queue[conn.position]
    if event ~= nil then
      conn.queue[conn.position] = nil
      conn.position = conn.position + 1
      return event
    end
    if conn.failure ~= nil then return nil, conn.failure end
    if conn.eof then return nil, "eof" end
    local chunk = read_chunk(conn, seconds)
    local events, err
    if chunk == nil then
      conn.eof = true
      events, err = conn.parser:finish()
    else
      events, err = conn.parser:feed(chunk)
    end
    for _, parsed in ipairs(events) do
      conn.tail = conn.tail + 1
      conn.queue[conn.tail] = parsed
    end
    if err ~= nil and chunk ~= nil then conn.failure = err end
  end
end

local function end_of_stream(message)
  return net.EndOfStreamError({ message = "http.Client: " .. message, context = { buffered = 0 } })
end

local function protocol_error(message, reason)
  return core.ProtocolError({ message = "http.Client: " .. message, context = { reason = reason } })
end

M.discard = discard
M.remaining = remaining
M.bounded = bounded
M.next_event = next_event
M.end_of_stream = end_of_stream
M.protocol_error = protocol_error

return M
