-- Reactor: the scheduler over libuv (Schmidt, "Reactor", 1995). One reactor runs on one
-- thread; every unit of work is a coroutine ("task") resumed by the scheduler only, never
-- from inside a libuv callback (reactor/CLAUDE.md, known pitfalls). Completions and
-- timers merely mark tasks ready; `Reactor:run` resumes them in FIFO order.
--
-- Two clocks: "real" (libuv monotonic time, blocking in `uv.run`) and "virtual"
-- (deterministic, time jumps to the next timer when no task is ready;
-- concurrency.md, "Testing requirements").
global <const> type, error, table, coroutine, math, pairs, pcall, require, tostring

local core = require("hecate.core")
local uv = require("luv")
local context = require("hecate.reactor.internal.context")
local Future = require("hecate.reactor.future")

local YIELD = {} -- value yielded by managed coroutines to the scheduler
local CANCELLED = {} -- value a cancelled suspension is resumed with

---@class hecate.reactor.ReactorOptions
---@field clock? "real"|"virtual"  default "real"
---@field start? number  initial reading of a virtual clock, default 0

---@class hecate.reactor.Reactor
---@overload fun(options?: hecate.reactor.ReactorOptions): hecate.reactor.Reactor
local Reactor = core.class("Reactor")

--- Creates a reactor. It runs nothing until `run` is called.
---@param options? hecate.reactor.ReactorOptions
function Reactor:init(options)
  options = options or {}
  local clock = options.clock or "real"
  if clock ~= "real" and clock ~= "virtual" then
    error(core.ArgumentError(("invalid clock %s: expected \"real\" or \"virtual\""):format(tostring(clock))), 2)
  end
  self._virtual = clock == "virtual"
  self._virtual_now = options.start or 0
  self._origin = 0
  self._ready = {}
  self._head, self._tail = 1, 0
  self._heap = {}
  self._cancelled_timers = 0
  self._sequence = 0
  self._tasks = {}
  self._live = 0
  self._uv_timer = nil
end

--- Returns the reading of the reactor clock, in seconds.
---@return number
function Reactor:now()
  if self._virtual then return self._virtual_now end
  return uv.hrtime() / 1e9 - self._origin
end

--- Returns the number of coroutines that have not finished.
---@return integer
function Reactor:live_tasks() return self._live end

-- Timers: a binary heap ordered by (when, sequence); cancelled entries are dropped lazily.

local function before(a, b)
  return a.when < b.when or (a.when == b.when and a.sequence < b.sequence)
end

local function heap_push(heap, item)
  local i = #heap + 1
  heap[i] = item
  while i > 1 do
    local parent = i // 2
    if not before(heap[i], heap[parent]) then break end
    heap[i], heap[parent] = heap[parent], heap[i]
    i = parent
  end
end

