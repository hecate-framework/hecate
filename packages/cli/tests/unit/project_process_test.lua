local test = require("harness.test")
local core = require("hecate.core")
local project_process = require("hecate.cli.internal.project_process")
local T = test.Case("CliProjectProcessTest")

local context = { runtime = { lua_version = "5.5.1", project_dir = "/work/app/" } }

local function dependencies(result, calls)
  return {
    run_process = function(program, args, options)
      calls[#calls + 1] = { program = program, args = args, options = options }
      return result
    end,
    interpreter = "/opt/hecate",
    interpreter_arguments = { "--lua" },
  }
end

function T:test_the_program_runs_in_the_interpreter_of_the_project_with_its_module_path()
  local calls = {}
  local result = project_process.run(context, dependencies({ code = 0, stdout = "out", stderr = "" }, calls), "print(1)", { HECATE_CLI_X = "y" }, "the test")
  self:assert_equal("out", result.stdout)
  local call = calls[1]
  self:assert_equal("/opt/hecate", call.program)
  self:assert_equal("--lua,-e,print(1)", table.concat(call.args, ","))
  self:assert_equal("/work/app", call.options.cwd)
  self:assert_equal("y", call.options.env.HECATE_CLI_X)
  self:assert_true(call.options.env.LUA_PATH:find("/work/app/lua_modules/share/lua/5.5/?.lua", 1, true) ~= nil)
end

function T:test_a_failure_names_what_was_done_and_what_the_program_wrote()
  local err = self:assert_error(function()
    project_process.run(context, dependencies({ code = 1, stdout = "", stderr = "boom\n" }, {}), "x", nil, "the build")
  end)
  self:assert_true(core.is_instance_of(err, core.ConfigurationError), tostring(err))
  local message = (err --[[@as hecate.core.Error]]).message
  self:assert_true(message:find("the build failed:\nboom", 1, true) ~= nil, message)
  local silent = self:assert_error(function()
    project_process.run(context, dependencies({ code = 4, stdout = "", stderr = "" }, {}), "x", nil, "the build")
  end)
  self:assert_true(tostring((silent --[[@as hecate.core.Error]]).message):find("the process exited with 4", 1, true) ~= nil)
end

function T:test_a_rock_of_the_project_that_is_missing_gets_the_advice_without_the_list_of_searched_files()
  local stderr = "lua: (command line):1: module 'hecate.openapi' not found:\n\tno field package.preload['hecate.openapi']\n\tno file '/x/hecate/openapi.lua'\n"
  local err = self:assert_error(function()
    project_process.run(context, dependencies({ code = 1, stdout = "", stderr = stderr }, {}), "x", nil, "the lint")
  end)
  local message = (err --[[@as hecate.core.Error]]).message
  self:assert_true(message:find("module 'hecate.openapi' not found:", 1, true) ~= nil, message)
  self:assert_true(message:find("run `hecate install`", 1, true) ~= nil, message)
  self:assert_nil(message:find("/x/hecate/openapi.lua", 1, true))
  -- A module of another origin keeps its whole text.
  local other = self:assert_error(function()
    project_process.run(context, dependencies({ code = 1, stdout = "", stderr = "module 'lfs' not found:\n\tno file 'a'\n" }, {}), "x", nil, "x")
  end)
  self:assert_true(tostring((other --[[@as hecate.core.Error]]).message):find("no file 'a'", 1, true) ~= nil)
end

return T
