-- Signals over libuv signal handles (concurrency.md, "Signals and shutdown"). `wait_signal` owns a
-- handle only while a coroutine waits; `SignalWatcher` owns its handles until closed, so a signal
-- delivered between two waits is queued instead of taking the default action (OQ-116).
global <const> type, error, require, pcall, tostring, table, ipairs

local core = require("hecate.core")
local uv = require("luv")
local uv_call = require("hecate.reactor.internal.uv_call")
local context = require("hecate.reactor.internal.context")

-- Documented on `hecate.reactor` (module class completed here so that the LuaLS export lists the
-- function; coding-standards.md, "Annotations for the reference").

---@class hecate.reactor
local M = {}

local QUEUE_LIMIT = 16

--- Owns libuv signal handles from creation until `close`, so that no signal reaches the process
--- default action between two waits. A signal delivered while nobody waits is queued (at most 16;
--- a name already queued is not queued again, as POSIX signals do not count; one more is dropped).
--- Cancelling a waiter keeps the watcher and its queue. While nobody waits the handles do not keep
--- the event loop alive; while a coroutine waits they do. The watcher is `<close>`-able.
---@class hecate.reactor.SignalWatcher
---@overload fun(...: string): hecate.reactor.SignalWatcher
local SignalWatcher = core.class("SignalWatcher")

--- Starts watching the named signals (libuv names such as "sigint"); use `reactor.watch_signals`.
---
--- Raises `hecate.core.ArgumentError` for no name or a name that is not a string, and
--- `hecate.reactor.IoError` for a name the platform refuses (nothing is left open then).
---@param ... string  the names of the signals to watch
---@private
function SignalWatcher:init(...)
  local names = { ... }
  if #names == 0 then error(core.ArgumentError("reactor.watch_signals: expects at least one signal name"), 3) end
  for i = 1, #names do
    if type(names[i]) ~= "string" then
      error(core.ArgumentError("reactor.watch_signals: signal names must be strings"), 3)
    end
  end
  uv_call.begin("reactor.watch_signals")
  self._handles = {}
  self._queue = {}
  self._closed = false
  self._wake = nil -- the wake-up of the coroutine now waiting, if any
  for i = 1, #names do
    local handle = uv.new_signal()
    self._handles[#self._handles + 1] = handle
    local called, started, err = pcall(handle.start, handle, names[i], function(received) self:_deliver(received) end)
    if not called then started, err = nil, started end
    if not started then
      self:_release()
      uv_call.fail("reactor.watch_signals", "watch_signals", tostring(err))
    end
    handle:unref()
  end
end

---@param name string
---@private
function SignalWatcher:_deliver(name)
  local wake = self._wake
  if wake then
    self._wake = nil
    if wake(name) then return end
  end
  local queue = self._queue
  if #queue >= QUEUE_LIMIT then return end
  for i = 1, #queue do if queue[i] == name then return end end
  queue[#queue + 1] = name
end

---@param referenced boolean
---@private
function SignalWatcher:_reference(referenced)
  for _, handle in ipairs(self._handles) do
    if not handle:is_closing() then
      if referenced then handle:ref() else handle:unref() end
    end
  end
end

---@private
function SignalWatcher:_release()
  for _, handle in ipairs(self._handles) do
    if not handle:is_closing() then handle:close() end
  end
end

--- Returns the next signal delivered, suspending until one arrives when none is queued. One
--- coroutine at a time may wait.
---
--- Raises `hecate.core.CancellationError` when the enclosing scope is cancelled while waiting
--- (the watcher and its queue are kept), and `hecate.core.Error` when the watcher is closed.
---@async
---@return string name  the name of the signal
function SignalWatcher:wait()
  context.current_computation("reactor.SignalWatcher.wait")
  if self._closed then error(core.Error("reactor.SignalWatcher.wait: the watcher is closed"), 2) end
  if #self._queue > 0 then return table.remove(self._queue, 1) end
  if self._wake then error(core.Error("reactor.SignalWatcher.wait: another coroutine is already waiting"), 2) end
  local ok, name = pcall(context.suspend, function(wake)
    self._wake = wake
    self:_reference(true)
    return function()
      if self._wake == wake then self._wake = nil end
      if not self._closed then self:_reference(false) end
    end
  end)
  if not ok then error(name, 0) end
  if name == nil then error(core.Error("reactor.SignalWatcher.wait: the watcher was closed while waiting"), 2) end
  return name
end

--- Returns the number of signals queued and not yet returned by `wait`.
---@return integer
function SignalWatcher:pending() return #self._queue end

--- Stops watching and closes the libuv handles; a coroutine waiting is woken with an error.
--- Idempotent.
function SignalWatcher:close()
  if self._closed then return end
  self._closed = true
  self:_release()
  local wake = self._wake
  self._wake = nil
  if wake then wake(nil) end
end

---@private
function SignalWatcher:__close() self:close() end

--- Returns whether `close` was called.
---@return boolean
function SignalWatcher:is_closed() return self._closed end

M.SignalWatcher = core.finalise(SignalWatcher)

--- Starts a persistent watcher on the named signals (see `hecate.reactor.SignalWatcher`).
--- Raises `hecate.core.ArgumentError` for no name or a name that is not a string, and
--- `hecate.reactor.IoError` for a name the platform refuses.
---@param ... string  the names of the signals to watch
---@return hecate.reactor.SignalWatcher watcher  close it (or declare it `<close>`)
function M.watch_signals(...)
  return M.SignalWatcher(...)
end

--- Suspends until one of the named signals is delivered; returns its name. Names are libuv
--- names such as "sigint", "sigterm" and "sighup"; Windows delivers only the console ones.
---
--- Raises `hecate.core.ArgumentError` for no name or a name that is not a string, and
--- `hecate.core.CancellationError` if the enclosing scope is cancelled while waiting.
---@async
---@param ... string  the names of the signals to wait for
---@return string name  the name of the signal delivered
function M.wait_signal(...)
  local names = { ... }
  if #names == 0 then error(core.ArgumentError("reactor.wait_signal: expects at least one signal name"), 2) end
  for i = 1, #names do
    if type(names[i]) ~= "string" then
      error(core.ArgumentError("reactor.wait_signal: signal names must be strings"), 2)
    end
  end
  uv_call.begin("reactor.wait_signal")
  local handles = {}
  local ok, name = pcall(context.suspend, function(wake)
    for i = 1, #names do
      local handle = uv.new_signal()
      handles[#handles + 1] = handle
      -- luv raises (instead of returning nil) for a name the platform does not know.
      local called, started, err = pcall(handle.start, handle, names[i], function(received) wake(received) end)
      if not called then started, err = nil, started end
      if not started then
        for j = 1, #handles do handles[j]:close() end
        handles = {}
        uv_call.fail("reactor.wait_signal", "wait_signal", tostring(err))
      end
    end
    return function()
      for i = 1, #handles do if not handles[i]:is_closing() then handles[i]:close() end end
    end
  end)
  if not ok then error(name, 0) end
  return name
end

return M
