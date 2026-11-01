-- A decorator sink that hands records to a detached computation, so that logging never waits for I/O.
global <const> require, error, type, pcall, math

local core = require("hecate.core")
local reactor = require("hecate.reactor")

--- Options of `AsyncSink`.
---@class hecate.log.AsyncSinkOptions
---@field sink hecate.log.Sink  the sink that receives the records, from the drain computation
---@field capacity? integer  most records waiting at once (default 1024); beyond it records are dropped and counted

--- A sink that queues records and writes them to another sink from a detached computation. `write` never
--- suspends: it appends to a bounded queue and adds one unit to a semaphore (Dijkstra's V) that
--- the drain computation takes (P), so a slow target costs the callers nothing. When the queue is full
--- the record is dropped and counted: back-pressure is loss, never waiting.
--- The drain computation starts at the first `write`, which therefore must run inside a reactor. Call `close` before
--- the main computation ends: a drain computation still waiting for records is a deadlock to the reactor.
---@class hecate.log.AsyncSink : hecate.log.Sink
---@overload fun(options: hecate.log.AsyncSinkOptions): hecate.log.AsyncSink
local AsyncSink = core.class("AsyncSink")

--- Initialises a sink.
---
--- Raises `hecate.core.ArgumentError` for a missing sink or a capacity that is not a positive integer.
---@param options hecate.log.AsyncSinkOptions
function AsyncSink:init(options)
  local target = options and options.sink
  if type(target) ~= "table" or type(target.write) ~= "function" then
    error(core.ArgumentError("log.AsyncSink: invalid sink: expected an object with a write method"), 2)
  end
  local capacity = options.capacity or 1024
  if math.type(capacity) ~= "integer" or capacity < 1 then
    error(core.ArgumentError("log.AsyncSink: invalid capacity: expected a positive integer"), 2)
  end
  self._sink = target
  self._capacity = capacity
  self._queue = {}
  self._head, self._count = 1, 0 -- entries of `_queue`: records and markers, FIFO
  self._records = 0 -- records waiting (markers excluded)
  self._items = reactor.Semaphore(0) -- one unit per queued entry
  self._drain = nil
  self._closed = false
  self._closing = nil -- future of the shutdown, set by the first `close`
  self._dropped, self._failures = 0, 0
end

---@param self hecate.log.AsyncSink
---@param entry table
local function push(self, entry)
  self._queue[self._head + self._count] = entry
  self._count = self._count + 1
  self._items:release()
end

--- Writes the queued records to the target, in order, until a stop marker is reached.
---@async
---@param self hecate.log.AsyncSink
local function drain(self)
  while true do
    self._items:acquire() -- the unit is consumed on purpose: the permit is not released
    local index = self._head
    local entry = self._queue[index]
    self._queue[index] = nil
    self._count = self._count - 1
    self._head = self._count == 0 and 1 or index + 1
    if entry.marker then
      entry.reached:release()
      if entry.stop then return end
    else
      self._records = self._records - 1
      local ok = pcall(self._sink.write, self._sink, entry)
      if not ok then self._failures = self._failures + 1 end
    end
  end
end

--- Queues a record, or drops it when the queue is full or the sink is closed. Never suspends.
---
--- Raises `hecate.core.NonYieldableContextError` when the drain computation has to start outside a reactor.
---@param record hecate.log.Record
function AsyncSink:write(record)
  if self._closed then return end
  if self._records >= self._capacity then
    self._dropped = self._dropped + 1
    return
  end
  if not self._drain then self._drain = reactor.detach(drain, self) end
  self._records = self._records + 1
  push(self, record)
end

---@async
---@param self hecate.log.AsyncSink
---@param stop boolean
local function wait_marker(self, stop)
  local marker = { marker = true, stop = stop, reached = reactor.Semaphore(0) }
  push(self, marker)
  marker.reached:acquire()
end

--- Suspends until every record queued before the call has been written to the target. Does nothing
--- on a sink that was never written to or is closed.
---@async
function AsyncSink:flush()
  if not self._drain or self._closed then return end
  wait_marker(self, false)
end

--- Stops the drain computation, then closes the target. Runs detached, so that a closer that is cancelled
--- does not leave the sink half closed.
---@async
---@param self hecate.log.AsyncSink
local function shut_down(self)
  if self._drain then
    wait_marker(self, true)
    self._drain:value()
  end
  local close = self._sink["close"]
  if type(close) == "function" then close(self._sink) end
end

--- Flushes, then stops the drain computation; later writes are ignored. Closing again, also while a first
--- `close` is still waiting for the drain, suspends until the drain has ended and reports the same
--- outcome: it returns, or raises the error raised by the `close` of the target.
---@async
function AsyncSink:close()
  if not self._closing then
    self._closed = true
    if self._drain then
      self._closing = reactor.detach(shut_down, self)
    else
      -- Nothing was ever queued: no drain to wait for, so no suspension, and this works outside a reactor.
      local close = self._sink["close"]
      local ok, err = true, nil
      if type(close) == "function" then ok, err = pcall(close, self._sink) end
      self._closing = { failure = not ok and err or nil } -- the outcome every later `close` reports
    end
  end
  local closing = self._closing
  if reactor.is_future(closing) then
    closing:value()
  elseif closing.failure ~= nil then
    error(closing.failure, 0)
  end
end

--- Returns how many records were dropped because the queue was full.
---@return integer
function AsyncSink:dropped() return self._dropped end

--- Returns how many writes to the target raised.
---@return integer
function AsyncSink:failures() return self._failures end

--- Returns how many records wait to be written.
---@return integer
function AsyncSink:pending() return self._records end

return core.finalise(AsyncSink)
