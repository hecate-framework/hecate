local test = require("harness.test")
local app = require("hecate.cli.app")
local real = require("hecate.reactor")
local serve_command = require("hecate.cli.commands.serve")
local T = test.Case("CliServeCommandTest")

local runtime = { hecate_version = "0.1.0", lua_version = "5.5.1", platform = "linux-x86_64", project_dir = "/work/app", lua_interpreter = "/usr/bin/lua5.5" }

--- The real reactor with a fake process and fake signals, so that no program is started.
local function setup(files, behaviour)
  behaviour = behaviour or {}
  local calls = { spawned = {}, signals = nil, closed = false }
  local queue = behaviour.signals or {}
  local reactor = setmetatable({
    spawn = function(program, args, options)
      calls.spawned[#calls.spawned + 1] = { program = program, args = args, options = options }
      local child = {}
      function child:wait()
        while not self.status do real.sleep(0.001) end
        return self.status
      end
      function child:kill(signal)
        -- A process that already exited keeps its status.
        if not self.status and (signal == "sigterm" or signal == "sigint") then self.status = { code = 0, signal = 0 } end
      end
      if behaviour.exit_code then child.status = { code = behaviour.exit_code, signal = 0 } end
      return child
    end,
    watch_signals = function(...)
      calls.signals = { ... }
      return {
        wait = function()
          while #queue == 0 do real.sleep(0.001) end
          return table.remove(queue, 1)
        end,
        close = function() calls.closed = true end,
      }
    end,
    fs = { stat = function() return nil end, list = function() return {} end },
  }, { __index = real })
  return calls, {
    exists = function(path) return files[path] == true end,
    run = function(task) return real.run(task) end,
    reactor = reactor,
    interpreter = "lua",
    windows = behaviour.windows == true,
  }
end

local function run(args, dependencies, rt)
  local out, err = {}, {}
  local wrapped = setmetatable({ run = function(context) return serve_command.execute(context, dependencies) end }, { __index = serve_command })
  local code = app.run(args, {
    commands = { wrapped }, runtime = rt or runtime,
    write = function(text) out[#out + 1] = text end,
    write_error = function(text) err[#err + 1] = text end,
  })
  return code, table.concat(out, "\n"), table.concat(err, "\n")
end

local PROJECT = { ["/work/app/hecate.project.lua"] = true, ["/work/app/main.lua"] = true }

function T:test_the_environment_carries_the_module_paths_and_the_workers()
  local env = serve_command.environment("/work/app", "5.5", "4")
  self:assert_true(env.LUA_PATH:find("/work/app/src/?.lua", 1, true) ~= nil)
  self:assert_true(env.LUA_PATH:find("/work/app/lua_modules/share/lua/5.5/?.lua", 1, true) ~= nil)
  self:assert_true(env.LUA_PATH:sub(-2) == ";;" and env.LUA_PATH_5_5 == env.LUA_PATH)
  self:assert_true(env.LUA_CPATH:find("/work/app/lua_modules/lib/lua/5.5/?.so", 1, true) ~= nil)
  self:assert_equal("4", env.HECATE_SERVER__WORKERS)
  self:assert_nil(serve_command.environment("/work/app", "5.5").HECATE_SERVER__WORKERS)
end

function T:test_env_names_the_configuration_environment_and_is_left_out_when_not_given()
  self:assert_equal("development", serve_command.environment("/work/app", "5.5", nil, "development").HECATE_ENV)
  self:assert_nil(serve_command.environment("/work/app", "5.5").HECATE_ENV)
  for _, good in ipairs({ "development", "staging", "ci_2", "pre-prod" }) do self:assert_true(serve_command.valid_environment(good), good) end
  for _, bad in ipairs({ "", "a/b", "../x", "a b", "dev;rm" }) do self:assert_false(serve_command.valid_environment(bad), bad) end
end

function T:test_serve_passes_env_to_the_child_and_refuses_a_bad_name()
  local calls, dependencies = setup(PROJECT, { exit_code = 0 })
  local code = run({ "serve", "--env=development" }, dependencies)
  self:assert_equal(0, code)
  self:assert_equal("development", calls.spawned[1].options.env.HECATE_ENV)
  local _, bad = setup(PROJECT, { exit_code = 0 })
  local code2, _, err = run({ "serve", "--env=a/b" }, bad)
  self:assert_equal(2, code2)
  self:assert_true(err:find("--env", 1, true) ~= nil, err)
end

function T:test_workers_is_a_whole_number_or_auto()
  for _, good in ipairs({ "1", "8", "auto" }) do self:assert_true(serve_command.valid_workers(good), good) end
  for _, bad in ipairs({ "0", "-1", "1.5", "two", "", "AUTO" }) do self:assert_false(serve_command.valid_workers(bad), bad) end
end

function T:test_it_runs_main_lua_in_the_project_with_its_paths_and_returns_the_exit_code()
  local calls, dependencies = setup(PROJECT, { exit_code = 7 })
  local code, _, err = run({ "serve", "--workers=3" }, dependencies)
  self:assert_equal(7, code)
  self:assert_equal(1, #calls.spawned)
  local spawned = calls.spawned[1]
  self:assert_equal("lua", spawned.program)
  self:assert_equal("main.lua", spawned.args[1])
  self:assert_equal("/work/app", spawned.options.cwd)
  self:assert_equal("3", spawned.options.env.HECATE_SERVER__WORKERS)
  self:assert_true(err:find("starting main.lua", 1, true) ~= nil, err)
  self:assert_true(calls.closed)
  self:assert_equal("sigint,sigterm,sighup", table.concat(calls.signals, ","))
  -- Ctrl+C in the terminal reaches the whole group: the child is its own, so that only the supervisor hears it and
  -- forwards it once (ADR 0023).
  self:assert_true(spawned.options.own_group == true, "the child must be spawned with own_group = true")
end

function T:test_a_signal_stops_the_application_gracefully()
  local calls, dependencies = setup(PROJECT, { signals = { "sigterm" } })
  local code = run({ "serve" }, dependencies)
  self:assert_equal(0, code)
  self:assert_true(calls.closed)
end

function T:test_there_is_no_sighup_on_windows()
  local calls, dependencies = setup(PROJECT, { exit_code = 0, windows = true })
  run({ "serve" }, dependencies)
  self:assert_equal("sigint,sigterm", table.concat(calls.signals, ","))
end

function T:test_on_windows_the_console_signal_is_left_to_the_child_which_is_then_given_the_grace_period()
  local calls, dependencies = setup(PROJECT, { signals = { "sigint" }, windows = true })
  local kills = {}
  local spawn = dependencies.reactor.spawn
  dependencies.reactor.spawn = function(...)
    local child = spawn(...)
    local kill = child.kill
    child.kill = function(self, signal) kills[#kills + 1] = signal; kill(self, signal) end
    return child
  end
  local code = run({ "serve" }, dependencies)
  self:assert_equal(1, #calls.spawned)
  self:assert_equal(137, code) -- killed after the grace period (the fake child ignores the console)
  self:assert_equal("sigkill", table.concat(kills, ","))
end

function T:test_watch_gives_the_supervisor_a_watcher_and_a_plain_run_does_not()
  local plain_calls, plain = setup(PROJECT, { exit_code = 0 })
  run({ "serve" }, plain)
  self:assert_equal(1, #plain_calls.spawned)
  -- With --watch a child that exits by itself is not the end: the run waits for a change or a signal.
  local calls, dependencies = setup(PROJECT, { exit_code = 5, signals = { "sigterm" } })
  local code = run({ "serve", "--watch" }, dependencies)
  self:assert_equal(5, code)
  self:assert_equal(1, #calls.spawned)
end

function T:test_bad_arguments_and_missing_files_say_what_to_do()
  local _, dependencies = setup(PROJECT, { exit_code = 0 })
  local code, _, err = run({ "serve", "--workers", "0" }, dependencies)
  self:assert_equal(2, code)
  self:assert_true(err:find("--workers takes a whole number", 1, true) ~= nil, err)
  local extra, _, err2 = run({ "serve", "main.lua" }, dependencies)
  self:assert_equal(2, extra)
  self:assert_true(err2:find("takes no argument", 1, true) ~= nil, err2)
  local _, no_manifest = setup({ ["/work/app/main.lua"] = true })
  local failed, _, err3 = run({ "serve" }, no_manifest)
  self:assert_equal(1, failed)
  self:assert_true(err3:find("hecate new", 1, true) ~= nil, err3)
  local calls, no_main = setup({ ["/work/app/hecate.project.lua"] = true })
  local failed_main, _, err4 = run({ "serve" }, no_main)
  self:assert_equal(1, failed_main)
  self:assert_true(err4:find("main.lua not found", 1, true) ~= nil, err4)
  self:assert_equal(0, #calls.spawned)
end

function T:test_the_executable_starts_the_project_in_interpreter_mode()
  local calls, dependencies = setup(PROJECT, { exit_code = 0 })
  dependencies.interpreter = "/opt/hecate/hecate"
  dependencies.interpreter_arguments = { "--lua" }
  run({ "serve" }, dependencies)
  self:assert_equal("/opt/hecate/hecate", calls.spawned[1].program)
  self:assert_equal("--lua,main.lua", table.concat(calls.spawned[1].args, ","))
end

return T
