-- bench [name...] [options]: browses and runs the benchmarks of the repository on a Linux host (Ubuntu
-- server is the reference platform, benchmarks/README.md). A benchmark is a file
-- `packages/<package>/benchmarks/<name>.lua`, named `<package>/<name>`; it prints measurement lines
-- (`label  value unit`) and exits. Without a name and on a terminal the task shows a menu.
--
--   --list           list the benchmarks and stop
--   --runs=N         rounds (default 5); each round runs every selected benchmark once, so drift is spread
--   --pin=CPUS       run on these CPUs only (taskset -c), e.g. --pin=2,3
--   --out=DIR        results directory (default benchmarks/results/<host>-<UTC date and time>)
--   --yes            do not ask for confirmation when the host is not quiet
--   --strict         the checks of a quiet host are errors, not warnings
--
-- Results: host-before.md and host-after.md (benchmarks/host-report.sh), run-<n>/<benchmark>.txt, and
-- summary.md (minimum, median, maximum and spread of every measure over the runs).
local util = require("lib.util")
local bench = require("lib.bench")

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local text = f:read("a")
  f:close()
  return text
end

local function write(path, text)
  local f = assert(io.open(path, "wb"))
  f:write(text)
  f:close()
end

local function discover(root)
  local found = {}
  for _, package in ipairs(util.list_dir(root .. "/packages")) do
    local dir = ("%s/packages/%s/benchmarks"):format(root, package)
    if util.is_dir(dir) then
      for _, file in ipairs(util.list_dir(dir)) do
        local name = file:match("^(.+)%.lua$")
        if name then
          local path = ("packages/%s/benchmarks/%s"):format(package, file)
          found[#found + 1] = {
            id = package .. "/" .. name, path = path,
            description = bench.describe(read(root .. "/" .. path) or ""),
          }
        end
      end
    end
  end
  return found
end

local function number(path)
  local text = read(path)
  return text and tonumber((text:gsub("%s+", ""))) or nil
end

