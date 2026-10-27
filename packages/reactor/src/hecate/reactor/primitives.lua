-- The suspending primitives of concurrency.md, "Primitives": fork, join, select, sleep,
-- scope, deadline. Every function here may suspend and therefore raises
-- `NonYieldableContextError` outside a managed coroutine (ADR 0003).
global <const> type, error, math, table, pcall, tostring, require

local core = require("hecate.core")
local context = require("hecate.reactor.internal.context")
local Future = require("hecate.reactor.future")
local Scope = require("hecate.reactor.scope")
local Instant = require("hecate.reactor.instant")
local ChannelOperation = require("hecate.reactor.channel_operation")

-- Documented on `hecate.reactor` (module class completed here so that the LuaLS export lists the
-- functions; coding-standards.md, "Annotations for the reference").

---@class hecate.reactor
local M = {}

---@param name string
---@param value any
local function require_future(name, value)
  if not core.is_instance_of(value, Future) then
    error(core.ArgumentError(("%s: expects futures, got %s"):format(name, type(value))), 3)
  end
end

---@param value any
local function require_selectable(value)
  if not core.is_instance_of(value, Future) and not core.is_instance_of(value, ChannelOperation) then
    error(core.ArgumentError(("reactor.select: expects futures or channel operations, got %s"):format(type(value))), 3)
  end
end

--- Runs `fn(scope)` in a new scope owned by the running coroutine; returns what `fn`
--- returns after every computation forked inside has completed or been cancelled.
---@param fn fun(scope: hecate.reactor.Scope): ...
---@param deadline_at? number  clock reading at which the scope is cancelled
---@return any ...
local function scope_run(fn, deadline_at)
  local computation = context.current_computation("reactor.scope")
  local reactor = computation.reactor
  local scope = Scope(computation, computation.scope)
  if scope.parent then scope.parent:_add_subscope(scope) end
  computation.scope = scope
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
  computation.scope = scope.parent
  if scope.parent then scope.parent:_remove_subscope(scope) end

  if scope._failed then error(scope._failure, 0) end
  if body[1] then return table.unpack(body, 2, body.n) end
  -- The body ended with this scope's own cancellation: the scope absorbs it.
  if scope._deadline_hit then
    error(core.DeadlineExceededError({ message = "reactor.deadline: deadline exceeded", context = { at = deadline_at } }), 0)
  end
end
context.scope_run = scope_run

--- Opens a structured-concurrency scope, runs `fn(scope)` in it and returns what `fn` returns
--- once every computation forked inside has completed or been cancelled. See `hecate.reactor.Scope`.
---
--- Raises `hecate.core.ArgumentError` if `fn` is not a function, the first failure of a forked
--- computation or of `fn`, and `hecate.core.NonYieldableContextError` outside a managed coroutine.
---@async
---@param fn fun(scope: hecate.reactor.Scope): ...  the body of the scope
---@return any ...  the results of `fn`
function M.scope(fn)
  if type(fn) ~= "function" then
    error(core.ArgumentError(("reactor.scope: expects a function, got %s"):format(type(fn))), 2)
  end
  return scope_run(fn)
end

--- Starts `fn(...)` in a new coroutine of the current scope and returns its future.
---
--- Raises `hecate.core.ArgumentError` if `fn` is not a function and
--- `hecate.core.NonYieldableContextError` outside a managed coroutine.
---@param fn fun(...): ...  the computation to run
---@param ... any  the arguments passed to `fn`
---@return hecate.reactor.Future future  the future of the computation
function M.fork(fn, ...)
  if type(fn) ~= "function" then
    error(core.ArgumentError(("reactor.fork: expects a function, got %s"):format(type(fn))), 2)
  end
  local computation = context.current_computation("reactor.fork")
  return computation.reactor:_create_computation(computation.scope, fn, table.pack(...))
end

