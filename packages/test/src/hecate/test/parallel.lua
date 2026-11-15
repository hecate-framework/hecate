-- Parallel runs: one worker process per test file, each with its own reactor (testing.md, "Parallelism").
--   * The coordinator starts at most `jobs` workers at once (`reactor.run_process`); a worker loads one
--     file, runs it with a `Runner` and prints its events as one JSON line behind a marker.
--   * The coordinator replays the events of the files to the reporter in the order of the paths, so
--     the stream a reporter sees is deterministic and has the shape of a sequential run.
--   * Limits of this first version: the reporter sees nothing before every worker has finished (the
--     plan of a run, `run_started`, needs the total of all files); what a test prints to its standard
--     output is dropped.
global <const> require, type, ipairs, error, io, os, package, arg, string, table, pcall, tostring

local core = require("hecate.core")
local reactor = require("hecate.reactor")
local discovery = require("hecate.test.discovery")

local MARKER = "\30hecate-test-events\30"

---@class hecate.test.parallel
local M = {}

---@class hecate.test.ParallelOptions
---@field jobs? integer  workers running at once (default 2)
---@field runner? hecate.test.RunnerOptions  `filter`, `cases`, `tags`, `exclude_tags`, `clock` of each worker (no reporter)
---@field reporter? hecate.test.Reporter  receives the events of the run, in the order of the paths
---@field lua? string  Lua interpreter that runs a worker (default: the running one)

--- Body of a worker: runs the test file `job.path` and prints its events. Called by the coordinator
--- through `lua -e`; not meant for other callers.
---@param encoded string  JSON text `{ path, options }`
function M.work(encoded)
  local json = require("hecate.json")
  local job = json.decode(encoded)
  local events = {}
  local function write(payload) io.write(MARKER, json.encode(payload), "\n") end
  local ok, err = pcall(function()
    local case = discovery.load(job.path)
    local options = job.options or {}
    options.reporter = { handle = function(_, event) events[#events + 1] = event end }
    require("hecate.test.runner")(options):run({ case })
  end)
  if not ok then
    write({ failure = tostring(err) })
  else
    write({ events = events })
  end
end

--- The events a path produced, or a synthetic errored suite when its worker failed.
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

local function launch(path, options, lua)
  local json = require("hecate.json")
  local job = json.encode({ path = path, options = options })
  local code = ("package.path=%q package.cpath=%q require('hecate.test.parallel').work(%q)"):format(
    package.path, package.cpath, job)
  local ok, result = pcall(reactor.run_process, lua, { "-e", code })
  if not ok then return synthetic(path, "cannot start a worker: " .. tostring(result)) end
  local from, to = result.stdout:find(MARKER, 1, true)
  local line = from and result.stdout:match("^[^\n]*", to + 1)
  if not line then
    local tail = (result.stderr or ""):gsub("%s+$", "")
    return synthetic(path, ("worker ended with code %s without a result%s"):format(
      tostring(result.code), tail ~= "" and ("\n" .. tail) or ""))
  end
  local payload = json.decode(line)
  if payload.failure then return synthetic(path, payload.failure) end
  return payload.events
end

--- Runs the test files `paths` in worker processes, at most `options.jobs` at once, and returns the
--- summary (the shape of `Runner:run`). Must be called inside a reactor (it suspends). Never raises
--- for a failing test or a file that does not load: that file becomes an errored suite.
---@async
---@param paths string[]  test files
---@param options? hecate.test.ParallelOptions
---@return hecate.test.Summary summary
function M.run(paths, options)
  options = options or {}
  local jobs = options.jobs or 2
  if type(jobs) ~= "number" or jobs < 1 or jobs % 1 ~= 0 then
    error(core.ArgumentError("test.run_parallel: jobs must be a positive integer"), 2)
  end
  local lua = options.lua or (arg and arg[-1]) or "lua"
  local gate = reactor.Semaphore(jobs)
  local futures = {}
  for index, path in ipairs(paths) do
    futures[index] = reactor.fork(function()
      local permit = gate:acquire()
      local events = launch(path, options.runner, lua)
      permit:release()
      return events
    end)
  end
  local batches = {}
  for index, future in ipairs(futures) do batches[index] = reactor.join(future) end

  local summary = {
    total = 0, passed = 0, failed = 0, errored = 0, assertions = 0, ok = true, exit_code = 0,
    results = {}, suites = {}, duration = 0,
  }
  local reporter = options.reporter
  local function emit(event) if reporter then reporter:handle(event) end end
  local suites = 0
  for _, events in ipairs(batches) do
    for _, event in ipairs(events) do
      if event.type == "run_started" then summary.total = summary.total + event.total; suites = suites + event.suites end
    end
  end
  emit({ type = "run_started", total = summary.total, suites = suites })
  for _, events in ipairs(batches) do
    for _, event in ipairs(events) do
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
      if event.type ~= "run_started" and event.type ~= "run_finished" then emit(event) end
    end
  end
  emit({ type = "run_finished", summary = summary })
  return summary
end

return M
