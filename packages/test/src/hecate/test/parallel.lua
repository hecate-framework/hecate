-- Parallel runs: one worker process per test file, each with its own reactor (testing.md, "Parallelism"). The
-- primary (the process that calls `run`) and the workers share nothing but a message pipe per worker.
--   * Plan: each file is loaded by a worker that counts its tests and suites and exits, so the primary knows the
--     total of the whole run before it reports anything (`run_started`).
--   * Run: each file is run by a worker that sends its events over the pipe as they happen. The primary replays
--     them to the reporter in the order of the paths: the events of the first unfinished file flow live, those of
--     later files wait for their turn, so the stream a reporter sees is deterministic and has the shape of a
--     sequential run, and a console shows progress while the files run.
--   * A worker that cannot start, dies, or sends something unreadable becomes an errored suite; it never stops the
--     run. What a test prints to its standard output is dropped; its standard error goes to the primary's.
global <const> require, type, ipairs, pairs, error, pcall, tostring, package, arg, os, math, table

local core = require("hecate.core")
local reactor = require("hecate.reactor")
local discovery = require("hecate.test.discovery")

---@class hecate.test.parallel
local M = {}

-- The options a runner accepts that cross a process boundary, and those of the run itself.
local RUNNER_KEYS = { filter = true, cases = true, tags = true, exclude_tags = true, clock = true }
local PARALLEL_KEYS = { jobs = true, lua = true, reporter = true, coverage = true }

--- Options of `run_parallel`: the options of a runner that cross a process boundary (`filter`, `cases`, `tags`,
--- `exclude_tags`, `clock`, flat, as for `Runner`) and those of the run itself.
---@class hecate.test.ParallelOptions
---@field jobs? integer  workers running at once (default 2)
---@field filter? string  as for `Runner`: Lua pattern on the full test name
---@field cases? string[]  as for `Runner`
---@field tags? string[]  as for `Runner`
---@field exclude_tags? string[]  as for `Runner`
---@field clock? "real"|"virtual"  as for `Runner`
---@field reporter? hecate.test.Reporter  receives the events of the run, live and in the order of the paths
---@field coverage? hecate.test.LineCoverage  receives the lines the workers ran (its `include` must be a pattern, not a predicate)
---@field lua? string  Lua interpreter that runs a worker (default: the running one, found in `arg`)

--- The Lua interpreter that started the script: the lowest index of `arg`, which holds the interpreter name followed
--- by the options it was given (`lua -W script.lua`). `nil` when `arg` is missing (an embedding host) or holds no
--- interpreter.
---@param arguments? table  the `arg` table (default: the global `arg`)
---@return string? interpreter
function M.interpreter(arguments)
  if type(arguments) ~= "table" then return nil end
  local index = 0
  while arguments[index - 1] ~= nil do index = index - 1 end
  if index == 0 then return nil end
  return arguments[index]
end

-- ---------------------------------------------------------------------------------------------------------
-- The worker

