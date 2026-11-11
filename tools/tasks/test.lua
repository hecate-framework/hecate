-- test [packages...]: runs tests/**/*_test.lua of the given packages (default: all)
-- under the bootstrap harness. The name `tools` selects tools/tests, `examples/<name>` selects an example.
--
-- Concurrency: the files of `tests/unit/`, `tests/conformance/` and `tools/tests` run in a pool of worker
-- processes (HECATE_TEST_JOBS, default min(cores, 4); 1 is the serial run, in file order). The integration
-- tests (sockets, processes, services) and the examples always run serially, after the pool, so they never
-- compete for ports, timing or machine load. Results and the failure report are in a fixed order.
local util = require("lib.util")
local pool = require("lib.pool")

local function files_in(dir) return util.walk(dir, "_test.lua") end

--- True for the files that are safe to run concurrently with each other (pure, no fixed ports or paths).
local function concurrent(relative)
  return relative:find("^tools/tests/") ~= nil or relative:find("/tests/unit/", 1, true) ~= nil
    or relative:find("/tests/conformance/", 1, true) ~= nil
end

return {
  description = "run unit tests of packages (and `tools`) under the bootstrap harness (HECATE_TEST_JOBS workers)",
  run = function(ctx)
    local selected = #ctx.args > 0 and ctx.args or util.list_dir(ctx.root .. "/packages")
    local runner = ctx.root .. "/tools/harness/run_file.lua"
    -- `sanitize` on macOS: DYLD_* variables do not survive the system shell, so the variables of the
    -- sanitizer run are set on the command of each file.
    local inline = os.getenv("HECATE_SANITIZE_ENV")
    local jobs = {} -- in discovery order: { name, command }
    for _, name in ipairs(selected) do
      local example = name:match("^examples/([%w_%-]+)$")
      local base = name == "tools" and (ctx.root .. "/tools") or example and (ctx.root .. "/examples/" .. example)
        or (ctx.root .. "/packages/" .. name)
      -- Every package source tree is on the path so a package can require its declared
      -- dependencies (for example hecate.core from hecate.reactor); native rocks such as luv
      -- are found through the caller's LUA_CPATH.
      local srcs = { base .. "/src", ctx.root .. "/tools" }
      for _, other in ipairs(util.list_dir(ctx.root .. "/packages")) do
        if other ~= name then srcs[#srcs + 1] = ctx.root .. "/packages/" .. other .. "/src" end
      end
      local quoted = {}
      for i, dir in ipairs(srcs) do quoted[i] = util.quote(dir) end
      for _, file in ipairs(files_in(base .. "/tests")) do
        local relative = file:sub(#ctx.root + 2)
        jobs[#jobs + 1] = {
          name = relative,
          concurrent = not example and concurrent(relative),
          command = ("%s%s %s %s %s 2>&1"):format(inline and (inline .. " ") or "", util.quote(util.interpreter()),
            util.quote(runner), util.quote(file), table.concat(quoted, " ")),
        }
      end
    end

    local workers = pool.workers()
    local ordered = {}
    if workers == 1 then
      ordered = { jobs } -- the serial run, in discovery order
    else
      local parallel, serial = {}, {}
      for _, job in ipairs(jobs) do table.insert(job.concurrent and parallel or serial, job) end
      ordered = { parallel, serial }
    end

    local problems = {}
    for phase, group in ipairs(ordered) do
      local commands = {}
      for i, job in ipairs(group) do commands[i] = job.command end
      local results = pool.run(commands, (workers == 1 or phase == 2) and 1 or workers, function(index)
        -- CI sets CI=true: name the file before running it, so a cancelled run shows where it stopped.
        if os.getenv("CI") then io.stderr:write("# test ", group[index].name, "\n") end
      end)
      for i, job in ipairs(group) do
        if not results[i].ok then problems[#problems + 1] = job.name .. "\n" .. results[i].output end
      end
    end
    return { ok = #problems == 0, problems = problems, count = #jobs }
  end,
}
