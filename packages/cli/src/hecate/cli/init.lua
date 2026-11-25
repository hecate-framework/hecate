-- hecate.cli: the `hecate` command (cli-and-packaging.md). Status: in progress; the commands of `hecate.cli.commands` below are
-- implemented, the others of the specification (toolchains, migrations, workflows) are still to do (see README.md).
global <const> require

local app = require("hecate.cli.app")

---@class hecate.cli
---@field run fun(args: string[], options: hecate.cli.AppOptions): integer  runs one command line and returns the exit code
---@field parse fun(args: string[], commands: hecate.cli.Command[]): hecate.cli.ParsedArguments
---@field commands hecate.cli.Command[]  the commands implemented so far
---@field exit_codes hecate.cli.exit_codes
---@field completion hecate.cli.completion  candidates and scripts of shell completion
local cli = {
  run = app.run,
  parse = require("hecate.cli.parser").parse,
  commands = {
    require("hecate.cli.commands.version"),
    require("hecate.cli.commands.add"),
    require("hecate.cli.commands.contract").commands[1],
    require("hecate.cli.commands.contract").commands[2],
    require("hecate.cli.commands.contract").commands[3],
    require("hecate.cli.commands.doc"),
    require("hecate.cli.commands.doctor"),
    require("hecate.cli.commands.generate_meta"),
    require("hecate.cli.commands.generate_systemd"),
    require("hecate.cli.commands.generate_workflow"),
    require("hecate.cli.commands.init"),
    require("hecate.cli.commands.install"),
    require("hecate.cli.commands.new"),
    require("hecate.cli.commands.outdated"),
    require("hecate.cli.commands.package"),
    require("hecate.cli.commands.remove"),
    require("hecate.cli.commands.run"),
    require("hecate.cli.commands.serve"),
    require("hecate.cli.commands.tests"),
    require("hecate.cli.commands.update"),
    require("hecate.cli.commands.completion")[1],
    require("hecate.cli.commands.completion")[2],
  },
  exit_codes = app.exit_codes,
  completion = require("hecate.cli.completion"),
}

return cli
