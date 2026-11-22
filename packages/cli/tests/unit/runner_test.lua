local test = require("harness.test")
local reactor = require("hecate.reactor")
local runner = require("hecate.cli.runner")
local T = test.Case("CliRunnerTest")

local LUA = "lua"

function T:test_runs_a_program_with_an_environment_and_captures_its_output()
  local result = reactor.run(function()
    return runner.run(LUA, { "-e", 'io.write(os.getenv("HECATE_CLI_RUNNER") or "unset") io.stderr:write("warn")' }, { env = { HECATE_CLI_RUNNER = "set" } })
  end)
  self:assert_equal(0, result.code)
  self:assert_equal("set", result.stdout)
  self:assert_equal("warn", result.stderr)
end

function T:test_reports_the_exit_status()
  local result = reactor.run(function() return runner.run(LUA, { "-e", "os.exit(3)" }, {}) end)
  self:assert_equal(3, result.code)
end

return T
