-- `hecate contract lint <file>` and `hecate contract diff <old> <new>`: the lint and the breaking-change detection of
-- `hecate.openapi` over OpenAPI documents in JSON files. (`contract export` needs the application of the project and
-- comes with `serve`.)
global <const> require, error, ipairs, io, pcall, string, table, tostring, type

local core = require("hecate.core")

---@class hecate.cli.ContractDependencies
---@field read fun(path: string): string?  the text of a file, nil when it does not exist
---@field decode fun(text: string): any  JSON text to a value; raises on invalid JSON
---@field lint fun(document: table): hecate.openapi.Finding[]
---@field diff fun(old: table, new: table): hecate.openapi.Change[]

--- The commands of the contract.
---@class hecate.cli.commands.contract
local M = {}

local function load_document(dependencies, path)
  local text = dependencies.read(path)
  if text == nil then
    error(core.ConfigurationError({ message = path .. ": no such file (export the contract first, or pass the path of an OpenAPI JSON document)", context = { path = path } }), 0)
  end
  local ok, value = pcall(dependencies.decode, text)
  if not ok then
    error(core.ConfigurationError({ message = path .. ": not valid JSON: " .. tostring((value --[[@as hecate.core.Error]]).message or value), context = { path = path } }), 0)
  end
  if type(value) ~= "table" then
    error(core.ConfigurationError({ message = path .. ": an OpenAPI document is a JSON object", context = { path = path } }), 0)
  end
  return value
end

--- `hecate contract lint <file>`: runs `openapi.lint`; exit 1 when a finding is an error (warnings do not fail).
---@param context hecate.cli.Context
---@param dependencies hecate.cli.ContractDependencies
---@return integer exit_code
function M.lint(context, dependencies)
  local positionals = context.arguments.positionals
  if #positionals ~= 1 then
    context.print_error("hecate contract lint: name the OpenAPI JSON file, for example `hecate contract lint openapi.json`")
    return 2
  end
  local findings = dependencies.lint(load_document(dependencies, positionals[1]))
  local errors, warnings, lines = 0, 0, {}
  for _, finding in ipairs(findings) do
    if finding.severity == "error" then errors = errors + 1 else warnings = warnings + 1 end
    lines[#lines + 1] = string.format("%-7s %-28s %s: %s", finding.severity, finding.rule, finding.path, finding.message)
  end
  lines[#lines + 1] = string.format("%d error(s), %d warning(s)", errors, warnings)
  context.emit({ ok = errors == 0, errors = errors, warnings = warnings, findings = findings }, table.concat(lines, "\n"))
  return errors > 0 and 1 or 0
end

--- `hecate contract diff <old> <new>`: runs `openapi.diff`; exit 1 when a change is breaking.
---@param context hecate.cli.Context
---@param dependencies hecate.cli.ContractDependencies
---@return integer exit_code
function M.diff(context, dependencies)
  local positionals = context.arguments.positionals
  if #positionals ~= 2 then
    context.print_error("hecate contract diff: name the previous and the current OpenAPI JSON files, for example `hecate contract diff old.json new.json`")
    return 2
  end
  local changes = dependencies.diff(load_document(dependencies, positionals[1]), load_document(dependencies, positionals[2]))
  local breaking, lines = 0, {}
  for _, change in ipairs(changes) do
    if change.breaking then breaking = breaking + 1 end
    lines[#lines + 1] = string.format("%-9s %-24s %s: %s", change.breaking and "BREAKING" or "ok", change.kind, change.path, change.message)
  end
  lines[#lines + 1] = #changes == 0 and "No change." or string.format("%d change(s), %d breaking", #changes, breaking)
  context.emit({ ok = breaking == 0, breaking = breaking, changes = changes }, table.concat(lines, "\n"))
  return breaking > 0 and 1 or 0
end

--- The real dependencies: files, the JSON codec and the OpenAPI package, loaded when the command runs.
---@return hecate.cli.ContractDependencies
function M.real_dependencies()
  local json = require("hecate.json")
  local openapi = require("hecate.openapi")
  return {
    read = function(path)
      local file = io.open(path, "rb")
      if not file then return nil end
      local text = file:read("a")
      file:close()
      return text
    end,
    decode = function(text) return json.decode(text) end,
    lint = openapi.lint,
    diff = openapi.diff,
  }
end

--- The two commands, as `hecate.cli.Command` values.
---@type hecate.cli.Command[]
M.commands = {
  {
    name = "contract lint",
    summary = "Lint an OpenAPI document (JSON file); exit 1 on an error finding",
    usage = "<file>",
    run = function(context) return M.lint(context, M.real_dependencies()) end,
  },
  {
    name = "contract diff",
    summary = "List the changes between two OpenAPI documents; exit 1 on a breaking change",
    usage = "<old> <new>",
    run = function(context) return M.diff(context, M.real_dependencies()) end,
  },
}

return M
