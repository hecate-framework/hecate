-- `hecate generate workflow <kind> [--provider github] [--doc] [--output <file>] [--force]`: writes a CI workflow for the project
-- (cli-and-packaging.md, "Generated workflows"). `ci` exists so far: install, test and, when the manifest has a `contract`
-- section, lint the contract, on Linux, macOS and Windows, with the setup action of the project. The workflow goes to
-- `.github/workflows/<kind>.yml` unless `--output` says otherwise; an existing file is kept unless `--force`.
global <const> require, error, ipairs, pcall, type, tostring

local core = require("hecate.core")
local manifest_module = require("hecate.cli.manifest")
local workflows = require("hecate.cli.templates.workflows")

local MANIFEST = "hecate.project.lua"

---@class hecate.cli.GenerateWorkflowDependencies
---@field fs { read: fun(path: string): string? }
---@field write fun(path: string, text: string)
---@field exists fun(path: string): boolean
---@field run fun(task: fun(): any): any

--- The `generate workflow` command.
---@class hecate.cli.commands.generate_workflow: hecate.cli.Command
---@field execute fun(context: hecate.cli.Context, dependencies: hecate.cli.GenerateWorkflowDependencies): integer
local command = {
  name = "generate workflow",
  summary = "Generate a CI workflow for the project (ci)",
  usage = "<kind> [--provider github] [--doc] [--output <file>] [--force]",
  options = {
    { name = "provider", takes_value = true, summary = "The CI provider: github (default)" },
    { name = "doc", summary = "Also build the documentation (hecate doc build --yes)" },
    { name = "output", takes_value = true, summary = "Write the workflow here (default: .github/workflows/<kind>.yml)" },
    { name = "force", summary = "Overwrite the output file when it exists" },
  },
}

--- Runs the command.
---@param context hecate.cli.Context
---@param dependencies hecate.cli.GenerateWorkflowDependencies
---@return integer exit_code
function command.execute(context, dependencies)
  local options = context.arguments.options
  local positionals = context.arguments.positionals
  if #positionals ~= 1 then
    context.print_error("hecate generate workflow: name the kind of workflow, for example `hecate generate workflow ci`")
    return 2
  end
  local kind = positionals[1]
  if not workflows.kinds[kind] then
    local hint = "available: ci"
    for _, planned in ipairs(workflows.planned_kinds) do
      if planned == kind then hint = "`" .. kind .. "` is specified but not implemented yet; available: ci" end
    end
    context.print_error("hecate generate workflow: unknown kind '" .. tostring(kind):gsub("%c", "?") .. "' (" .. hint .. ")")
    return 2
  end
  local provider = options.provider or "github"
  if provider ~= "github" then
    context.print_error("hecate generate workflow: unknown provider '" .. tostring(provider):gsub("%c", "?") .. "' (available: github)")
    return 2
  end
  local text = dependencies.fs.read(MANIFEST)
  if text == nil then
    error(core.ConfigurationError({ message = MANIFEST .. " not found in the current directory: run `hecate new <name>` to create a project" }), 0)
  end
  local manifest = manifest_module.parse(text)
  local ok, workflow = pcall(workflows[kind], {
    hecate_version = context.runtime.hecate_version, contract = manifest.contract ~= nil, doc = options.doc == true,
  })
  if not ok then
    context.print_error("hecate generate workflow: " .. (type(workflow) == "table" and workflow.message or tostring(workflow)))
    return 1
  end
  local output = options.output --[[@as string?]] or (".github/workflows/" .. kind .. ".yml")
  local code = dependencies.run(function()
    if dependencies.exists(output) and not options.force then
      context.print_error("hecate generate workflow: " .. output .. " already exists; pass --force to overwrite it")
      return 1
    end
    dependencies.write(output, workflow)
    return 0
  end)
  if code ~= 0 then return code end
  context.emit({ output = output, kind = kind, provider = provider }, "Wrote " .. output .. ".\nCommit it; it runs on every push and pull request.")
  return 0
end

--- Runs `hecate generate workflow` with the real file system and reactor.
---@param context hecate.cli.Context
---@return integer exit_code
function command.run(context)
  local project_environment = require("hecate.cli.internal.project_environment")
  local reactor = require("hecate.reactor")
  local environment = project_environment.real(context.runtime)
  return command.execute(context, {
    fs = { read = function(path) return reactor.run(function()
      if not reactor.fs.stat(path) then return nil end
      return reactor.fs.read_file(path)
    end) end },
    write = environment.fs.write,
    exists = function(path) return reactor.fs.stat(path) ~= nil end, -- called inside `run`, which is the reactor
    run = environment.run,
  })
end

return command
