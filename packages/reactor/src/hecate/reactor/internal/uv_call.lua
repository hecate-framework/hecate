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
---@param operation string
---@param message string
---@param class? any  defaults to `IoError`
function M.fail(operation, message, class)
  -- Request errors read "ENOENT: no such file or directory"; stream callbacks deliver the bare name.
  local name = message:match("^(%u[%u%d_]*):") or message:match("^(%u[%u%d_]*)$")
  error((class or IoError)({
    message = operation .. ": " .. message,
    context = { operation = operation, errno = name },
  }), 0)
end

--- Raises a `TransportError`, the network failure of TCP and name resolution.
---@param operation string
---@param message string
function M.fail_transport(operation, message)
  M.fail(operation, message, TransportError)
end

--- Requires a running real-clock reactor and returns its internal task record.
---@param operation string
---@return table task
function M.begin(operation)
  local task = context.current_task(operation)
  if not task.reactor:is_real() then
    error(core.Error(operation .. " needs the real clock: libuv I/O cannot run on a virtual-clock reactor"), 0)
  end
  return task
end

--- Starts a libuv request with `start(callback)` and suspends until the callback runs.
--- The callback receives `(err, ...)`; returns the values after `err`, or raises `IoError`.
---@async
---@param operation string
---@param start fun(callback: fun(err: string?, ...))
---@return any ...
function M.request(operation, start)
  M.begin(operation)
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
  if err then M.fail(operation, err) end
  return table.unpack(results --[[@as table]], 1, results.n)
end

return M
