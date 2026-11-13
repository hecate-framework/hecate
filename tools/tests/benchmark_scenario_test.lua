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

--- Runs an HTTP scenario small and fast; nil when luv or a native module is missing on this host.
---@param scenario string
---@param extra? string
local function run_http(scenario, extra)
  local command = ("%s benchmarks/run.lua %s --rounds=1 --connections=10 --rate=200 --duration=1 --warmup=0 %s 2>&1")
    :format(util.quote(util.interpreter()), scenario, extra or "")
  local text, ok = util.capture(command)
  if text:find("module 'luv' not found", 1, true) or text:find("skipped", 1, true) then return nil end
  return text, ok
end

function T:test_plaintext_answers_every_request_with_a_200()
  if util.is_windows() then return end
  local text, ok = run_http("plaintext")
  if not text then return end
  self:assert_true(ok, text)
  self:assert_true(text:find("throughput%s+[1-9]") ~= nil, text)
  self:assert_true(text:find("errors%s+0%.0") ~= nil, text)
  self:assert_true(text:find("bad responses%s+0%.0") ~= nil, text)
  self:assert_true(text:find("latency p99.9", 1, true) ~= nil, text)
end

function T:test_plaintext_pipelines_batches_of_requests()
  if util.is_windows() then return end
  local text, ok = run_http("plaintext", "--pipeline=4")
  if not text then return end
  self:assert_true(ok, text)
  self:assert_true(text:find("throughput%s+[1-9]") ~= nil, text)
  self:assert_true(text:find("bad responses%s+0%.0") ~= nil, text)
end

function T:test_json_answers_every_request_through_the_kernel()
  if util.is_windows() then return end
  local text, ok = run_http("kernel-json")
  if not text then return end
  self:assert_true(ok, text)
  self:assert_true(text:find("throughput%s+[1-9]") ~= nil, text)
  self:assert_true(text:find("errors%s+0%.0") ~= nil, text)
  self:assert_true(text:find("bad responses%s+0%.0") ~= nil, text)
end

function T:test_http_load_counts_a_status_other_than_200_as_a_bad_response()
  if util.is_windows() then return end
  local text, ok = run_http("kernel-json", "--path=/missing")
  if not text then return end
  self:assert_true(ok, text)
  self:assert_true(text:find("bad responses%s+10%.0") ~= nil, text)
  self:assert_true(text:find("throughput%s+0%.0") ~= nil, text)
end

function T:test_accept_spread_ratio_is_the_largest_over_the_smallest_count()
  local spread = dofile("benchmarks/scenarios/accept-spread/spread.lua")
  self:assert_equal(1, spread.ratio({ 250, 250, 250, 250 }))
  self:assert_equal(2, spread.ratio({ 100, 200, 150 }))
  self:assert_equal(0, spread.ratio({}))
  self:assert_equal(0, spread.ratio({ 0, 0 }))
  self:assert_equal(300, spread.ratio({ 300, 0, 100 })) -- a worker that took nothing: the largest count
end

function T:test_accept_spread_balances_round_robin_and_skips_an_unavailable_strategy()
  if util.is_windows() then return end
  local command = ("%s benchmarks/run.lua accept-spread --rounds=1 --rate=100 --duration=1 --server-args=\"round_robin 2\" 2>&1")
    :format(util.quote(util.interpreter()))
  local text, ok = util.capture(command)
  if text:find("module 'luv' not found", 1, true) then return end
  self:assert_true(ok, text)
  self:assert_true(text:find("spread%s+1%.0") ~= nil, text)
  self:assert_true(text:find("errors%s+0%.0") ~= nil, text)
  text, ok = util.capture(("%s benchmarks/run.lua accept-spread --rounds=1 --server-args=\"nonsense 2\" 2>&1")
    :format(util.quote(util.interpreter())))
  self:assert_false(ok)
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

function T:test_a_scenario_given_runs_names_the_rounds_option()
  if util.is_windows() then return end
  local text, ok = util.capture(("%s tools/run.lua bench tcp-echo --runs=1 2>&1"):format(util.quote(util.interpreter())))
  self:assert_false(ok)
  self:assert_true(text:find("--rounds=N", 1, true) ~= nil, text)
  self:assert_nil(text:find("unknown argument", 1, true), text)
end

function T:test_list_shows_the_scenarios_next_to_the_micro_benchmarks()
  local text, ok = util.capture(("%s tools/run.lua bench --list 2>&1"):format(util.quote(util.interpreter())))
  self:assert_true(ok, text)
  self:assert_true(text:find("tcp-echo", 1, true) ~= nil, text)
  self:assert_true(text:find("plaintext", 1, true) ~= nil, text)
  self:assert_true(text:find("kernel-json", 1, true) ~= nil, text)
  self:assert_true(text:find("core/dispatch", 1, true) ~= nil, text)
end

return T
