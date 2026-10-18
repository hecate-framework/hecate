-- Framed message channel between a parent process and its child, with handle passing
-- (ADR 0023, "Mechanism in `reactor`"). The channel is a libuv IPC pipe, the child's fourth
-- standard stream; a message is a length-prefixed string that may carry one TCP stream. Messages
-- are strings: serialising them is the caller's concern (`reactor` stays below `json`).
global <const> type, error, require, pcall, tostring, string, table

local core = require("hecate.core")
local uv = require("luv")
local uv_call = require("hecate.reactor.internal.uv_call")
local tcp = require("hecate.reactor.tcp")

--- File descriptor of the channel in a child (the fourth standard stream).
local CHANNEL_FD = 3
--- Environment variable that tells a child it was started with a channel.
local ENV_NAME = "HECATE_IPC_FD"
--- Largest message accepted, to bound what a peer can make this process buffer.
local MAX_MESSAGE = 16 * 1024 * 1024
local HEADER = ">I4B" -- length of the message, flag: 1 when a stream accompanies it
local HEADER_SIZE = 5

--- One end of the channel between a parent and a child process.
---@class hecate.reactor.Peer
---@overload fun(handle: table): hecate.reactor.Peer
local Peer = core.class("Peer")

---@param handle table  a libuv IPC pipe, owned by the peer from now on
---@private
function Peer:init(handle)
  self._handle = handle
  self._stream = tcp.TcpStream(handle)
  self._chunks = {} -- bytes received and not yet decoded
  self._size = 0
  self._receiving = false
end

--- Sends a message, and optionally a `TcpStream` that the other end receives together with it.
--- Returns once libuv has handed the message to the operating system. A stream that is passed is
--- closed in this process when the hand-over completes: from then on only the other end owns the
--- connection. A cancelled send closes the peer, because the amount sent is unknown.
---
--- Raises `hecate.core.ArgumentError` for a message that is not a string, larger than 16 MiB, or a
--- `handle` that is not an open `TcpStream`, and `hecate.reactor.TransportError` when the channel
--- is closed or broken.
---@async
---@param message string  the message
---@param handle? hecate.reactor.TcpStream  a connected stream to hand over
function Peer:send(message, handle)
  if type(message) ~= "string" then
    error(core.ArgumentError(("send expects a string message, got %s"):format(type(message))), 2)
  end
  if #message > MAX_MESSAGE then
    error(core.ArgumentError(("send: the message is %d bytes, the limit is %d"):format(#message, MAX_MESSAGE)), 2)
  end
  if handle ~= nil and not core.is_instance_of(handle, tcp.TcpStream) then
    error(core.ArgumentError("send: only a TcpStream can be handed over"), 2)
  end
  if handle ~= nil and handle:is_closed() then
    error(core.ArgumentError("send: the stream to hand over is closed"), 2)
  end
  local frame = string.pack(HEADER, #message, handle and 1 or 0) .. message
  if handle == nil then
    self._stream:write(frame)
    return
  end
  ---@diagnostic disable-next-line: invisible  -- same package
  local raw = handle._handle
  ---@diagnostic disable-next-line: invisible  -- same package
  self._stream:_await("send", function(callback) return self._handle:write2(frame, raw, callback) end)
  handle:close()
end

--- Reads until `count` bytes are buffered.
---@async
---@param count integer
---@return boolean ok  false when the channel ended first
---@private
function Peer:_fill(count)
  while self._size < count do
    local data = self._stream:read()
    if data == nil then return false end
    self._chunks[#self._chunks + 1] = data
    self._size = self._size + #data
  end
  return true
end

--- Removes and returns the first `count` buffered bytes.
---@param count integer
---@return string
---@private
function Peer:_take(count)
  local joined = table.concat(self._chunks)
  self._chunks = { joined:sub(count + 1) }
  self._size = #joined - count
  return joined:sub(1, count)
end

--- Receives the next message, and the stream that came with it, if any. Returns `nil` when the
--- other end closed the channel (the parent or the child exited). Cancelling a suspended receive
--- keeps the peer open and loses nothing. One coroutine receives at a time.
---
--- Raises `hecate.reactor.TransportError` when the channel breaks or the other end sends a
--- malformed or oversized frame.
---@async
---@return string? message  the message, or nil at the end of the channel
---@return hecate.reactor.TcpStream? handle  the stream handed over with it
function Peer:receive()
  if self._receiving then error(core.Error("receive: another coroutine is already receiving"), 2) end
  self._receiving = true
  local ok, message, handle = pcall(self._receive, self)
  self._receiving = false
  if not ok then error(message, 0) end
  return message, handle
end

---@async
---@return string? message
---@return hecate.reactor.TcpStream? handle
---@private
function Peer:_receive()
  if not self:_fill(HEADER_SIZE) then
    if self._size > 0 then uv_call.fail_transport("receive", "EPIPE: the channel ended inside a frame") end
    return nil
  end
  local length, flag = string.unpack(HEADER, table.concat(self._chunks):sub(1, HEADER_SIZE))
  if length > MAX_MESSAGE or flag > 1 then
    uv_call.fail_transport("receive", "EPROTO: malformed frame")
  end
  if not self:_fill(HEADER_SIZE + length) then
    uv_call.fail_transport("receive", "EPIPE: the channel ended inside a frame")
  end
  local frame = self:_take(HEADER_SIZE + length)
  local message = frame:sub(HEADER_SIZE + 1)
  if flag == 0 then return message end
  if self._handle:pending_count() == 0 or self._handle:pending_type() ~= "tcp" then
    uv_call.fail_transport("receive", "EPROTO: the frame announced a stream that did not arrive")
  end
  local raw = uv.new_tcp()
  local accepted, err = self._handle:accept(raw)
  if not accepted then
    raw:close()
    uv_call.fail_transport("receive", tostring(err))
  end
  return message, tcp.TcpStream(raw)
end

--- Closes the channel. Idempotent, never suspends.
function Peer:close() self._stream:close() end

--- Closing at the end of a `<close>` scope.
function Peer:__close() self:close() end

--- Returns whether the peer is closed.
---@return boolean
function Peer:is_closed() return self._stream:is_closed() end

core.finalise(Peer)

--- Environment entry that `reactor.spawn` adds for a child started with a channel.
---@return string name
---@return string value
local function child_marker() return ENV_NAME, tostring(CHANNEL_FD) end

local parent_peer

---@class hecate.reactor.ipc
local ipc = { Peer = Peer, child_marker = child_marker }

--- The channel to the parent process, or `nil` when this process was not started by
--- `reactor.spawn` with `ipc = true`. The same peer is returned on every call. Does not suspend.
---@return hecate.reactor.Peer? peer  the parent's peer
function ipc.parent()
  if parent_peer and not parent_peer:is_closed() then return parent_peer end
  local fd = uv.os_getenv(ENV_NAME)
  if fd ~= tostring(CHANNEL_FD) or uv.guess_handle(CHANNEL_FD) ~= "pipe" then return nil end
  local handle = uv.new_pipe(true)
  local opened, err = handle:open(CHANNEL_FD)
  if not opened then
    handle:close()
    uv_call.fail_transport("ipc.parent", tostring(err))
  end
  parent_peer = Peer(handle)
  return parent_peer
end

return ipc
