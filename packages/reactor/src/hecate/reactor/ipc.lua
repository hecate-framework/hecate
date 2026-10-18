-- Framed message pipe between a parent process and its child, with handle passing
-- (ADR 0023, "Mechanism in `reactor`"). The message pipe is a libuv IPC pipe, the child's fourth
-- standard stream; a message is a length-prefixed string that may carry one TCP stream. Messages
-- are strings: serialising them is the caller's concern (`reactor` stays below `json`).
global <const> type, error, require, pcall, tostring, string, table, math, pairs, package

local core = require("hecate.core")
local uv = require("luv")
local uv_call = require("hecate.reactor.internal.uv_call")
local tcp = require("hecate.reactor.tcp")

--- File descriptor of the message pipe in a child (the fourth standard stream).
local PIPE_FD = 3
--- Environment variable that tells a child it was started with a message pipe.
local ENV_NAME = "HECATE_IPC_FD"
--- Largest message accepted by default, to bound what a peer can make this process buffer.
local DEFAULT_MAX_MESSAGE = 16 * 1024 * 1024
--- The length field holds 32 bits.
local MAX_FIELD = 0xFFFFFFFF
local HEADER = ">I4B" -- length of the message, flag: 1 when a stream accompanies it
local HEADER_SIZE = 5

--- Options of a `Peer`.
---@class hecate.reactor.PeerOptions
---@field max_message? integer  largest message in bytes, sent or received; default 16 MiB

---@param name string
---@param options any
---@return table
local function check_options(name, options)
  if options == nil then return {} end
  if type(options) ~= "table" then
    error(core.ArgumentError(("%s expects an options table, got %s"):format(name, type(options))), 3)
  end
  for key in pairs(options) do
    if key ~= "max_message" then error(core.ArgumentError(("%s: unknown option %s"):format(name, tostring(key))), 3) end
  end
  local limit = options.max_message
  if limit ~= nil and (math.type(limit) ~= "integer" or limit < 0 or limit > MAX_FIELD) then
    error(core.ArgumentError(("%s: option max_message must be an integer in 0..%d"):format(name, MAX_FIELD)), 3)
  end
  return options
end

--- One end of the message pipe between a parent and a child process.
---@class hecate.reactor.Peer
---@overload fun(handle: table, options?: hecate.reactor.PeerOptions): hecate.reactor.Peer
local Peer = core.class("Peer")

--- Wraps an IPC pipe handle. `reactor.spawn` and `ipc.parent` build peers; constructing one
--- directly is for tests and for code that opened the pipe itself.
---@param handle table  a libuv IPC pipe, owned by the peer from now on
---@param options? hecate.reactor.PeerOptions
---@param stream? table  replaces the stream over `handle` (tests of the framing)
---@private
function Peer:init(handle, options, stream)
  options = check_options("Peer", options)
  self._handle = handle
  self._stream = stream or tcp.TcpStream(handle, { read_ahead = false })
  self._max_message = options.max_message or DEFAULT_MAX_MESSAGE
  -- Bytes received and not yet decoded: `_buf` from `_pos` on, then the chunks of `_extra`, which
  -- are joined into `_buf` only once a whole frame is available (one copy per frame, not per read).
  -- Indicative gain (Linux, in-process pair, 100 000 frames of 20 bytes found already buffered):
  -- 0.82-0.90 s before, 0.09-0.10 s after; the old code copied the whole buffer for every message.
  self._buf = ""
  self._pos = 1
  self._extra = {}
  self._extra_size = 0
  self._receiving = false
end

