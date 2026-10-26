-- A decorator sink that samples and rate-limits the records it forwards.
global <const> require, error, tostring, math, type, os

local core = require("hecate.core")
local severity = require("hecate.log.internal.severity")

--- Options of `LimitedSink`.
---@class hecate.log.LimitedSinkOptions
---@field sink hecate.log.Sink  the sink that receives the records that pass
---@field exempt? hecate.core.EnumerationValue|string  records at least this urgent always pass (default `warning`)
---@field sample? number  fraction in (0, 1] of the other records kept (default 1)
---@field rate? number  most other records forwarded per second, token bucket (default: unlimited)
---@field burst? number  bucket capacity in records (default `rate`, at least 1)
---@field random? fun(): number  uniform number in [0, 1) (default `math.random`)
---@field clock? fun(): number  seconds, may be fractional (default `os.time`)

--- A sink that forwards to another one, dropping part of the records that are less urgent than
--- `exempt`: first by sampling, then by a token bucket. Dropped records are counted. `write` never suspends.
---@class hecate.log.LimitedSink
---@overload fun(options: hecate.log.LimitedSinkOptions): hecate.log.LimitedSink
local LimitedSink = core.class("LimitedSink")

---@param value any
---@param name string
---@param low number
local function check_number(value, name, low)
  if type(value) ~= "number" or value ~= value or value <= low then
    error(core.ArgumentError(("log.LimitedSink: invalid %s %s: expected a number greater than %s"):format(name, tostring(value), low)), 3)
  end
end

--- Initialises a sink.
---
--- Raises `hecate.core.ArgumentError` for a missing sink, an unknown severity or a number out of range.
---@param options hecate.log.LimitedSinkOptions
function LimitedSink:init(options)
  local target = options and options.sink
  if type(target) ~= "table" or type(target.write) ~= "function" then
    error(core.ArgumentError("log.LimitedSink: invalid sink: expected an object with a write method"), 2)
  end
  self._sink = target
  self._exempt = severity.resolve(options.exempt or "warning", 2).ordinal
  self._sample = options.sample or 1
  check_number(self._sample, "sample", 0)
  if self._sample > 1 then error(core.ArgumentError("log.LimitedSink: invalid sample: expected at most 1"), 2) end
  self._rate = options.rate
  if self._rate ~= nil then
    check_number(self._rate, "rate", 0)
    self._capacity = options.burst or math.max(self._rate, 1)
    check_number(self._capacity, "burst", 0)
    self._tokens = self._capacity
  end
  self._random = options.random or math.random
  self._clock = options.clock or os.time
  self._last = self._clock()
  self._dropped = 0
end

--- Forwards a record unless it is sampled out or over the rate.
---@param record hecate.log.Record
function LimitedSink:write(record)
  if record.severity.ordinal > self._exempt then
    if self._sample < 1 and self._random() >= self._sample then
      self._dropped = self._dropped + 1
      return
    end
    if self._rate then
      local now = self._clock()
      local tokens = self._tokens + math.max(now - self._last, 0) * self._rate
      self._last = now
      if tokens < 1 then
        self._tokens = tokens
        self._dropped = self._dropped + 1
        return
      end
      self._tokens = math.min(tokens, self._capacity) - 1
    end
  end
  self._sink:write(record)
end

--- Returns how many records were dropped by sampling or by the rate limit.
---@return integer
function LimitedSink:dropped() return self._dropped end

return core.finalise(LimitedSink)
