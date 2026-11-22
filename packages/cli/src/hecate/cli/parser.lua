-- Command-line parsing of the `hecate` command: global flags, command selection, options.
global <const> require, ipairs, error

local core = require("hecate.core")

---@class hecate.cli.OptionSpec
---@field name string  long name without the dashes, for example "watch"
---@field takes_value? boolean  the value follows `=` or is the next argument
---@field repeatable? boolean  the option may be given several times (values are collected in a list)
---@field summary string

---@class hecate.cli.Command
---@field name string  one or two words, for example "version" or "toolchain install"
---@field summary string  one line, shown by `hecate --help`
---@field hidden? boolean  not listed by `--help` nor completed (internal commands)
---@field usage? string  the arguments after the name, for example "<name> [--template api|minimal|crud]"
---@field options? hecate.cli.OptionSpec[]
---@field run fun(context: hecate.cli.Context): integer?  returns the exit code (default 0)

---@class hecate.cli.ParsedArguments
---@field command? hecate.cli.Command  nil when no command was named
---@field help boolean  `--help` or `-h` was given
---@field json boolean  `--json` was given
---@field options table<string, string|boolean|string[]>  options by long name
---@field positionals string[]

--- Parsing of the arguments after the program name.
---@class hecate.cli.parser
local M = {}

local function fail(message, context) error(core.ArgumentError(message, { context = context }), 0) end

--- Finds the command named by the leading words of `args`: a two-word name wins over a one-word name.
---@param args string[]
---@param commands hecate.cli.Command[]
---@return hecate.cli.Command? command
---@return integer consumed  number of leading words that form the name
function M.find_command(args, commands)
  local best, words = nil, 0
  for _, command in ipairs(commands) do
    local first, second = command.name:match("^(%S+)%s+(%S+)$")
    if second then
      if args[1] == first and args[2] == second and words < 2 then best, words = command, 2 end
    elseif args[1] == command.name and words < 1 then
      best, words = command, 1
    end
  end
  return best, words
end

--- Parses `args`. Global flags (`--help`, `-h`, `--json`) are accepted anywhere before `--`; the options of the
--- selected command are checked against its declaration.
---
--- Raises `hecate.core.ArgumentError` for an unknown command or option, or a missing value.
---@param args string[]
---@param commands hecate.cli.Command[]
---@return hecate.cli.ParsedArguments
function M.parse(args, commands)
  local parsed = { help = false, json = false, options = {}, positionals = {} }
  local rest = {}
  for _, argument in ipairs(args) do rest[#rest + 1] = argument end
  -- The command name is the leading words that are not flags; the global flags may precede it.
  local leading, cut = {}, 0
  for position, argument in ipairs(rest) do
    if argument == "--json" or argument == "--help" or argument == "-h" then
      if #leading > 0 then break end
    elseif argument:sub(1, 1) == "-" then
      break
    else
      leading[#leading + 1] = argument
      cut = position
    end
  end
  local command, consumed = M.find_command(leading, commands)
  if #leading > 0 and not command then
    fail("unknown command '" .. leading[1] .. "'", { command = leading[1] })
  end
  parsed.command = command
  -- Drop the words of the name; flags before it stay in place and are parsed with the rest.
  local remaining = {}
  local dropped = 0
  for position, argument in ipairs(rest) do
    if dropped < consumed and position <= cut and argument:sub(1, 1) ~= "-" then
      dropped = dropped + 1
    else
      remaining[#remaining + 1] = argument
    end
  end
  rest, consumed = remaining, 0
  local specs = {}
  for _, spec in ipairs(command and command.options or {}) do specs[spec.name] = spec end

  local index, only_positionals = consumed + 1, false
  while index <= #rest do
    local argument = rest[index]
    index = index + 1
    if only_positionals or argument:sub(1, 1) ~= "-" or argument == "-" then
      parsed.positionals[#parsed.positionals + 1] = argument
    elseif argument == "--" then
      only_positionals = true
    elseif argument == "--help" or argument == "-h" then
      parsed.help = true
    elseif argument == "--json" then
      parsed.json = true
    else
      local name, value = argument:match("^%-%-([%w%-]+)=(.*)$")
      name = name or argument:match("^%-%-([%w%-]+)$")
      local spec = name and specs[name]
      if not spec then fail("unknown option " .. argument, { option = argument }) end
      if spec.takes_value then
        if value == nil then
          value = rest[index]
          index = index + 1
        end
        if value == nil or value == "" then fail("option --" .. name .. " needs a value", { option = name }) end
        if spec.repeatable then
          local list = parsed.options[name]
          if list == nil then list = {}; parsed.options[name] = list end
          list[#list + 1] = value
        else
          if parsed.options[name] ~= nil then fail("option --" .. name .. " given twice", { option = name }) end
          parsed.options[name] = value
        end
      else
        if value ~= nil then fail("option --" .. name .. " takes no value", { option = name }) end
        parsed.options[name] = true
      end
    end
  end
  return parsed
end

return M
