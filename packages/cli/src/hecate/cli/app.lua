-- The `hecate` command dispatcher: selects a command, prints help, maps failures to exit codes.
global <const> require, ipairs, pcall, table, string, tostring, io

local core = require("hecate.core")
local parser = require("hecate.cli.parser")

--- Exit codes of the `hecate` command.
---@class hecate.cli.exit_codes
local EXIT = { ok = 0, failure = 1, usage = 2 }

---@class hecate.cli.Context
---@field arguments hecate.cli.ParsedArguments
---@field json boolean  machine-readable output was requested
---@field runtime hecate.cli.Runtime
---@field commands hecate.cli.Command[]  every command of the application
---@field print fun(text: string)  writes a line to standard output
---@field print_error fun(text: string)  writes a line to standard error
---@field emit fun(value: table, text: string)  prints `value` as JSON under `--json`, `text` otherwise

---@class hecate.cli.Runtime
---@field hecate_version string
---@field lua_version string
---@field luarocks_version? string
---@field libuv_version? string
---@field platform string  for example "linux-x86_64"
---@field project_dir? string  absolute path of the current directory, with forward slashes (commands that run programs elsewhere need absolute paths)

---@class hecate.cli.AppOptions
---@field commands hecate.cli.Command[]
---@field runtime hecate.cli.Runtime
---@field write? fun(text: string)  standard output (default: io.stdout)
---@field write_error? fun(text: string)  standard error (default: io.stderr)
---@field encode_json? fun(value: table): string  default: `hecate.json.encode`, required on first use

--- The application: one instance per process.
---@class hecate.cli.app
local M = { exit_codes = EXIT }

local function message_of(err)
  if core.is_instance_of(err, core.Error) then return (err --[[@as hecate.core.Error]]).message end
  return tostring(err)
end

local function help_for_command(command)
  local lines = { "Usage: hecate " .. command.name .. (command.usage and (" " .. command.usage) or "") .. " [--json]", "", command.summary }
  if command.options and #command.options > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Options:"
    for _, spec in ipairs(command.options) do
      lines[#lines + 1] = string.format("  --%-16s %s", spec.name .. (spec.takes_value and "=<value>" or ""), spec.summary)
    end
  end
  return table.concat(lines, "\n")
end

local function general_help(commands)
  local lines = { "Usage: hecate <command> [options]", "", "Commands:" }
  local sorted = {}
  for _, command in ipairs(commands) do
    if not command.hidden then sorted[#sorted + 1] = command end
  end
  table.sort(sorted, function(a, b) return a.name < b.name end)
  for _, command in ipairs(sorted) do lines[#lines + 1] = string.format("  %-20s %s", command.name, command.summary) end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Every command accepts --help and --json. Run 'hecate <command> --help' for its options."
  return table.concat(lines, "\n")
end

--- Runs the command named by `args` and returns the process exit code: 0 on success, 1 when the command failed,
--- 2 for a usage error (unknown command or option).
---@param args string[]  the arguments after the program name
---@param options hecate.cli.AppOptions
---@return integer exit_code
function M.run(args, options)
  local function default_write(stream) return function(text) stream:write(text, "\n") end end
  local write = options.write or default_write(io.stdout)
  local write_error = options.write_error or default_write(io.stderr)

  local ok, parsed = pcall(parser.parse, args, options.commands)
  if not ok then
    local err = parsed
    local message = message_of(err)
    write_error("hecate: " .. message)
    write_error("Run 'hecate --help' for the list of commands.")
    return EXIT.usage
  end
  if parsed.help or not parsed.command then
    write(parsed.command and help_for_command(parsed.command) or general_help(options.commands))
    return parsed.help and EXIT.ok or EXIT.usage
  end

  ---@type hecate.cli.Context
  local context = {
    arguments = parsed,
    json = parsed.json,
    runtime = options.runtime,
    commands = options.commands,
    print = write,
    print_error = write_error,
    emit = function(value, text)
      if parsed.json then
        local encode = options.encode_json or require("hecate.json").encode
        write(encode(value))
      else
        write(text)
      end
    end,
  }
  local ran, result = pcall(parsed.command.run, context)
  if not ran then
    local message = message_of(result)
    write_error("hecate " .. parsed.command.name .. ": " .. message)
    return EXIT.failure
  end
  return result or EXIT.ok
end

return M
