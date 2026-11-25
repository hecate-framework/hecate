-- The `hecate` command dispatcher: selects a command, prints help, maps failures to exit codes.
global <const> require, ipairs, pairs, pcall, table, string, tostring, io, type

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
---@field emit fun(value: table, text: string)  prints `value` as JSON under `--json` (with `ok = true` added when the value has no `ok`), `text` otherwise

---@class hecate.cli.Runtime
---@field hecate_version string
---@field lua_version string
---@field luarocks_version? string
---@field libuv_version? string
---@field platform string  for example "linux-x86_64"
---@field lua_interpreter? string  the interpreter that runs this process (`arg[-1]`), which `serve`, `run` and `contract export` start for the project
---@field luarocks_program? string  the program that runs LuaRocks (the self-contained executable: itself); none for the `luarocks` of the path
---@field luarocks_arguments? string[]  arguments that make that program run LuaRocks (`--luarocks`)
---@field lua_interpreter_arguments? string[]  arguments that put that program in interpreter mode (the self-contained executable: `--lua`); none for a plain `lua`
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
  lines[#lines + 1] = "Every command accepts --help and --json. Run 'hecate <command> --help' for its options; 'hecate --version' prints the version."
  return table.concat(lines, "\n")
end

--- The subcommands of a group (`contract` has `contract export`, `contract lint`, ...): the commands whose name starts with `word` and a space.
---@param commands hecate.cli.Command[]
---@param word string
---@return hecate.cli.Command[] members  sorted by name, hidden ones left out
local function group_of(commands, word)
  local members = {}
  for _, command in ipairs(commands) do
    if not command.hidden and command.name:sub(1, #word + 1) == word .. " " then members[#members + 1] = command end
  end
  table.sort(members, function(a, b) return a.name < b.name end)
  return members
end

local function group_help(word, members)
  local lines = { "Usage: hecate " .. word .. " <command> [options]", "", "Commands:" }
  for _, command in ipairs(members) do lines[#lines + 1] = string.format("  %-20s %s", command.name, command.summary) end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Run 'hecate " .. word .. " <command> --help' for the options of a command."
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
  local function encode(value) return (options.encode_json or require("hecate.json").encode)(value) end

  -- `hecate help` and `hecate help <command>` are `--help` (unless a command is named `help`).
  if args[1] == "help" then
    local named = false
    for _, candidate in ipairs(options.commands) do if candidate.name == "help" then named = true end end
    if not named then
      local rewritten = {}
      for index = 2, #args do rewritten[#rewritten + 1] = args[index] end
      rewritten[#rewritten + 1] = "--help"
      args = rewritten
    end
  end
  local wants_json, wants_help = false, false
  for _, argument in ipairs(args) do
    if argument == "--" then break end
    if argument == "--json" then wants_json = true end
    if argument == "--help" or argument == "-h" then wants_help = true end
  end

  local ok, parsed = pcall(parser.parse, args, options.commands)
  if not ok then
    local err = parsed
    local message = message_of(err)
    local context = type(err) == "table" and err.context or {}
    -- A word that starts a group of commands (`hecate contract`) shows the group, not an error.
    local members = context.command and group_of(options.commands, context.command) or {}
    if #members > 0 and not wants_json then
      write(group_help(context.command, members))
      return wants_help and EXIT.ok or EXIT.usage
    end
    local name = context.command_name
    local hint = name and ("Run 'hecate " .. name .. " --help' for its options.") or "Run 'hecate --help' for the list of commands."
    if wants_json then
      write(encode({ ok = false, usage = true, error = { message = message, code = type(err) == "table" and err.code or nil, hint = hint } }))
    else
      write_error("hecate" .. (name and (" " .. name) or "") .. ": " .. message)
      write_error(hint)
    end
    return EXIT.usage
  end
  -- `hecate --version` is `hecate version`.
  if parsed.version and not parsed.command then
    for _, candidate in ipairs(options.commands) do
      if candidate.name == "version" then parsed.command = candidate break end
    end
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
        if value.ok == nil then
          local copy = { ok = true }
          for key, field in pairs(value) do copy[key] = field end
          value = copy
        end
        write(encode(value))
      else
        write(text)
      end
    end,
  }
  local ran, result = pcall(parsed.command.run, context)
  if not ran then
    local message = message_of(result)
    if parsed.json then
      -- Under --json the answer stays one JSON document on standard output, success or not.
      write(encode({ ok = false, error = { message = message, code = core.is_instance_of(result, core.Error) and (result --[[@as hecate.core.Error]]).code or nil } }))
    else
      write_error("hecate " .. parsed.command.name .. ": " .. message)
    end
    return EXIT.failure
  end
  return result or EXIT.ok
end

return M