--- Starts `fn(...)` in the application scope (the root scope of the running reactor), so it
--- may outlive the scope of the caller. Its failure is observable only through its future
--- and does not cancel the application scope (concurrency.md, rule 2; OQ-26).
---
--- Raises `hecate.core.ArgumentError` if `fn` is not a function, `hecate.core.Error` if the
--- application scope is not running, and `hecate.core.NonYieldableContextError` outside a
--- managed coroutine.
---@param fn fun(...): ...  the computation to run
---@param ... any  the arguments passed to `fn`
---@return hecate.reactor.Future future  the future of the computation
function M.detach(fn, ...)
  if type(fn) ~= "function" then
    error(core.ArgumentError(("reactor.detach: expects a function, got %s"):format(type(fn))), 2)
  end
  local computation = context.current_computation("reactor.detach")
  local root = computation.reactor._root
  if root == nil or root._closed then
    error(core.Error("reactor.detach: the application scope is not running"), 2)
  end
  local future = computation.reactor:_create_computation(root, fn, table.pack(...))
  future._computation.detached = true
  return future
end

--- Runs `fn(...)` with `key` bound to `value` for the running computation and for the computations
--- it forks or detaches while the binding exists (ADR 0025). A binding is immutable; a nested
--- binding of the same key shadows the outer one until `fn` returns. The binding is removed when
--- `fn` returns or raises.
---
--- Raises `hecate.core.ArgumentError` if `key` is `nil` or `fn` is not a function,
--- `hecate.core.NonYieldableContextError` outside a managed coroutine, and the error of `fn`.
---@param key any  what identifies the binding; a module-private table avoids collisions
---@param value any  the value bound to `key`
---@param fn fun(...): ...  the function run with the binding
---@param ... any  the arguments passed to `fn`
---@return any ...  the results of `fn`
function M.with_ambient(key, value, fn, ...)
  if key == nil then
    error(core.ArgumentError("reactor.with_ambient: expects a key that is not nil"), 2)
  end
  if type(fn) ~= "function" then
    error(core.ArgumentError(("reactor.with_ambient: expects a function, got %s"):format(type(fn))), 2)
  end
  local computation = context.current_computation("reactor.with_ambient")
  local outer = computation.ambient
  computation.ambient = { key = key, value = value, parent = outer }
  local results = table.pack(pcall(fn, ...))
  computation.ambient = outer
  if not results[1] then error(results[2], 0) end
  return table.unpack(results, 2, results.n)
end

--- Returns the value bound to `key` in the running computation, or `nil` (ADR 0025).
---
--- Raises `hecate.core.ArgumentError` if `key` is `nil` and
--- `hecate.core.NonYieldableContextError` outside a managed coroutine.
---@param key any  the key given to `with_ambient`
---@return any? value  the bound value, or `nil`
function M.ambient(key)
  if key == nil then
    error(core.ArgumentError("reactor.ambient: expects a key that is not nil"), 2)
  end
  local node = context.current_computation("reactor.ambient").ambient
  while node do
    if node.key == key then return node.value end
    node = node.parent
  end
  return nil
end

--- Suspends the running coroutine for `seconds` of the reactor clock.
---
--- Raises `hecate.core.ArgumentError` if `seconds` is not a finite number greater than or equal
--- to 0, `hecate.core.NonYieldableContextError` outside a managed coroutine, and
--- `hecate.core.CancellationError` or `hecate.core.DeadlineExceededError` if the enclosing scope is
--- cancelled or its deadline expires while suspended.
---@async
---@param seconds number  finite and not negative; 0 yields to the other ready coroutines
function M.sleep(seconds)
  if type(seconds) ~= "number" or not (seconds >= 0) or seconds == math.huge then
    error(core.ArgumentError(("reactor.sleep: invalid duration %s: expected a finite number of seconds >= 0")
      :format(tostring(seconds))), 2)
  end
  local computation = context.current_computation("reactor.sleep")
  local reactor = computation.reactor
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
---
--- Raises `hecate.core.ArgumentError` if an argument is not a future, the error of the first
--- failed future, and `hecate.core.NonYieldableContextError` outside a managed coroutine.
---@async
---@param ... hecate.reactor.Future  the futures to wait for
---@return any ...  the first value of each future, in argument order
function M.join(...)
  context.current_computation("reactor.join")
  local futures = table.pack(...)
  for i = 1, futures.n do require_future("reactor.join", futures[i]) end
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

local HANDOFF = {} -- first value a channel hand-off resumes `select` with

--- Cancels the futures among the items of a `select`.
local function cancel_futures(items)
  for i = 1, items.n do
    if core.is_instance_of(items[i], Future) then items[i]:cancel() end
  end
end

