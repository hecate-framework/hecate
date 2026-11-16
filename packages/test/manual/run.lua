-- Manual check of hecate.test on a real terminal (used on Windows by hand; works anywhere).
--
--   lua packages/test/manual/run.lua [console|tap|junit|json] [--live|--no-live] [--color|--no-color]
--                                    [--width=N] [--jobs=N] [directory]
--
-- Runs the `*_test.lua` files under `directory` (default: the `demo` directory next to this script). The demo
-- holds passing, failing and erroring tests, a slow suite (to see the live line redraw), a suite with many
-- assertions and a long name, in a nested directory, so path handling is exercised too. The exit code is 0 when
-- every test passed: the demo has failures on purpose, so 1 is the expected status.
global <const> require, arg, io, os, ipairs, debug, tonumber, _VERSION, package

local here = (debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")):match("^(.*)/[^/]*$") or "."

-- The packages are not installed as rocks: put their sources, and the project-local rocks tree (luv and the native
-- modules, as `lua tools/run.lua build-native` installs them), on the search paths, as the test harness does.
do
  local root, version = here .. "/../../..", _VERSION:match("%d+%.%d+")
  for _, name in ipairs({ "core", "reactor", "net", "json", "log", "http", "router", "schema", "container",
    "config", "kernel", "openapi", "test" }) do
    local src = root .. "/packages/" .. name .. "/src"
    package.path = src .. "/?.lua;" .. src .. "/?/init.lua;" .. package.path
  end
  local base = root .. "/.hecate/rocks"
  package.path = base .. "/share/lua/" .. version .. "/?.lua;" .. base .. "/share/lua/" .. version
    .. "/?/init.lua;" .. package.path
  package.cpath = base .. "/lib/lua/" .. version .. "/?.so;" .. base .. "/lib/lua/" .. version .. "/?.dll;"
    .. package.cpath
end

local reactor = require("hecate.reactor")
local test = require("hecate.test")

local reporter_name, directory, options, jobs = "console", here .. "/demo", {}, nil
for _, argument in ipairs(arg) do
  if argument == "--live" then options.live = true
  elseif argument == "--no-live" then options.live = false
  elseif argument == "--color" then options.color = true
  elseif argument == "--no-color" then options.color = false
  elseif argument:find("^%-%-width=%d+$") then options.width = tonumber(argument:match("=(%d+)$"))
  elseif argument:find("^%-%-jobs=%d+$") then jobs = tonumber(argument:match("=(%d+)$"))
  elseif argument == "console" or argument == "tap" or argument == "junit" or argument == "json" then
    reporter_name = argument
  elseif argument:sub(1, 2) == "--" then
    io.stderr:write("unknown option " .. argument .. "\n")
    os.exit(2)
  else
    directory = argument
  end
end

local reporter
if reporter_name == "console" then reporter = test.ConsoleReporter(options)
elseif reporter_name == "tap" then reporter = test.TapReporter()
elseif reporter_name == "junit" then reporter = test.JUnitReporter()
else reporter = test.JsonLinesReporter() end

-- Discovery suspends, so it runs in a reactor; the runner starts a reactor of its own for each test.
local paths, cases, summary = {}, {}, nil
reactor.run(function()
  paths = test.discover(directory)
  if jobs then
    -- one worker process per file; the events reach the reporter live, in the order of the paths
    summary = test.run_parallel(paths, { jobs = jobs, reporter = reporter })
  else
    for _, path in ipairs(paths) do cases[#cases + 1] = test.load(path) end
  end
end)
if not summary then summary = test.Runner({ reporter = reporter }):run(cases) end
io.stdout:flush()
os.exit(summary.exit_code)
