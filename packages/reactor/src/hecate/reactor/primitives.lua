-- The suspending primitives of concurrency.md, "Primitives": fork, join, select, sleep,
-- scope, deadline. Every function here may suspend and therefore raises
-- `NonYieldableContextError` outside a managed coroutine (ADR 0003).
global <const> type, error, math, table, pcall, tostring, require

local core = require("hecate.core")
local context = require("hecate.reactor.internal.context")
local Future = require("hecate.reactor.future")
local Scope = require("hecate.reactor.scope")
local Instant = require("hecate.reactor.instant")

local M = {}

---@param name string
---@param value any
local function require_future(name, value)
  if not core.is_instance_of(value, Future) then
    error(core.ArgumentError(("%s expects futures, got %s"):format(name, type(value))), 3)
  end
end

--- Runs `fn(scope)` in a new scope owned by the running coroutine; returns what `fn`
--- returns after every computation forked inside has completed or been cancelled.
---@param fn fun(scope: hecate.reactor.Scope): ...
---@param deadline_at? number  clock reading at which the scope is cancelled
---@return any ...
local function scope_run(fn, deadline_at)
  local task = context.current_task("scope")
  local reactor = task.reactor
  local scope = Scope(task, task.scope)
  if scope.parent then scope.parent:_add_subscope(scope) end
  task.scope = scope
  local timer
  if deadline_at ~= nil then
    timer = reactor:_add_timer(deadline_at, function()
      scope._deadline_hit = true
      scope:cancel()
    end)
  end

  local body = table.pack(pcall(fn, scope))
  local own_cancellation = false
  if not body[1] then
    local err = body[2]
    own_cancellation = core.is_instance_of(err, core.CancellationError) and err.context.source == scope
    -- Rule 2: a failing body cancels its children; its error is the scope's first failure
    -- unless a child already failed (or the body merely observed this scope's own cancellation).
    if not own_cancellation and not scope._failed then
      scope._failed, scope._failure = true, err
    end
    scope:cancel(core.CancellationError({
      message = "the scope body failed", cause = err, context = { source = scope },
    }))
  end
  -- Rule 1: never complete before the children, whatever happens (uncancellable wait).
  while #scope._children > 0 do
    context.suspend(function(wake)
      scope._waiter = wake
      return function() scope._waiter = nil end
    end, true)
  end
  scope._closed = true
  if timer then reactor:_cancel_timer(timer) end
  task.scope = scope.parent
  if scope.parent then scope.parent:_remove_subscope(scope) end

  if scope._failed then error(scope._failure, 0) end
  if body[1] then return table.unpack(body, 2, body.n) end
  -- The body ended with this scope's own cancellation: the scope absorbs it.
  if scope._deadline_hit then
    error(core.DeadlineExceededError({ message = "deadline exceeded", context = { at = deadline_at } }), 0)
  end
end
context.scope_run = scope_run

--- Opens a structured-concurrency scope. See `hecate.reactor.Scope`.
---@async
---@param fn fun(scope: hecate.reactor.Scope): ...
---@return any ...
function M.scope(fn)
  if type(fn) ~= "function" then
    error(core.ArgumentError(("scope expects a function, got %s"):format(type(fn))), 2)
  end
  return scope_run(fn)
end

--- Starts `fn(...)` in a new coroutine of the current scope and returns its future.
---@async
---@param fn fun(...): ...
---@param ... any
---@return hecate.reactor.Future
function M.fork(fn, ...)
  if type(fn) ~= "function" then
    error(core.ArgumentError(("fork expects a function, got %s"):format(type(fn))), 2)
  end
  local task = context.current_task("fork")
  return task.reactor:_create_task(task.scope, fn, table.pack(...))
end

--- Suspends the running coroutine for `seconds` of the reactor clock.
---@async
---@param seconds number  finite and not negative; 0 yields to the other ready coroutines
function M.sleep(seconds)
  if type(seconds) ~= "number" or not (seconds >= 0) or seconds == math.huge then
    error(core.ArgumentError(("invalid duration %s: expected a finite number of seconds >= 0")
      :format(tostring(seconds))), 2)
  end
  local task = context.current_task("sleep")
  local reactor = task.reactor
  context.suspend(function(wake)
    local timer = reactor:_add_timer(reactor:now() + seconds, wake)
    return function() reactor:_cancel_timer(timer) end
  end)
end

--- Registers `wake` on every pending future; returns the function withdrawing them.
local function watch_all(futures, wake)
  local watchers = {}
  for i = 1, futures.n do
    if futures[i]._state == "pending" then watchers[#watchers + 1] = futures[i]:_watch(wake) end
  end
  return function()
    for i = 1, #watchers do watchers[i].active = false end
  end
end

local function cancel_pending(futures)
  for i = 1, futures.n do futures[i]:cancel() end
end

--- Waits for every future; if one fails, cancels the others and raises the first error.
---@async
---@param ... hecate.reactor.Future
---@return any ... the first value of each future, in argument order
function M.join(...)
  context.current_task("join")
  local futures = table.pack(...)
  for i = 1, futures.n do require_future("join", futures[i]) end
  while true do
    local pending = false
    for i = 1, futures.n do
      local state = futures[i]._state
      if state == "failed" or state == "cancelled" then
        cancel_pending(futures)
        error(futures[i]._error, 0)
      elseif state == "pending" then
        pending = true
      end
    end
    if not pending then break end
    context.suspend(function(wake) return watch_all(futures, wake) end)
  end
  local values = {}
  for i = 1, futures.n do values[i] = futures[i]._results[1] end
  return table.unpack(values, 1, futures.n)
end

--- Waits for the first future to complete, cancels the others and returns its index and
--- first value; raises its error if it failed or was cancelled.
---@async
---@param ... hecate.reactor.Future
---@return integer index
---@return any value
function M.select(...)
  context.current_task("select")
  local futures = table.pack(...)
  if futures.n == 0 then error(core.ArgumentError("select expects at least one future"), 2) end
  for i = 1, futures.n do require_future("select", futures[i]) end
  while true do
    for i = 1, futures.n do
      local future = futures[i]
      if future._state ~= "pending" then
        cancel_pending(futures)
        if future._state == "completed" then return i, future._results[1] end
        error(future._error, 0)
      end
    end
    context.suspend(function(wake) return watch_all(futures, wake) end)
  end
end

--- Runs `fn(...)`; cancels it and raises `DeadlineExceededError` if it does not finish
--- in time. `limit` is a relative duration in seconds, or a `hecate.reactor.Instant`.
---@async
---@param limit number|hecate.reactor.Instant
---@param fn fun(...): ...
---@param ... any
---@return any ...
function M.deadline(limit, fn, ...)
  if type(fn) ~= "function" then
    error(core.ArgumentError(("deadline expects a function, got %s"):format(type(fn))), 2)
  end
  local task = context.current_task("deadline")
  local at
  if type(limit) == "number" and limit == limit then
    at = task.reactor:now() + limit
  elseif core.is_instance_of(limit, Instant) then
    at = limit.seconds
  else
    error(core.ArgumentError(("invalid deadline %s: expected seconds or an Instant")
      :format(tostring(limit))), 2)
  end
  local args = table.pack(...)
  return scope_run(function() return fn(table.unpack(args, 1, args.n)) end, at)
end

--- Returns the reading of the running reactor's clock, in seconds.
---@return number
function M.now()
  if context.reactor == nil then error(core.Error("no reactor is running"), 2) end
  return context.reactor:now()
end

return M
