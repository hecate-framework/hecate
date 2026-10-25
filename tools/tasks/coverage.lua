-- coverage [package...]: runs the tests with line recording, writes coverage/lcov.info and fails when
-- core, reactor, router or schema fall under their threshold (docs/architecture/automation.md).
local util = require("lib.util")
local coverage = require("lib.coverage")

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local text = f:read("a")
  f:close()
  return text
end

return {
  description = "line coverage report (LCOV) with per-package thresholds",
  run = function(ctx)
    local root = coverage.normalize(ctx.root)
    local out_dir = ctx.root .. "/coverage"
    local data = out_dir .. "/data"
    util.mkdir(out_dir)
    util.mkdir(data)
    for _, name in ipairs(util.list_dir(data)) do os.remove(data .. "/" .. name) end
    local args = {}
    for i, name in ipairs(ctx.args) do args[i] = util.quote(name) end
    local out, ok = util.capture(("%s%s %s test %s 2>&1"):format(coverage.environment(data, util.is_windows()),
      util.quote(util.interpreter()), util.quote(ctx.root .. "/tools/run.lua"), table.concat(args, " ")))
    local problems = {}
    if not ok then problems[#problems + 1] = "tests failed:\n" .. out end

    local hits = {}
    for _, name in ipairs(util.list_dir(data)) do coverage.parse_hits(read(data .. "/" .. name) or "", hits) end

    local selected = #ctx.args > 0 and ctx.args or util.list_dir(ctx.root .. "/packages")
    local files, stats = {}, {}
    for _, package in ipairs(selected) do
      local base = ctx.root .. "/packages/" .. package .. "/src"
      local s = { total = 0, covered = 0 }
      for _, path in ipairs(util.walk(base, ".lua")) do
        local normal = coverage.normalize(path)
        local executable = coverage.executable_lines(read(path) or "")
        local total, covered = coverage.count(executable, hits[normal])
        s.total, s.covered = s.total + total, s.covered + covered
        files[#files + 1] = { path = normal:sub(#root + 2), executable = executable, hit = hits[normal] }
      end
      stats[package] = s
    end
    local report = assert(io.open(out_dir .. "/lcov.info", "w"))
    report:write(coverage.lcov(files))
    report:close()
    for _, problem in ipairs(coverage.check(stats)) do problems[#problems + 1] = problem end
    local summary = {}
    for _, package in ipairs(selected) do
      local s = stats[package]
      summary[#summary + 1] = ("%s %.1f%%"):format(package, coverage.percent(s.total, s.covered))
    end
    io.stderr:write("coverage: ", table.concat(summary, ", "), "\n")
    return { ok = #problems == 0, problems = problems, stats = stats }
  end,
}
