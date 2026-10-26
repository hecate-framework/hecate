-- Reactor: the scheduler over libuv (Schmidt, "Reactor", 1995). One reactor runs on one
-- thread; every unit of work is a coroutine ("coroutine") resumed by the scheduler only, never
-- from inside a libuv callback (reactor/CLAUDE.md, known pitfalls). Completions and
-- timers merely mark coroutines ready; `Reactor:run` resumes them in FIFO order.
--
-- Two clocks: "real" (libuv monotonic time, blocking in `uv.run`) and "virtual"
-- (deterministic, time jumps to the next timer when no coroutine is ready;
-- concurrency.md, "Testing requirements").
global <const> type, error, table, coroutine, math, pairs, pcall, require, tostring

local core = require("hecate.core")
local uv = require("luv")
local context = require("hecate.reactor.internal.context")
local Future = require("hecate.reactor.future")

local YIELD = {} -- value yielded by managed coroutines to the scheduler
local CANCELLED = {} -- value a cancelled suspension is resumed with

--- Options of a reactor.
---@class hecate.reactor.ReactorOptions
---@field clock? "real"|"virtual"  default "real"
---@field start? number  initial reading of a virtual clock, default 0

--- The scheduler: runs a main computation and everything it forks over libuv, on a real or a virtual clock.
---@class hecate.reactor.Reactor
---@overload fun(options?: hecate.reactor.ReactorOptions): hecate.reactor.Reactor
local Reactor = core.class("Reactor")

--- Creates a reactor. It runs nothing until `run` is called.
---@param options? hecate.reactor.ReactorOptions
function Reactor:init(options)
  options = options or {}
  local clock = options.clock or "real"
  if clock ~= "real" and clock ~= "virtual" then
    error(core.ArgumentError(("reactor.Reactor: invalid clock %s: expected \"real\" or \"virtual\""):format(tostring(clock))), 2)
  end
  self._virtual = clock == "virtual"
  self._virtual_now = options.start or 0
  self._origin = 0
  self._ready = {}
  self._head, self._tail = 1, 0
  self._heap = {}
  self._cancelled_timers = 0
  self._sequence = 0
  self._computations = {}
  self._live = 0
  self._uv_timer = nil
  self._sigpipe_guard = nil
  self._root = nil
end

--- Returns the reading of the reactor clock, in seconds.
---@return number
function Reactor:now()
  if self._virtual then return self._virtual_now end
  return uv.hrtime() / 1e9 - self._origin
end

--- Returns the number of coroutines that have not finished.
---@return integer
function Reactor:live_coroutines() return self._live end

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

-- Computations.

local function push_ready(self, computation)
  self._tail = self._tail + 1
  self._ready[self._tail] = computation
end

local function wake_computation(computation, id, ...)
  if computation.state ~= "suspended" or id ~= computation.wait_id then return false end
  computation.state = "ready"
  computation.resume = table.pack(...)
  push_ready(computation.reactor, computation)
  return true
end

--- Returns the cancellation pending for a coroutine: its own, or that of any enclosing scope.
local function pending_cancel(computation)
  if computation.cancel_error ~= nil then return computation.cancel_error end
  local scope = computation.scope
  while scope do
    if scope._cancel_error ~= nil then return scope._cancel_error end
    scope = scope.parent
  end
  return nil
end

function context.notify_cancel(computation)
  if computation.state == "suspended" and computation.cancellable and pending_cancel(computation) ~= nil then
    wake_computation(computation, computation.wait_id, CANCELLED)
  end
end

function context.cancel_computation(computation, err)
  if computation.cancel_error == nil then computation.cancel_error = err end
  context.notify_cancel(computation)
end

--- Returns the coroutine of the running coroutine, or raises `NonYieldableContextError`.
local function current_computation(operation)
  local reactor = context.reactor
  local co = coroutine.running()
  local computation = reactor and reactor._computations[co]
  if not computation then
    error(core.NonYieldableContextError({
      message = operation .. ": may only be called from a coroutine managed by a running reactor",
      context = { operation = operation },
    }), 0)
  end
  if not coroutine.isyieldable() then
    error(core.NonYieldableContextError({
      message = operation .. ": cannot suspend here: the coroutine is inside a non-yieldable context"
        .. " (for example a table.sort comparator, a string.gsub callback or a metamethod called from C)",
      context = { operation = operation },
    }), 0)
  end
  return computation
end

--- Suspends the running coroutine until the `wake` function handed to `register` is called.
--- `register` returns an optional `undo` function, always called after the coroutine resumes.
--- A cancellable suspension raises the pending `CancellationError` instead of returning.
---@param register? fun(wake: fun(...): boolean): (fun()?)
---@param uncancellable? boolean
---@return any ...
function context.suspend(register, uncancellable)
  local computation = current_computation("suspending operation")
  if not uncancellable then
    local pending = pending_cancel(computation)
    if pending ~= nil then error(pending, 0) end
  end
  local id = computation.wait_id + 1
  computation.wait_id = id
  computation.state = "suspended"
  computation.cancellable = not uncancellable
  local undo
  if register then
    undo = register(function(...) return wake_computation(computation, id, ...) end)
  end
  local resumed = table.pack(coroutine.yield(YIELD))
  computation.cancellable = false
  if undo then undo() end
  if resumed[1] == CANCELLED then
    error(pending_cancel(computation) or core.CancellationError("cancelled"), 0)
  end
  return table.unpack(resumed, 1, resumed.n)