--- Body of a worker: reads its job from the message pipe, runs it and sends the results. Called through `lua -e` by
--- the primary; not meant for other callers.
---@private
function M.work()
  local ipc = require("hecate.reactor.ipc")
  local json = require("hecate.json")
  local peer = ipc.parent()
  if peer == nil then error("hecate.test.parallel.work: not started by test.run_parallel", 0) end
  -- a message is one short reactor run: the runner starts a reactor of its own for each test, so none may be running
  local function send(payload) reactor.run(function() peer:send(json.encode(payload)) end) end
  local job
  reactor.run(function()
    local text = peer:receive()
    job = text and json.decode(text)
  end)
  if type(job) ~= "table" then os.exit(2) end -- the primary is gone
  local ok, err = pcall(function()
    local case = discovery.load(job.path)
    local options = job.options or {}
    local Runner = require("hecate.test.runner")
    if job.mode == "plan" then
      local suites, last, tests = 0, nil, Runner(options):plan({ case })
      for _, test in ipairs(tests) do
        if test.suite ~= last then suites, last = suites + 1, test.suite end
      end
      send({ t = "plan", total = #tests, suites = suites })
      return
    end
    local coverage
    if job.coverage then
      coverage = require("hecate.test.line_coverage")(job.coverage)
      options.coverage = coverage
    end
    options.reporter = { handle = function(_, event)
      if event.type ~= "run_started" and event.type ~= "run_finished" then send({ t = "event", event = event }) end
    end }
    Runner(options):run({ case })
    local hits
    if coverage then
      -- JSON object keys are text: a line number becomes the text of the number
      hits = {}
      for path, lines in pairs(coverage:hits()) do
        local copy = {}
        for line, count in pairs(lines) do copy[tostring(line)] = count end
        hits[path] = copy
      end
    end
    send({ t = "done", hits = hits })
  end)
  if not ok then send({ t = "failure", message = tostring(err) }) end
end

-- ---------------------------------------------------------------------------------------------------------
-- The primary

-- A failure reason that holds no more than one line of text.
local function describe(failure)
  local text = type(failure) == "table" and failure.message or failure
  return (tostring(text):gsub("%s+", " "))
end

--- Starts a worker for `job`, sends it the job and hands every message it sends to `on_message` until that returns
--- true (the worker's last message) or the pipe closes. Returns nil on success, or the reason the worker failed.
---@async
---@param lua string
---@param job table
---@param on_message fun(message: table): boolean?
---@return string? failure
local function converse(lua, job, on_message)
  local json = require("hecate.json")
  local code = ("package.path=%q package.cpath=%q require('hecate.test.parallel').work()"):format(
    package.path, package.cpath)
  local started, process = pcall(reactor.spawn, lua, { "-e", code }, { ipc = true, stdout = "ignore" }) -- glossary-ok: starts an operating-system process (ADR 0023)
  if not started then return "cannot start a worker: " .. describe(process) end
  local finished = false
  local ok, failure = pcall(function()
    process.ipc:send(json.encode(job))
    while true do
      local text = process.ipc:receive()
      if text == nil then return end
      local message = json.decode(text)
      if type(message) ~= "table" or type(message.t) ~= "string" then error("not a message", 0) end
      if on_message(message) then
        finished = true
        return
      end
    end
  end)
  if not ok or not finished then pcall(process.kill, process) end
  local exited, result = pcall(process.wait, process)
  if not ok then
    if core.is_instance_of(failure, core.CancellationError) then error(failure, 0) end
    return "the worker sent an unreadable result (" .. describe(failure) .. ")"
  end
  if not finished then
    return ("worker ended with code %s without a result"):format(exited and tostring(result and result.code) or "?")
  end
  return nil
end

local EVENT_TYPES = { suite_started = true, test_started = true, test_finished = true, suite_finished = true }
local STATUSES = { passed = true, failed = true, errored = true }

-- True when an event of a worker has the shape the summary and the reporters rely on.
local function valid_event(event)
  if type(event) ~= "table" or not EVENT_TYPES[event.type] then return false end
  if event.type == "test_finished" then
    local result = event.result
    return type(result) == "table" and STATUSES[result.status] == true and math.type(result.assertions) == "integer"
  elseif event.type == "suite_finished" then
    return type(event.summary) == "table" and type(event.summary.duration) == "number"
  end
  return true
end

-- The events of a file that could not be run: an errored suite.
local function synthetic(path, message)
  local name = "load " .. path
  local result = { name = name, case = "load", suite = path, status = "errored", assertions = 0, message = message,
    duration = 0 }
  local suite = { name = path, total = 1, passed = 0, failed = 0, errored = 1, assertions = 0, duration = 0 }
  return {
    { type = "suite_started", suite = path, total = 1 },
    { type = "test_started", suite = path, test = name, index = 1 },
    { type = "test_finished", suite = path, test = name, index = 1, result = result },
    { type = "suite_finished", suite = path, summary = suite },
  }
end

-- Plans one file: `{ total, suites }`, or a failure message.
---@async
local function plan_file(lua, path, runner)
  local plan
  local failure = converse(lua, { mode = "plan", path = path, options = runner }, function(message)
    if message.t == "plan" and math.type(message.total) == "integer" and math.type(message.suites) == "integer" then
      plan = { total = message.total, suites = message.suites }
    elseif message.t == "failure" then
      plan = { failure = tostring(message.message) }
    else
      plan = { failure = "the worker sent an unexpected message" }
    end
    return true
  end)
  if failure then return { failure = failure } end
  return plan or { failure = "the worker sent no plan" }
end

--- Runs the test files `paths` in worker processes, at most `options.jobs` at once, and returns the summary (the
--- shape of `Runner:run`). Must be called inside a reactor (it suspends). Never raises for a failing test, a file that
--- does not load or a worker that fails: that file becomes an errored suite.
---
--- Raises `hecate.core.ArgumentError` for bad options, and when the interpreter cannot be found (`options.lua`).
---@async
---@param paths string[]  test files
---@param options? hecate.test.ParallelOptions
---@return hecate.test.Summary summary
function M.run(paths, options)
  if options ~= nil and type(options) ~= "table" then
    error(core.ArgumentError("test.run_parallel: expects an options table, got " .. type(options)), 2)
  end
  options = options or {}
  local runner = {}
  for key, value in pairs(options) do
    if RUNNER_KEYS[key] then runner[key] = value
    elseif not PARALLEL_KEYS[key] then error(core.ArgumentError("test.run_parallel: unknown option " .. tostring(key)), 2) end
  end
  local jobs = options.jobs or 2
  if math.type(jobs) ~= "integer" or jobs < 1 then
    error(core.ArgumentError("test.run_parallel: jobs must be a positive integer"), 2)
  end
  local lua = options.lua or M.interpreter(arg)
  if lua == nil then
    error(core.ArgumentError("test.run_parallel: the interpreter is unknown (no `arg`); give the option lua"), 2)
  end
  local coverage, settings = options.coverage, nil
  if coverage ~= nil then
    if not core.is_instance_of(coverage, require("hecate.test.line_coverage")) then
      error(core.ArgumentError("test.run_parallel: coverage must be a test.LineCoverage"), 2)
    end
    settings = coverage:settings()
  end

  local gate = reactor.Semaphore(jobs)
  local function within_gate(work)
    local permit = gate:acquire()
    local ok, result = pcall(work)
    permit:release()
    if not ok then
      if core.is_instance_of(result, core.CancellationError) then error(result, 0) end
      return { failure = "worker failed: " .. describe(result) }
    end
    return result
  end

  -- Plan: every file is loaded and counted before anything is reported.
  local planning = {}
  for index, path in ipairs(paths) do
    planning[index] = reactor.fork(function()
      return within_gate(function() return plan_file(lua, path, runner) end)
    end)
  end
  local plans, total, suites = {}, 0, 0
  for index in ipairs(paths) do
    local plan = reactor.join(planning[index])
    plans[index] = plan
    if plan.failure then total, suites = total + 1, suites + 1 else total, suites = total + plan.total, suites + plan.suites end
  end

  local summary = {
    total = total, passed = 0, failed = 0, errored = 0, assertions = 0, ok = true, exit_code = 0,
    results = {}, suites = {}, duration = 0,
  }
  local reporter = options.reporter
  local function emit(event) if reporter then reporter:handle(event) end end
  emit({ type = "run_started", total = total, suites = suites })

  -- Run: workers send events as they happen; the first unfinished file is replayed live, the others wait.
  local inbox = reactor.Channel(1 << 30)
  local running = {}
  for index, path in ipairs(paths) do
    running[index] = reactor.fork(function()
      within_gate(function()
        local seen = false
        local failure = converse(lua, { mode = "run", path = path, options = runner, coverage = settings },
          function(message)
            if message.t == "event" then
              if valid_event(message.event) then
                seen = true
                inbox:send({ index = index, event = message.event })
                return false
              end
              error("an event of an unknown shape", 0)
            elseif message.t == "done" then
              if coverage and type(message.hits) == "table" then pcall(coverage.merge, coverage, message.hits) end
              return true
            elseif message.t == "failure" then
              error(tostring(message.message), 0)
            end
            error("an unexpected message", 0)
          end)
        inbox:send({ index = index, finished = true, failure = failure, seen = seen })
        return true
      end)
      return true
    end)
  end

  local buffers, closed, open_suite, last_index = {}, {}, {}, {}
  for index in ipairs(paths) do buffers[index] = {} end
  local current = 1
  local function replay(event)
    if event.type == "test_finished" then
      local result = event.result
      summary.results[#summary.results + 1] = result
      summary[result.status] = summary[result.status] + 1
      summary.assertions = summary.assertions + result.assertions
      if result.status ~= "passed" then summary.ok, summary.exit_code = false, 1 end
    elseif event.type == "suite_finished" then
      summary.suites[#summary.suites + 1] = event.summary
      summary.duration = summary.duration + event.summary.duration
    end
    emit(event)
  end
  local function close_file(index)
    local info = closed[index]
    if info.failure then
      -- a file that failed: what was replayed stays; the failure is one more errored test of its suite
      local path = paths[index]
      if open_suite[index] then
        local synthetic_events = synthetic(path, info.failure)
        replay(synthetic_events[3])
        replay(synthetic_events[4])
      else
        for _, event in ipairs(synthetic(path, info.failure)) do replay(event) end
      end
    end
  end
  local function flush()
    while current <= #paths do
      local queue = buffers[current]
      while #queue > 0 do
        local event = table.remove(queue, 1)
        if event.type == "suite_started" then open_suite[current] = true
        elseif event.type == "suite_finished" then open_suite[current] = false end
        replay(event)
      end
      if closed[current] then
        close_file(current)
        current = current + 1
      else
        return
      end
    end
  end
  while current <= #paths do
    flush()
    if current > #paths then break end
    local message = inbox:receive()
    if message.finished then closed[message.index] = message
    else buffers[message.index][#buffers[message.index] + 1] = message.event end
  end
  for index in ipairs(paths) do reactor.join(running[index]) end

  -- The totals announced by the plan may differ from what ran (a file that failed after its plan): the summary
  -- counts what ran.
  summary.total = #summary.results
  summary.empty = summary.total == 0
  emit({ type = "run_finished", summary = summary })
  return summary
end

return M
