-- Command-line selection: turns the arguments of a test command into runner options and paths.
global <const> require, type, ipairs, error, table

local core = require("hecate.core")

---@class hecate.test.Selection
---@field options hecate.test.RunnerOptions  `filter`, `cases`, `tags`, `exclude_tags` as given
---@field paths string[]  files or directories to discover tests in (empty: the default directory)

--- Parsing of the command-line arguments of a test run.
---@class hecate.test.selection
local M = {}

local function fail(message) error(core.ArgumentError("test: " .. message), 3) end

--- Parses the arguments of a test command.
---
--- Options (the value follows `=` or is the next argument): `--filter` (Lua pattern on the full test
--- name, at most once), `--case` (a case name, repeatable), `--tag` and `--exclude-tag` (repeatable).
--- Any other argument is a path; `--` ends the options.
---
--- Raises `hecate.core.ArgumentError` for an unknown option, a missing or empty value, or a repeated `--filter`.
---@param args string[]
---@return hecate.test.Selection selection
function M.parse(args)
  local options, paths = {}, {}
  local lists = { ["--case"] = "cases", ["--tag"] = "tags", ["--exclude-tag"] = "exclude_tags" }
  local index, count, only_paths = 1, #args, false
  while index <= count do
    local argument = args[index]
    index = index + 1
    if only_paths or argument:sub(1, 2) ~= "--" then
      paths[#paths + 1] = argument
    elseif argument == "--" then
      only_paths = true
    else
      local name, value = argument:match("^(%-%-[%w%-]+)=(.*)$")
      name = name or argument
      if name ~= "--filter" and not lists[name] then fail("unknown option " .. name) end
      if value == nil then
        value = args[index]
        index = index + 1
      end
      if value == nil or value == "" then fail("option " .. name .. " needs a value") end
      if name == "--filter" then
        if options.filter ~= nil then fail("option --filter given twice") end
        options.filter = value
      else
        local key = lists[name]
        options[key] = options[key] or {}
        options[key][#options[key] + 1] = value
      end
    end
  end
  return { options = options, paths = paths }
end

return M
