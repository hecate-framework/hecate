local test = require("harness.test")
local app = require("hecate.cli.app")
local real = require("hecate.reactor")
local run_command = require("hecate.cli.commands.run")
local T = test.Case("CliRunCommandTest")

local runtime = { hecate_version = "0.1.0", lua_version = "5.5.1", platform = "linux-x86_64", project_dir = "/work/app", lua_interpreter = "/usr/bin/lua5.5" }

local MANIFEST = 'return { name = "app", scripts = { seed = "scripts/seed.lua", escape = "../outside.lua", absolute = "/etc/x.lua", gone = "scripts/gone.lua" } }'

--- The real reactor with a fake process (it exits with `exit_code` at once) and fake signals.
local function setup(files, exit_code)
  local calls = { spawned = {}, closed = false }
  local reactor = setmetatable({
    spawn = function(program, args, options)
      calls.spawned[#calls.spawned + 1] = { program = program, args = args, options = options }
      local child = { status = { code = exit_code or 0, signal = 0 } }
      function child:wait() return self.status end
      function child:kill() end
      return child
    end,
    watch_signals = function(...)
      calls.signals = { ... }
      return { wait = function() while true do real.sleep(1) end end, close = function() calls.closed = true end }
    end,
  }, { __index = real })
  return calls, {
    read = function(path) return files[path] end,
    exists = function(path) return files[path] ~= nil end,
    run = function(task) return real.run(task) end,
    reactor = reactor,
    interpreter = "lua",
    windows = false,
  }
end

local function run(args, dependencies, rt)
  local out, err = {}, {}
  local wrapped = setmetatable({ run = function(context) return run_command.execute(context, dependencies) end }, { __index = run_command })
  local code = app.run(args, {
    commands = { wrapped }, runtime = rt or runtime,
    write = function(text) out[#out + 1] = text end,
    write_error = function(text) err[#err + 1] = text end,
  })
  return code, table.concat(out, "\n"), table.concat(err, "\n")
end

local PROJECT = {
  ["/work/app/hecate.project.lua"] = MANIFEST,
  ["/work/app/scripts/seed.lua"] = "-- seed",
  ["/work/app/tools/once.lua"] = "-- once",
}

function T:test_a_script_of_the_manifest_runs_in_the_project_with_its_arguments_and_exit_code()
  local calls, dependencies = setup(PROJECT, 3)
  local code = run({ "run", "seed", "--", "--count", "5" }, dependencies)
  self:assert_equal(3, code)
  self:assert_equal(1, #calls.spawned)
  local spawned = calls.spawned[1]
  self:assert_equal("lua", spawned.program)
  self:assert_equal("scripts/seed.lua,--count,5", table.concat(spawned.args, ","))
  self:assert_equal("/work/app", spawned.options.cwd)
  self:assert_true(spawned.options.env.LUA_PATH:find("/work/app/lua_modules/share/lua/5.5/?.lua", 1, true) ~= nil)
  self:assert_true(calls.closed)
  self:assert_equal("sigint,sigterm", table.concat(calls.signals, ","))
end

function T:test_a_lua_file_of_the_project_runs_by_its_path()
  local calls, dependencies = setup(PROJECT)
  self:assert_equal(0, (run({ "run", "tools/once.lua" }, dependencies)))
  self:assert_equal("tools/once.lua", calls.spawned[1].args[1])
end

function T:test_what_cannot_run_says_why()
  local function fails(args, fragment, files)
    local calls, dependencies = setup(files or PROJECT)
    local code, _, err = run(args, dependencies)
    self:assert_equal(1, code)
    self:assert_true(err:find(fragment, 1, true) ~= nil, err)
    self:assert_equal(0, #calls.spawned)
  end
  fails({ "run", "unknown" }, "'unknown' is not a script of hecate.project.lua (scripts: absolute, escape, gone, seed)")
  fails({ "run", "escape" }, "leaves the project")
  fails({ "run", "absolute" }, "leaves the project")
  fails({ "run", "gone" }, "scripts/gone.lua not found")
  fails({ "run", "seed" }, "hecate new", { ["/work/app/scripts/seed.lua"] = "-- seed" })
  fails({ "run", "x" }, "declares no `scripts`", { ["/work/app/hecate.project.lua"] = 'return { name = "app" }' })
end

function T:test_no_script_is_a_usage_error_that_shows_how_arguments_are_given()
  local _, dependencies = setup(PROJECT)
  local code, _, err = run({ "run" }, dependencies)
  self:assert_equal(2, code)
  self:assert_true(err:find("hecate run seed -- --count 5", 1, true) ~= nil, err)
end

function T:test_a_script_stays_inside_the_project()
  self:assert_true(run_command.inside_project("scripts/seed.lua"))
  self:assert_true(run_command.inside_project("a/b/../c.lua") == false)
  for _, bad in ipairs({ "", "/etc/x", "\\x", "C:/x", "../x", "a/../../x" }) do self:assert_false(run_command.inside_project(bad), bad) end
end

function T:test_the_executable_runs_a_script_in_interpreter_mode()
  local calls, dependencies = setup(PROJECT)
  dependencies.interpreter_arguments = { "--lua" }
  run({ "run", "seed", "--", "x" }, dependencies)
  self:assert_equal("--lua,scripts/seed.lua,x", table.concat(calls.spawned[1].args, ","))
end

return T