end

context.current_computation = current_computation

local function finish(self, computation, state, results, err)
  self._computations[computation.co] = nil
  self._live = self._live - 1
  computation.state = "dead"
  computation.future:_settle(state, results, err)
  if computation.home then computation.home:_child_done(computation, state, err) end
end

local function step(self, computation)
  local resume = computation.resume
  computation.resume = nil
  computation.state = "running"
  local outcome
  if resume then
    outcome = table.pack(coroutine.resume(computation.co, table.unpack(resume, 1, resume.n)))
  else
    outcome = table.pack(coroutine.resume(computation.co))
  end
  if not outcome[1] then
    -- An errored coroutine has not unwound: closing it runs the pending `<close>` handlers
    -- (reactor/CLAUDE.md invariant: cancellation runs `<close>` handlers). An error raised by
    -- a handler replaces the original one.
    local closed, err = coroutine.close(computation.co)
    if closed then err = outcome[2] end
    local state = core.is_instance_of(err, core.CancellationError) and "cancelled" or "failed"
    finish(self, computation, state, nil, err)
  elseif coroutine.status(computation.co) == "dead" then
    finish(self, computation, "completed", table.pack(table.unpack(outcome, 2, outcome.n)))
  elseif outcome[2] ~= YIELD then
    coroutine.close(computation.co)
    finish(self, computation, "failed", nil,
      core.Error("a managed coroutine called coroutine.yield directly; use the reactor primitives"))
  end
end

--- Creates a coroutine for `fn(...)` in `scope` and marks it ready.
---@param scope? hecate.reactor.Scope  nil for the main computation
---@param fn function
---@param args table  packed arguments
---@return hecate.reactor.Future
---@private
function Reactor:_create_computation(scope, fn, args)
  local future = Future()
  local computation = {
    reactor = self, state = "ready", wait_id = 0, cancellable = false,
    scope = scope, home = scope, future = future,
  }
  local creator = self._computations[coroutine.running()]
  if creator then computation.ambient = creator.ambient end -- ambient context (ADR 0025)
  computation.co = coroutine.create(function() return fn(table.unpack(args, 1, args.n)) end)
  future._computation = computation
  self._computations[computation.co] = computation
  self._live = self._live + 1
  ---@diagnostic disable-next-line: invisible  -- the scheduler is the friend of `Scope`
  if scope then scope:_adopt(computation) end
  push_ready(self, computation)
  return future
end

local function run_ready(self)
  local count = self._tail - self._head + 1
  for _ = 1, count do
    local index = self._head
    local computation = self._ready[index]
    self._ready[index] = nil
    self._head = index + 1
    step(self, computation)
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
---@param fn fun(...): ...
---@param ... any
---@return any ...
function Reactor:run(fn, ...)
  if type(fn) ~= "function" then
    error(core.ArgumentError(("reactor.Reactor.run: expects a function, got %s"):format(type(fn))), 2)
  end
  if context.reactor ~= nil then
    error(core.Error("reactor.Reactor.run: a reactor is already running on this thread"), 2)
  end
  local args = table.pack(...)
  context.reactor = self
  if not self._virtual then
    self._origin = uv.hrtime() / 1e9
    self._uv_timer = uv.new_timer()
    -- A write to a connection the peer has closed must fail with EPIPE, not kill the process:
    -- libuv leaves SIGPIPE at its default action, so a handler is installed for the run. The
    -- handle is unreferenced (it never keeps the loop alive). Windows has no SIGPIPE and luv
    -- raises "Invalid Signal name" there, so the call is protected.
    local guard = uv.new_signal()
    local started, armed = pcall(guard.start, guard, "sigpipe", function() end)
    if started and armed then
      guard:unref()
      self._sigpipe_guard = guard
    else
      guard:close()
    end
  end
  local main = self:_create_computation(nil, function()
    return context.scope_run(function(scope)
      self._root = scope
      return fn(table.unpack(args, 1, args.n))
    end)
  end, { n = 0 })
  local ok, failure = pcall(loop, self, main)
  context.reactor = nil
  self._root = nil
  if self._uv_timer then
    self._uv_timer:close()
    self._uv_timer = nil
    if self._sigpipe_guard then
      self._sigpipe_guard:close()
      self._sigpipe_guard = nil
    end
    uv.run("nowait") -- lets libuv finish closing the handles
  end
  if not ok then
    -- Abandon what is left: closing a suspended coroutine runs its `<close>` handlers.
    for co, computation in pairs(self._computations) do
      coroutine.close(co)
      computation.state = "dead"
    end
    self._computations, self._live = {}, 0
    error(failure, 0)
  end
  if main._state == "completed" then
    return table.unpack(main._results, 1, main._results.n)
  end
  error(main._error, 0)
end

--- Returns whether this reactor runs on the real clock (libuv I/O requires it).
---@return boolean
function Reactor:is_real() return not self._virtual end

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
