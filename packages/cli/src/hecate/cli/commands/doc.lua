-- `hecate doc build [--audience=<name>] [--output=<dir>] [--yes]`: builds the documentation site of the project with
-- `hecate.doc.generate_project_documentation`, from the `doc` section of `hecate.project.lua`; the flags override the section.
-- When the project asks for a code reference (`package_name`), LuaLS runs the plugins that its configuration files declare:
-- the command says so and asks before going on (`--yes` answers for CI; nothing answering means no).
global <const> require, error, io, ipairs, pairs, string, table, type

local core = require("hecate.core")
local manifest_module = require("hecate.cli.manifest")

local MANIFEST = "hecate.project.lua"

---@class hecate.cli.DocDependencies
---@field fs { read: fun(path: string): string? }  reads a file, nil when it does not exist
---@field run fun(task: fun(): any): any  runs a suspending task to completion (the reactor)
---@field ask fun(question: string): boolean  asks a yes/no question; false when nothing answers
---@field generate fun(options: hecate.doc.ProjectDocumentationOptions): hecate.doc.ProjectDocumentationReport

local WARNING = "hecate doc build: the code reference runs LuaLS, which runs the plugin declared by any LuaLS configuration "
  .. "reachable from the documented directory (.luarc.json, .luarc.jsonc, .vscode/settings.json), with full file and command "
  .. "access as the current user. Build only a project you trust."

--- The `doc build` command.
---@class hecate.cli.commands.doc_build: hecate.cli.Command
---@field execute fun(context: hecate.cli.Context, dependencies: hecate.cli.DocDependencies): integer
local command = {
  name = "doc build",
  summary = "Build the documentation site of the project",
  options = {
    { name = "audience", takes_value = true, repeatable = true, summary = "Build this audience tree (`user` or `maintainer`, repeatable; default `maintainer`)" },
    { name = "output", takes_value = true, summary = "Write the sites to this directory (default `docs/dist`)" },
    { name = "yes", summary = "Run the code reference without asking (for CI)" },
  },
}

--- Runs the command with the given file system, reactor, prompt and generator.
---@param context hecate.cli.Context
---@param dependencies hecate.cli.DocDependencies
---@return integer exit_code
function command.execute(context, dependencies)
  local text = dependencies.fs.read(MANIFEST)
  if text == nil then
    error(core.ConfigurationError({ message = MANIFEST .. " not found in the current directory: run `hecate new <name>` to create a project" }), 0)
  end
  local manifest = manifest_module.parse(text)
  local options = {}
  for key, value in pairs(manifest.doc or {}) do options[key] = value end
  local given = context.arguments.options
  if given.output then options.output_dir = given.output end
  if given.audience then options.audiences = given.audience end
  options.project_dir = context.runtime.project_dir

  if options.package_name and not given.yes then
    context.print_error(WARNING)
    if not dependencies.ask("Run LuaLS on this project? [y/N] ") then
      context.print_error("hecate doc build: stopped; pass --yes to run without asking, or remove `package_name` from the `doc` section")
      return 1
    end
  end

  local report = dependencies.run(function() return dependencies.generate(options) end)
  local lines = {}
  for _, site in ipairs(report.sites) do
    lines[#lines + 1] = string.format("%-11s %d files, %d bytes -> %s", site.audience, site.files, site.bytes, site.directory)
  end
  for _, problem in ipairs(report.problems) do lines[#lines + 1] = "problem: " .. problem end
  context.emit({ ok = #report.problems == 0, files = report.files, bytes = report.bytes, problems = report.problems }, table.concat(lines, "\n"))
  return #report.problems > 0 and 1 or 0
end

--- Runs `hecate doc build` with the real file system and reactor, the standard input for the question, and `hecate.doc`.
---@param context hecate.cli.Context
---@return integer exit_code
function command.run(context)
  local reactor = require("hecate.reactor")
  return command.execute(context, {
    fs = { read = function(path) return reactor.run(function()
      if not reactor.fs.stat(path) then return nil end
      return reactor.fs.read_file(path)
    end) end },
    run = function(task) return reactor.run(task) end,
    ask = function(question)
      io.stderr:write(question)
      local answer = io.read("l")
      return type(answer) == "string" and answer:lower():match("^%s*y") ~= nil
    end,
    generate = require("hecate.doc").generate_project_documentation,
  })
end

return command