local function heap_pop(heap)
  local top = heap[1]
  local last = heap[#heap]
  heap[#heap] = nil
  local size = #heap
  if size > 0 then
    heap[1] = last
    local i = 1
    while true do
      local left, right, smallest = i * 2, i * 2 + 1, i
      if left <= size and before(heap[left], heap[smallest]) then smallest = left end
      if right <= size and before(heap[right], heap[smallest]) then smallest = right end
      if smallest == i then break end
      heap[i], heap[smallest] = heap[smallest], heap[i]
      i = smallest
    end
  end
  return top
end

--- Schedules `fn` to run in the scheduler at clock reading `when`.
---@param when number
---@param fn fun()
---@return table timer  pass to `_cancel_timer`
---@private
function Reactor:_add_timer(when, fn)
  self._sequence = self._sequence + 1
  local timer = { when = when, sequence = self._sequence, fn = fn, cancelled = false }
  heap_push(self._heap, timer)
  return timer
end

---@private
function Reactor:_cancel_timer(timer)
  if timer.cancelled then return end
  timer.cancelled = true
  self._cancelled_timers = self._cancelled_timers + 1
  local heap = self._heap
  if self._cancelled_timers > 64 and self._cancelled_timers * 2 > #heap then
    local kept = {}
    for i = 1, #heap do
      if not heap[i].cancelled then kept[#kept + 1] = heap[i] end
    end
    self._heap, self._cancelled_timers = {}, 0
    for i = 1, #kept do heap_push(self._heap, kept[i]) end
  end
end

--- Returns the earliest live timer without removing it.
local function peek_timer(self)
  local heap = self._heap
  while heap[1] and heap[1].cancelled do
    heap_pop(heap)
    self._cancelled_timers = self._cancelled_timers - 1
  end
  return heap[1]
end

local function fire_due(self, now)
  while true do
    local timer = peek_timer(self)
    if not timer or timer.when > now then return end
    heap_pop(self._heap)
    timer.cancelled = true
    timer.fn()
  end
end

-- Tasks.

local function push_ready(self, task)
  self._tail = self._tail + 1
  self._ready[self._tail] = task
end

local function wake_task(task, id, ...)
  if task.state ~= "suspended" or id ~= task.wait_id then return false end
  task.state = "ready"
  task.resume = table.pack(...)
  push_ready(task.reactor, task)
  return true
end

--- Returns the cancellation pending for a task: its own, or that of any enclosing scope.
local function pending_cancel(task)
  if task.cancel_error ~= nil then return task.cancel_error end
  local scope = task.scope
  while scope do
    if scope._cancel_error ~= nil then return scope._cancel_error end
    scope = scope.parent
  end
  return nil
end

function context.notify_cancel(task)
  if task.state == "suspended" and task.cancellable and pending_cancel(task) ~= nil then
    wake_task(task, task.wait_id, CANCELLED)
  end
end

function context.cancel_task(task, err)
  if task.cancel_error == nil then task.cancel_error = err end
  context.notify_cancel(task)
end

--- Returns the task of the running coroutine, or raises `NonYieldableContextError`.
local function current_task(operation)
  local reactor = context.reactor
  local co = coroutine.running()
  local task = reactor and reactor._tasks[co]
  if not task then
    error(core.NonYieldableContextError({
      message = operation .. " may only be called from a coroutine managed by a running reactor",
      context = { operation = operation },
    }), 0)
  end
  if not coroutine.isyieldable() then
    error(core.NonYieldableContextError({
      message = operation .. " cannot suspend here: the coroutine is inside a non-yieldable context"
        .. " (for example a table.sort comparator, a string.gsub callback or a metamethod called from C)",
      context = { operation = operation },
    }), 0)
  end
  return task
end

--- Suspends the running task until the `wake` function handed to `register` is called.
--- `register` returns an optional `undo` function, always called after the task resumes.
--- A cancellable suspension raises the pending `CancellationError` instead of returning.
---@param register? fun(wake: fun(...): boolean): (fun()?)
---@param uncancellable? boolean
---@return any ...
function context.suspend(register, uncancellable)
  local task = current_task("a suspending operation")
  if not uncancellable then
    local pending = pending_cancel(task)
    if pending ~= nil then error(pending, 0) end
  end
  local id = task.wait_id + 1
  task.wait_id = id
  task.state = "suspended"
  task.cancellable = not uncancellable
  local undo
  if register then
    undo = register(function(...) return wake_task(task, id, ...) end)
  end
  local resumed = table.pack(coroutine.yield(YIELD))
  task.cancellable = false
  if undo then undo() end
  if resumed[1] == CANCELLED then
    error(pending_cancel(task) or core.CancellationError("cancelled"), 0)
  end
  return table.unpack(resumed, 1, resumed.n)
end

context.current_task = current_task

local function finish(self, task, state, results, err)
  self._tasks[task.co] = nil
  self._live = self._live - 1
  task.state = "dead"
  task.future:_settle(state, results, err)
  if task.home then task.home:_child_done(task, state, err) end
end

local function step(self, task)
  local resume = task.resume
  task.resume = nil
  task.state = "running"
  local outcome
  if resume then
    outcome = table.pack(coroutine.resume(task.co, table.unpack(resume, 1, resume.n)))
  else
    outcome = table.pack(coroutine.resume(task.co))
  end
  if not outcome[1] then
    -- An errored coroutine has not unwound: closing it runs the pending `<close>` handlers
    -- (reactor/CLAUDE.md invariant: cancellation runs `<close>` handlers). An error raised by
    -- a handler replaces the original one.
    local closed, err = coroutine.close(task.co)
    if closed then err = outcome[2] end
    local state = core.is_instance_of(err, core.CancellationError) and "cancelled" or "failed"
    finish(self, task, state, nil, err)
  elseif coroutine.status(task.co) == "dead" then
    finish(self, task, "completed", table.pack(table.unpack(outcome, 2, outcome.n)))
  elseif outcome[2] ~= YIELD then
    coroutine.close(task.co)
    finish(self, task, "failed", nil,
      core.Error("a managed coroutine called coroutine.yield directly; use the reactor primitives"))
  end
end

--- Creates a coroutine for `fn(...)` in `scope` and marks it ready.
---@param scope? hecate.reactor.Scope  nil for the main task
---@param fn function
---@param args table  packed arguments
---@return hecate.reactor.Future
---@private
function Reactor:_create_task(scope, fn, args)
  local future = Future()
  local task = {
    reactor = self, state = "ready", wait_id = 0, cancellable = false,
    scope = scope, home = scope, future = future,
  }
  task.co = coroutine.create(function() return fn(table.unpack(args, 1, args.n)) end)
  future._task = task
  self._tasks[task.co] = task
  self._live = self._live + 1
  if scope then scope:_adopt(task) end
  push_ready(self, task)
  return future
end

local function run_ready(self)
  local count = self._tail - self._head + 1
  for _ = 1, count do
    local index = self._head
    local task = self._ready[index]
    self._ready[index] = nil
    self._head = index + 1
    step(self, task)
  end
  if self._head > self._tail then self._head, self._tail = 1, 0 end
end

local function has_ready(self) return self._head <= self._tail end

local function deadlock(self)
  error(core.Error({
    message = ("deadlock: %d coroutine(s) are suspended and nothing can wake them"):format(self._live),
    context = { live = self._live },
  }), 0)
end

local function loop(self, main)
  local uv_timer = self._uv_timer
  while main._state == "pending" do
    run_ready(self)
    if main._state ~= "pending" then break end
    if self._virtual then
      if has_ready(self) then
        fire_due(self, self._virtual_now)
      else
        local timer = peek_timer(self)
        if not timer then deadlock(self) end
        if timer.when > self._virtual_now then self._virtual_now = timer.when end
        fire_due(self, self._virtual_now)
      end
    elseif has_ready(self) then
      uv.run("nowait")
      fire_due(self, self:now())
    else
      local timer = peek_timer(self)
      if timer then
        local delay = math.max(0, math.ceil((timer.when - self:now()) * 1000))
        uv_timer:start(delay, 0, function() end)
      end
      local alive = uv.run("once")
      if timer then uv_timer:stop() end
      fire_due(self, self:now())
      if not timer and not alive and not has_ready(self) and peek_timer(self) == nil then deadlock(self) end
    end
  end
end

--- Runs `fn(...)` as the main coroutine, inside a root scope, and drives the reactor until
--- it and everything it forked have finished. Returns the results of `fn`, or raises its error.
---@param fn fun(...): any ...
---@param ... any
---@return any ...
function Reactor:run(fn, ...)
  if type(fn) ~= "function" then
    error(core.ArgumentError(("run expects a function, got %s"):format(type(fn))), 2)
  end
  if context.reactor ~= nil then
    error(core.Error("a reactor is already running on this thread"), 2)
  end
  local args = table.pack(...)
  context.reactor = self
  if not self._virtual then
    self._origin = uv.hrtime() / 1e9
    self._uv_timer = uv.new_timer()
  end
  local main = self:_create_task(nil, function()
    return context.scope_run(function() return fn(table.unpack(args, 1, args.n)) end)
  end, { n = 0 })
  local ok, failure = pcall(loop, self, main)
  context.reactor = nil
  if self._uv_timer then
    self._uv_timer:close()
    self._uv_timer = nil
    uv.run("nowait") -- lets libuv finish closing the handle
  end
  if not ok then
    -- Abandon what is left: closing a suspended coroutine runs its `<close>` handlers.
    for co, task in pairs(self._tasks) do
      coroutine.close(co)
      task.state = "dead"
    end
    self._tasks, self._live = {}, 0
    error(failure, 0)
  end
  if main._state == "completed" then
    return table.unpack(main._results, 1, main._results.n)
  end
  error(main._error, 0)
end

--- Returns the number of open (not closing) libuv handles, for leak detection in tests.
---@return integer
function Reactor.open_handles()
  local count = 0
  uv.walk(function(handle)
    if not uv.is_closing(handle) then count = count + 1 end
  end)
  return count
end

return core.finalise(Reactor)
