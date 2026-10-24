local test = require("harness.test")
local log = require("hecate.log")
local T = test.Case("LimitedSinkTest")

local function setup(options)
  local memory = log.MemorySink()
  options.sink = memory
  local now = 0
  options.clock = function() return now end
  local limited = log.LimitedSink(options)
  local logger = log.Logger({ sinks = { limited } })
  return logger, memory, limited, function(t) now = t end
end

function T:test_defaults_forward_everything()
  local logger, memory = setup({})
  for _ = 1, 5 do logger:informational("x") end
  self:assert_equal(5, #memory:records())
end

function T:test_sampling_drops_and_counts()
  local values = { 0.1, 0.9, 0.4, 0.5 }
  local i = 0
  local logger, memory, limited = setup({ sample = 0.5, random = function() i = i + 1 return values[i] end })
  for _ = 1, 4 do logger:informational("x") end
  self:assert_equal(2, #memory:records())
  self:assert_equal(2, limited:dropped())
end

function T:test_exempt_severities_always_pass()
  local logger, memory, limited = setup({ sample = 0.5, rate = 1, burst = 1, random = function() return 0.99 end })
  logger:warning("a")
  logger:error("b")
  logger:informational("c")
  self:assert_equal(2, #memory:records())
  self:assert_equal(1, limited:dropped())
end

function T:test_the_bucket_refills_with_time()
  local logger, memory, limited, set = setup({ rate = 1, burst = 2 })
  for _ = 1, 3 do logger:informational("x") end
  self:assert_equal(2, #memory:records())
  self:assert_equal(1, limited:dropped())
  set(1)
  logger:informational("x")
  logger:informational("x")
  self:assert_equal(3, #memory:records())
end

function T:test_invalid_options_raise()
  self:assert_error(function() log.LimitedSink({}) end)
  self:assert_error(function() log.LimitedSink({ sink = log.MemorySink(), sample = 0 }) end)
  self:assert_error(function() log.LimitedSink({ sink = log.MemorySink(), sample = 2 }) end)
  self:assert_error(function() log.LimitedSink({ sink = log.MemorySink(), rate = -1 }) end)
  self:assert_error(function() log.LimitedSink({ sink = log.MemorySink(), exempt = "loud" }) end)
end

return T
