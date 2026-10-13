-- Bridges libuv request callbacks to suspending calls. The callback only wakes the task;
-- the task is resumed by the scheduler (reactor/CLAUDE.md, known pitfalls).
global <const> type, error, require, select, table

local core = require("hecate.core")
local context = require("hecate.reactor.internal.context")

local IoError = core.error_class("IoError", "hecate.reactor.IoError")

local M = { IoError = IoError }

--- Raises an `IoError` for a libuv error string such as "ENOENT: no such file or directory".
---@param operation string
---@param message string
function M.fail(operation, message)
  -- Request errors read "ENOENT: no such file or directory"; stream callbacks deliver the bare name.
  local name = message:match("^(%u[%u%d_]*):") or message:match("^(%u[%u%d_]*)$")
  error(IoError({
    message = operation .. ": " .. message,
    context = { operation = operation, errno = name },
  }), 0)
end

--- Requires a running real-clock reactor and returns its task.
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
  -- Uncancellable: a started request cannot be withdrawn, so the task waits for its
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
