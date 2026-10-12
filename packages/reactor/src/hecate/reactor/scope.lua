-- Scope: structured-concurrency region owning forked computations (concurrency.md,
-- "Structured concurrency"; Sustrik 2016; Smith 2018).
--   1. A scope does not complete before all of its children have completed.
--   2. A failing child cancels its siblings; the first failure is raised by the scope.
--   4. Cancellation is cooperative and level-triggered: every suspension point of a task
--      inside a cancelled scope raises the scope's CancellationError.
global <const> type, error, table, require

local core = require("hecate.core")
local context = require("hecate.reactor.internal.context")

---@class hecate.reactor.Scope
---@field parent? hecate.reactor.Scope  the scope that was innermost when this one opened
---@overload fun(owner: table, parent?: hecate.reactor.Scope): hecate.reactor.Scope
local Scope = core.class("Scope")

--- Initialises a scope owned by the task that opens it.
---@param owner table  internal task
---@param parent? hecate.reactor.Scope
function Scope:init(owner, parent)
  self.parent = parent
  self._owner = owner
  self._children = {}
  self._subscopes = {}
  self._slot = nil
  self._cancel_error = nil
  self._failure = nil
  self._failed = false
  self._deadline_hit = false
  self._closed = false
  self._waiter = nil
end

--- Starts `fn(...)` in a new coroutine that belongs to this scope.
---@param fn fun(...): ...
---@param ... any
---@return hecate.reactor.Future
function Scope:fork(fn, ...)
  if type(fn) ~= "function" then
    error(core.ArgumentError(("fork expects a function, got %s"):format(type(fn))), 2)
  end
  if self._closed then
    error(core.ArgumentError("cannot fork into a scope that has completed"), 2)
  end
  return context.reactor:_create_task(self, fn, table.pack(...))
end

--- Requests cancellation of every computation in the scope (and of the code that opened
--- it, at its next suspension point). The first cancellation wins; later ones are ignored.
---@param err? any  error delivered to the computations; defaults to a `CancellationError`
function Scope:cancel(err)
  if self._cancel_error ~= nil then return end
  self._cancel_error = err or core.CancellationError({
    message = "scope cancelled", context = { source = self },
  })
  self:_propagate()
end

--- Returns whether the scope has been cancelled.
---@return boolean
function Scope:is_cancelled() return self._cancel_error ~= nil end

--- Returns the number of computations still running in the scope.
---@return integer
function Scope:live() return #self._children end

---@private
function Scope:_propagate()
  local children = self._children
  for i = 1, #children do context.notify_cancel(children[i]) end
  context.notify_cancel(self._owner)
  local subscopes = self._subscopes
  for i = 1, #subscopes do subscopes[i]:_propagate() end
end

---@private
function Scope:_adopt(task)
  local children = self._children
  children[#children + 1] = task
  task.slot = #children
end

---@private
function Scope:_add_subscope(scope)
  local list = self._subscopes
  list[#list + 1] = scope
  scope._slot = #list
end

---@private
function Scope:_remove_subscope(scope)
  local list = self._subscopes
  local last = list[#list]
  list[scope._slot] = last
  last._slot = scope._slot
  list[#list] = nil
  scope._slot = nil
end

--- Records the end of a child; the first failure cancels the siblings.
---@param task table
---@param state "completed"|"failed"|"cancelled"
---@param err any
---@private
function Scope:_child_done(task, state, err)
  local children = self._children
  local last = children[#children]
  children[task.slot] = last
  last.slot = task.slot
  children[#children] = nil
  task.slot = nil
  if state == "failed" and not self._failed then
    self._failed, self._failure = true, err
    self:cancel(core.CancellationError({
      message = "a sibling computation failed", cause = err, context = { source = self },
    }))
  end
  if #children == 0 and self._waiter then self._waiter() end
end

return core.finalise(Scope)
