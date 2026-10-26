-- Bridges libuv request callbacks to suspending calls. The callback only wakes the coroutine;
-- the coroutine is resumed by the scheduler (reactor/CLAUDE.md, known pitfalls).
global <const> type, error, require, select, table

local core = require("hecate.core")
local context = require("hecate.reactor.internal.context")

local IoError = core.error_class("IoError", "hecate.reactor.IoError")

-- A failure of TCP or name resolution is a network failure (owner decision on OQ-32 (5)):
-- it derives from `core.NetworkError` so that `catch` on `NetworkError` sees it. `IoError`
-- stays for the file system and processes. `core` has no multiple inheritance, so the two
-- classes are siblings and a transport failure is not an `IoError`.
local TransportError = core.error_class("TransportError", "hecate.reactor.TransportError", core.NetworkError)

local M = { IoError = IoError, TransportError = TransportError }

--- Raises an `IoError` (or an instance of `class`) for a libuv error string such as
--- "ENOENT: no such file or directory". `context.errno` is the libuv name.
---
--- `qualified` is the call as the caller wrote it (`reactor.fs.read_file`, `net.TcpStream.read`;
--- coding-standards.md, "Errors"): it prefixes the message. `operation` stays the stable
--- `context.operation` and is repeated in the message when it says more than the call
--- (`reactor.connect_tcp: connect 127.0.0.1:80: ECONNREFUSED`).
---@param qualified string
---@param operation string
---@param message string
---@param class? any  defaults to `IoError`
function M.fail(qualified, operation, message, class)
  -- Request errors read "ENOENT: no such file or directory"; stream callbacks deliver the bare name.
  local name = message:match("^(%u[%u%d_]*):") or message:match("^(%u[%u%d_]*)$")
  local prefix = qualified .. ": "
  if qualified:sub(-#operation - 1) ~= "." .. operation then prefix = prefix .. operation .. ": " end
  error((class or IoError)({
    message = prefix .. message,
    context = { operation = operation, errno = name },
  }), 0)
end

--- Raises a `TransportError`, the network failure of TCP and name resolution.
---@param qualified string
---@param operation string
---@param message string
function M.fail_transport(qualified, operation, message)
  M.fail(qualified, operation, message, TransportError)
end

--- Requires a running real-clock reactor and returns its internal computation record.
---@param qualified string  the public call, as the caller wrote it
---@return table computation
function M.begin(qualified)
  local computation = context.current_computation(qualified)
  if not computation.reactor:is_real() then
    error(core.Error(qualified .. ": needs the real clock, libuv I/O cannot run on a virtual-clock reactor"), 0)
  end
  return computation
end

--- Starts a libuv request with `start(callback)` and suspends until the callback runs.
--- The callback receives `(err, ...)`; returns the values after `err`, or raises `IoError`.
---@async
---@param qualified string  the public call, for messages
---@param operation string  the `context.operation`
---@param start fun(callback: fun(err: string?, ...))
---@return any ...
function M.request(qualified, operation, start)
  M.begin(qualified)
  local err, results
  local function pack(...) return { n = select("#", ...), ... } end
  -- Uncancellable: a started request cannot be withdrawn, so the coroutine waits for its
  -- completion (file-system requests are short).
  context.suspend(function(wake)
    start(function(e, ...)
      err, results = e, pack(...)
      wake()
    end)
  end, true)
  if err then M.fail(qualified, operation, err) end
  return table.unpack(results --[[@as table]], 1, results.n)
end

return M
