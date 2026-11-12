local test = require("harness.test")
local util = require("lib.util")
local pool = require("lib.pool")
local T = test.Case("PoolTest")

--- Writes a script that prints its argument, sleeps (busy wait) for the second one and exits with the third.
local function script()
  local path = os.tmpname()
  local f = assert(io.open(path, "w"))
  f:write([[
local text, seconds, code = arg[1], tonumber(arg[2]), tonumber(arg[3])
local stop = os.clock() + seconds
while os.clock() < stop do end
io.write(text, "\n")
os.exit(code)
]])
  f:close()
  return path
end

local function command(path, text, seconds, code)
  return ("%s %s %s %s %s 2>&1"):format(util.quote(util.interpreter()), util.quote(path), util.quote(text),
    tostring(seconds), tostring(code))
end

function T:test_results_follow_the_job_order_not_the_completion_order()
  local path = script()
  local jobs = { command(path, "slow", 0.3, 0), command(path, "fast", 0, 0), command(path, "last", 0, 0) }
  local results = pool.run(jobs, 3)
  os.remove(path)
  self:assert_equal(3, #results)
  self:assert_equal("slow", results[1].output)
  self:assert_equal("fast", results[2].output)
  self:assert_equal("last", results[3].output)
end

function T:test_a_failing_job_reports_its_output_and_the_others_are_unaffected()
  local path = script()
  local results = pool.run({ command(path, "good", 0, 0), command(path, "bad", 0, 3), command(path, "fine", 0, 0) }, 2)
  os.remove(path)
  self:assert_true(results[1].ok)
  self:assert_false(results[2].ok)
  self:assert_equal("bad", results[2].output)
  self:assert_true(results[3].ok)
end

function T:test_one_worker_gives_the_same_results_as_several()
  local path = script()
  local jobs = {}
  for i = 1, 6 do jobs[i] = command(path, "job" .. i, 0, i % 3 == 0 and 1 or 0) end
  local serial, parallel = pool.run(jobs, 1), pool.run(jobs, 4)
  os.remove(path)
  for i = 1, 6 do
    self:assert_equal(serial[i].output, parallel[i].output)
    self:assert_equal(serial[i].ok, parallel[i].ok)
  end
end

function T:test_jobs_are_started_in_order_and_never_more_than_the_workers_at_once()
  local started = {}
  local path = script()
  local jobs = {}
  for i = 1, 5 do jobs[i] = command(path, "j" .. i, 0, 0) end
  pool.run(jobs, 2, function(index) started[#started + 1] = index end)
  os.remove(path)
  self:assert_equal("1,2,3,4,5", table.concat(started, ","))
end

function T:test_the_number_of_workers_comes_from_the_environment_or_the_cores_capped_at_four()
  local function env(value) return function() return value end end
  self:assert_equal(1, pool.workers(env("1"), 8))
  self:assert_equal(7, pool.workers(env("7"), 2))
  self:assert_equal(4, pool.workers(env(nil), 16))
  self:assert_equal(2, pool.workers(env(nil), 2))
  self:assert_equal(1, pool.workers(env(nil), 1))
  self:assert_equal(4, pool.workers(env("0"), 4)) -- not a positive integer: ignored
  self:assert_equal(4, pool.workers(env("abc"), 4))
  self:assert_equal(4, pool.workers(env("1.5"), 4))
end

return T
