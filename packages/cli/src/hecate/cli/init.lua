-- hecate.cli: the `hecate` command (cli-and-packaging.md). Status: the dispatcher, the argument parser, `--help`,
-- `--json`, exit codes and `version` are implemented; every other command is still to do (see README.md).
global <const> require

local app = require("hecate.cli.app")

---@class hecate.cli
---@field run fun(args: string[], options: hecate.cli.AppOptions): integer  runs one command line and returns the exit code
---@field parse fun(args: string[], commands: hecate.cli.Command[]): hecate.cli.ParsedArguments
---@field commands hecate.cli.Command[]  the commands implemented so far
---@field exit_codes hecate.cli.exit_codes
local cli = {
  run = app.run,
  parse = require("hecate.cli.parser").parse,
  commands = { require("hecate.cli.commands.version") },
  exit_codes = app.exit_codes,
}

return cli