--- Sends a message, and optionally a `TcpStream` that the other end receives together with it.
--- Returns once libuv has handed the message to the operating system. A stream that is passed is
--- closed in this process when the hand-over completes: from then on only the other end owns the
--- connection. A cancelled send closes the peer, because the amount sent is unknown.
---
--- Windows: the operating system duplicates the socket for the other process, and the duplicate
--- is only valid while the sender's socket is open. This process closes it as soon as the write
--- completed, which may be before the other end called `receive`; a sender that must be sure the
--- stream arrived waits for an acknowledgement message from the receiver before it exits.
---
--- Raises `hecate.core.ArgumentError` for a message that is not a string, larger than the
--- `max_message` of the peer (16 MiB by default), or a `handle` that is not an open `TcpStream`,
--- and `hecate.reactor.TransportError` when the message pipe is closed (`EBADF`) or broken
--- (`EPIPE`).
---@async
---@param message string  the message
---@param handle? hecate.reactor.TcpStream  a connected stream to hand over
function Peer:send(message, handle)
  if type(message) ~= "string" then
    error(core.ArgumentError(("send expects a string message, got %s"):format(type(message))), 2)
  end
  if #message > self._max_message then
    error(core.ArgumentError(("send: the message is %d bytes, the limit is %d"):format(#message, self._max_message)), 2)
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

--- Number of bytes received and not yet decoded.
---@return integer
---@private
function Peer:_available() return #self._buf - self._pos + 1 + self._extra_size end

--- Reads until `count` bytes are buffered, and leaves them contiguous in `_buf` from `_pos`.
---@async
---@param count integer
---@return boolean ok  false when the message pipe ended first
---@private
function Peer:_fill(count)
  while self:_available() < count do
    local data = self._stream:read()
    if data == nil then return false end
    local extra = self._extra
    extra[#extra + 1] = data
    self._extra_size = self._extra_size + #data
  end
  local extra = self._extra
  if #extra > 0 then
    local parts = { self._pos == 1 and self._buf or self._buf:sub(self._pos) }
    table.move(extra, 1, #extra, 2, parts)
    self._buf = table.concat(parts)
    self._pos = 1
    self._extra, self._extra_size = {}, 0
  end
  return true
end

--- Counts the frames after the decoded one that announce a stream, as far as their header is
--- buffered: the operating system may deliver the handle of the next frame together with the end
--- of this one, so a handle waiting in libuv is only an orphan beyond that count. A header that
--- is cut short counts as announcing one stream (it is unknown yet).
---@return integer
---@private
function Peer:_announced_ahead()
  local buffer, position, size, count = self._buf, self._pos, #self._buf, 0
  while position <= size do
    if size - position + 1 < HEADER_SIZE then return count + 1 end
    local length, flag = string.unpack(HEADER, buffer, position)
    if flag > 1 or length > self._max_message then return count end
    if flag == 1 then count = count + 1 end
    position = position + HEADER_SIZE + length
  end
  return count
end

--- Fails the receive with `EPROTO` and closes the peer: after a protocol violation the byte
--- stream cannot be trusted any more, and the handles waiting in libuv are released with it.
---@param reason string
---@private
function Peer:_violation(reason)
  self:close()
  uv_call.fail_transport("receive", "EPROTO: " .. reason)
end

--- Receives the next message, and the stream that came with it, if any. Returns `nil` when the
--- other end closed the message pipe (the parent or the child exited). Cancelling a suspended
--- receive keeps the peer open and loses nothing, also after a partial frame. One coroutine
--- receives at a time.
---
--- Raises `hecate.reactor.TransportError` when the message pipe breaks (`EPIPE` inside a frame),
--- is closed (`EBADF`, or `ECANCELED` when closed while waiting), or the other end violates the
--- protocol (`EPROTO`: malformed or oversized frame, a stream that was announced and did not
--- arrive, or one that arrived without announcement; the peer is closed).
---@async
---@return string? message  the message, or nil at the end of the message pipe
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
    if self:_available() > 0 then
      uv_call.fail_transport("receive", "EPIPE: the message pipe ended inside a frame")
    end
    return nil
  end
  local length, flag = string.unpack(HEADER, self._buf, self._pos)
  if length > self._max_message or flag > 1 then self:_violation("malformed frame") end
  if not self:_fill(HEADER_SIZE + length) then
    uv_call.fail_transport("receive", "EPIPE: the message pipe ended inside a frame")
  end
  local first = self._pos + HEADER_SIZE
  local message = self._buf:sub(first, first + length - 1)
  self._pos = first + length
  if self._pos > #self._buf then self._buf, self._pos = "", 1 end
  local pending = self._handle:pending_count()
  if flag == 0 then
    if pending > 0 and pending > self:_announced_ahead() then
      self:_violation("a stream arrived with a frame that announced none")
    end
    return message
  end
  if pending == 0 or self._handle:pending_type() ~= "tcp" then
    self:_violation("the frame announced a stream that did not arrive")
  end
  if pending > 1 + self:_announced_ahead() then
    self:_violation("more than one stream arrived with a frame")
  end
  local raw = uv.new_tcp()
  local accepted, err = self._handle:accept(raw)
  if not accepted then
    raw:close()
    uv_call.fail_transport("receive", tostring(err))
  end
  return message, tcp.TcpStream(raw)
end

--- Closes the message pipe. Idempotent, never suspends.
function Peer:close() self._stream:close() end

--- Closing at the end of a `<close>` scope.
function Peer:__close() self:close() end

--- Returns whether the peer is closed.
---@return boolean
function Peer:is_closed() return self._stream:is_closed() end

core.finalise(Peer)

local parent_peer

--- Environment entry that `reactor.spawn` adds for a child started with a message pipe.
---@return string name
---@return string value
local function child_marker() return ENV_NAME, tostring(PIPE_FD) end

--- Whether this process holds the descriptor of a message pipe to its parent (it was started with
--- `ipc = true` and the pipe is not closed). A child it starts would inherit that descriptor.
---@return boolean
local function holds_descriptor()
  if package.config:sub(1, 1) == "\\" then return false end -- Windows passes only the descriptors listed
  return uv.os_getenv(ENV_NAME) ~= nil or (parent_peer ~= nil and not parent_peer:is_closed())
end

---@class hecate.reactor.ipc
---@field Peer hecate.reactor.Peer
---@field child_marker fun(): string, string  internal: name and value of the environment entry of a child with a message pipe
---@field holds_descriptor fun(): boolean  internal: whether this process holds a message pipe descriptor
local ipc = { Peer = Peer, child_marker = child_marker, holds_descriptor = holds_descriptor }

--- The message pipe to the parent process, or `nil` when this process was not started by
--- `reactor.spawn` with `ipc = true`. The same peer is returned on every call; `options` apply
--- when the peer is created. The marker in the environment is removed once the pipe is open, so
--- that processes started from here do not believe they own it. Does not suspend.
---
--- Raises `hecate.core.ArgumentError` for a malformed option.
---@param options? hecate.reactor.PeerOptions  `max_message`
---@return hecate.reactor.Peer? peer  the parent's peer
function ipc.parent(options)
  options = check_options("ipc.parent", options)
  if parent_peer and not parent_peer:is_closed() then return parent_peer end
  local fd = uv.os_getenv(ENV_NAME)
  if fd ~= tostring(PIPE_FD) or uv.guess_handle(PIPE_FD) ~= "pipe" then return nil end
  local handle = uv.new_pipe(true)
  local opened, err = handle:open(PIPE_FD)
  if not opened then
    handle:close()
    uv_call.fail_transport("ipc.parent", tostring(err))
  end
  parent_peer = Peer(handle, options)
  uv.os_unsetenv(ENV_NAME)
  return parent_peer
end

return ipc
