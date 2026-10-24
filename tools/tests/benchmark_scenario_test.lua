local test = require("harness.test")
local util = require("lib.util")
local T = test.Case("BenchmarkScenarioTest")

--- Runs the tcp-echo scenario small and fast; nil when luv is not installed on this host.
local function run_small(extra)
  local command = ("%s benchmarks/run.lua tcp-echo --rounds=1 --connections=20 --rate=200 --duration=1 --warmup=0 %s 2>&1")
    :format(util.quote(util.interpreter()), extra or "")
  local text, ok = util.capture(command)
  if text:find("module 'luv' not found", 1, true) then return nil end
  return text, ok
end

function T:test_tcp_echo_completes_every_request_without_errors()
  if util.is_windows() then return end
  local text, ok = run_small()
  if not text then return end
  self:assert_true(ok, text)
  self:assert_true(text:find("throughput", 1, true) ~= nil, text)
  self:assert_true(text:find("errors%s+0%.0") ~= nil, text)
  self:assert_true(text:find("latency p99.9", 1, true) ~= nil, text)
end

function T:test_run_rejects_an_unknown_scenario_and_option()
  if util.is_windows() then return end
  local text, ok = util.capture(("%s benchmarks/run.lua no-such-scenario 2>&1"):format(util.quote(util.interpreter())))
  self:assert_false(ok)
  self:assert_true(text:find("no scenario", 1, true) ~= nil, text)
  text, ok = util.capture(("%s benchmarks/run.lua tcp-echo --bogus 2>&1"):format(util.quote(util.interpreter())))
  self:assert_false(ok)
  self:assert_true(text:find("unknown argument", 1, true) ~= nil, text)
end

return T