--- What disturbs a measurement on this host; empty when it looks quiet.
local function noisy(root)
  local issues = {}
  local governor = (read("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor") or ""):gsub("%s+", "")
  if governor ~= "" and governor ~= "performance" then
    issues[#issues + 1] = ("CPU governor is '%s' (use performance: sudo cpupower frequency-set -g performance)"):format(governor)
  end
  if number("/sys/devices/system/cpu/intel_pstate/no_turbo") == 0 then
    issues[#issues + 1] = "turbo is on (fine to measure what users get, but never mix with runs that had it off)"
  end
  if number("/sys/devices/system/cpu/smt/active") == 1 then
    issues[#issues + 1] = "SMT is on (sibling threads add noise: echo off | sudo tee /sys/devices/system/cpu/smt/control)"
  end
  local swap = (read("/proc/swaps") or ""):match("\n(%S+)")
  if swap then issues[#issues + 1] = "swap is on (sudo swapoff -a)" end
  local load = tonumber((read("/proc/loadavg") or ""):match("^(%S+)"))
  if load and load > 0.5 then issues[#issues + 1] = ("load average is %.2f: something else is running (top)"):format(load) end
  local target = util.capture("systemctl is-active graphical.target 2>/dev/null")
  if target == "active" then
    issues[#issues + 1] = "the graphical session is running (leave it: sudo systemctl isolate multi-user.target)"
  end
  return issues
end

local function parse_args(args)
  local options = { names = {}, runs = 5 }
  local problems = {}
  for _, a in ipairs(args) do
    local key, value = a:match("^%-%-([%w-]+)=(.*)$")
    if a == "--list" then options.list = true
    elseif a == "--yes" then options.yes = true
    elseif a == "--strict" then options.strict = true
    elseif key == "runs" then
      options.runs = tonumber(value)
      if not options.runs or options.runs < 1 or options.runs % 1 ~= 0 then problems[#problems + 1] = "--runs needs a positive integer" end
    elseif key == "pin" then
      options.pin = value
      if not bench.valid_cpu_list(value) then problems[#problems + 1] = "--pin needs a CPU list such as 2,3 or 2-3" end
    elseif key == "out" then options.out = value
    elseif a:sub(1, 2) == "--" then problems[#problems + 1] = ("unknown option '%s'"):format(a)
    else options.names[#options.names + 1] = a end
  end
  return options, problems
end

local function select_benchmarks(options, all)
  if #options.names == 0 then
    return nil
  end
  local chosen = {}
  for _, name in ipairs(options.names) do
    if name == "all" then
      for _, b in ipairs(all) do chosen[#chosen + 1] = b end
    else
      local matched = false
      for _, b in ipairs(all) do
        if b.id == name or b.id:match("^" .. name:gsub("%p", "%%%0") .. "/") then
          chosen[#chosen + 1] = b
          matched = true
        end
      end
      if not matched then return nil, ("no benchmark or package named '%s' (see --list)"):format(name) end
    end
  end
  return chosen
end

local function menu(all)
  print("Benchmarks:")
  for i, b in ipairs(all) do print(("  %2d  %-28s %s"):format(i, b.id, b.description)) end
  while true do
    io.write("Run which? (numbers such as 1,3-4, a = all, q = quit) ")
    local answer = io.read("l")
    if not answer then return nil end
    local picked, problem = bench.parse_selection(answer, #all)
    if picked then
      local chosen = {}
      for _, i in ipairs(picked) do chosen[#chosen + 1] = all[i] end
      return chosen
    end
    if not problem then return nil end
    print(problem)
  end
end

return {
  description = "browse and run the benchmarks on a Linux host (--list, --runs=N, --pin=CPUS, --out=DIR)",
  run = function(ctx)
    local options, problems = parse_args(ctx.args)
    if #problems > 0 then return { ok = false, problems = problems } end
    local all = discover(ctx.root)

    if options.list then
      local lines = {}
      for _, b in ipairs(all) do lines[#lines + 1] = ("%-28s %s"):format(b.id, b.description) end
      return { ok = true, problems = {}, output = table.concat(lines, "\n"), data = all }
    end
    if util.is_windows() or util.capture("uname -s") ~= "Linux" then
      return { ok = false, problems = { "bench runs on Linux (Ubuntu server is the reference platform); see benchmarks/README.md for Windows and macOS" } }
    end

    local chosen, problem = select_benchmarks(options, all)
    if problem then return { ok = false, problems = { problem } } end
    if not chosen then
      if os.execute("test -t 0 -a -t 1") ~= true then
        return { ok = false, problems = { "name the benchmarks to run (or 'all'); --list shows them" } }
      end
      chosen = menu(all)
      if not chosen or #chosen == 0 then return { ok = true, problems = {}, output = "nothing was run" } end
    end
    if #chosen == 0 then return { ok = false, problems = { "no benchmark found" } } end

    local issues = noisy(ctx.root)
    if #issues > 0 then
      io.stderr:write("The host is not quiet:\n")
      for _, issue in ipairs(issues) do io.stderr:write("  - ", issue, "\n") end
      if options.strict then return { ok = false, problems = { "the host is not quiet (--strict)" } } end
      if not options.yes then
        if os.execute("test -t 0") ~= true then
          return { ok = false, problems = { "the host is not quiet; fix it, or pass --yes to measure anyway" } }
        end
        io.stderr:write("Continue anyway? [y/N] ")
        if not (io.read("l") or ""):match("^[yY]") then
          return { ok = true, problems = {}, output = "nothing was run (answer y, or pass --yes, to measure on a host that is not quiet)" }
        end
      end
    end

    local host = (util.capture("hostname"):gsub("[^%w%-_.]", "-"))
    local out = options.out or ("benchmarks/results/%s-%s"):format(host, util.capture("date -u +%Y%m%d-%H%M%S"))
    local absolute = out:sub(1, 1) == "/" and out or (ctx.root .. "/" .. out)
    util.mkdir(absolute)
    local function host_report(name)
      local text = util.capture(("cd %s && sh benchmarks/host-report.sh"):format(util.quote(ctx.root)))
      write(absolute .. "/" .. name, text .. "\n")
    end
    host_report("host-before.md")

    local outputs = {}
    local failures = {}
    for round = 1, options.runs do
      util.mkdir(("%s/run-%d"):format(absolute, round))
      for _, b in ipairs(chosen) do
        local pin = options.pin and ("taskset -c %s "):format(options.pin) or ""
        local command = ("cd %s && %s%s %s 2>&1"):format(util.quote(ctx.root), pin, util.quote(util.interpreter()), util.quote(b.path))
        io.stderr:write(("[run %d/%d] %s\n"):format(round, options.runs, b.id))
        local text, ok = util.capture(command)
        if not ok then failures[#failures + 1] = ("%s failed in run %d:\n%s"):format(b.id, round, text) end
        write(("%s/run-%d/%s.txt"):format(absolute, round, (b.id:gsub("/", "-"))), text .. "\n")
        outputs[b.id] = outputs[b.id] or {}
        outputs[b.id][#outputs[b.id] + 1] = text
      end
    end
    host_report("host-after.md")

    local summary = { "# Benchmark summary", "",
      ("- runs: %d%s"):format(options.runs, options.pin and (", pinned to CPUs " .. options.pin) or ""),
      "- host: [before](host-before.md), [after](host-after.md) (compare the noise lines)", "" }
    for _, b in ipairs(chosen) do
      summary[#summary + 1] = "## " .. b.id
      summary[#summary + 1] = ""
      summary[#summary + 1] = bench.table(bench.summarise(outputs[b.id]))
      summary[#summary + 1] = ""
    end
    write(absolute .. "/summary.md", table.concat(summary, "\n"))
    return { ok = #failures == 0, problems = failures, output = "results: " .. out .. "/summary.md", data = { out = out } }
  end,
}