--- Registers `wake` on every item of a `select`; returns the function withdrawing them.
local function watch_items(items, wake)
  local withdrawals = {}
  for i = 1, items.n do
    local item = items[i]
    if core.is_instance_of(item, Future) then
      if item._state == "pending" then
        local watcher = item:_watch(wake)
        withdrawals[#withdrawals + 1] = function() watcher.active = false end
      end
    else
      ---@diagnostic disable-next-line: invisible  -- friend class
      withdrawals[#withdrawals + 1] = item:_enqueue(function(status, value)
        return wake(HANDOFF, i, status, value)
      end)
    end
  end
  return function()
    for i = 1, #withdrawals do withdrawals[i]() end
  end
end

--- Waits for the first item to be ready, cancels the futures among the others and returns
--- its index and value. An item is a future (its first value; its error is raised if it
--- failed or was cancelled) or a channel operation (`Channel:receive_op()`: the received
--- value; `Channel:send_op(v)`: nil once the value is handed over; `ClosedChannelError` is
--- raised if the channel is closed). When several items are ready, the first in argument
--- order wins (OQ-25); a channel operation takes effect only if it is the one selected,
--- so no value is ever taken or sent by a losing operation.
---
--- Raises `hecate.core.ArgumentError` for no item or an item that is neither a future nor a
--- channel operation, `hecate.core.ClosedChannelError` for a closed channel, the error of a failed
--- future, and `hecate.core.NonYieldableContextError` outside a managed coroutine.
---@async
---@param ... hecate.reactor.Future|hecate.reactor.ChannelOperation  the items to wait for
---@return integer index  the position of the selected item
---@return any value  its value
function M.select(...)
  context.current_computation("reactor.select")
  local items = table.pack(...)
  if items.n == 0 then error(core.ArgumentError("reactor.select: expects at least one future"), 2) end
  for i = 1, items.n do require_selectable(items[i]) end
  while true do
    for i = 1, items.n do
      local item = items[i]
      if core.is_instance_of(item, Future) then
        if item._state ~= "pending" then
          cancel_futures(items)
          if item._state == "completed" then return i, item._results[1] end
          error(item._error, 0)
        end
      else
        ---@diagnostic disable-next-line: invisible  -- friend class
        local completed, value = item:_try()
        if completed then
          cancel_futures(items)
          return i, value
        end
      end
    end
    local tag, index, status, value = context.suspend(function(wake) return watch_items(items, wake) end)
    if tag == HANDOFF then
      cancel_futures(items)
      if status == false then error(core.ClosedChannelError({
        message = "reactor.select: the channel is closed", context = { channel = items[index].channel },
      }), 0) end
      return index, value
    end
  end
end

--- Runs `fn(...)`; cancels it and raises `DeadlineExceededError` if it does not finish
--- in time. `limit` is a relative duration in seconds, or a `hecate.reactor.Instant`.
---
--- Raises `hecate.core.DeadlineExceededError` when the limit expires, `hecate.core.ArgumentError`
--- if `limit` is neither seconds nor an instant or `fn` is not a function, and
--- `hecate.core.NonYieldableContextError` outside a managed coroutine.
---@async
---@param limit number|hecate.reactor.Instant  a duration in seconds, or an absolute instant
---@param fn fun(...): ...  the computation to bound
---@param ... any  the arguments passed to `fn`
---@return any ...  the results of `fn`
function M.deadline(limit, fn, ...)
  if type(fn) ~= "function" then
    error(core.ArgumentError(("reactor.deadline: expects a function, got %s"):format(type(fn))), 2)
  end
  local computation = context.current_computation("reactor.deadline")
  local at
  if type(limit) == "number" and limit == limit then
    at = computation.reactor:now() + limit
  elseif core.is_instance_of(limit, Instant) then
    at = limit.seconds
  else
    error(core.ArgumentError(("reactor.deadline: invalid deadline %s: expected seconds or an Instant")
      :format(tostring(limit))), 2)
  end
  local args = table.pack(...)
  return scope_run(function() return fn(table.unpack(args, 1, args.n)) end, at)
end

--- Returns the reading of the running reactor's clock, in seconds.
---
--- Raises `hecate.core.Error` if no reactor is running.
---@return number seconds  the clock reading
function M.now()
  if context.reactor == nil then error(core.Error("reactor.now: no reactor is running"), 2) end
  return context.reactor:now()
end

return M
