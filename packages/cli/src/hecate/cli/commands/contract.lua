-- `hecate contract lint <file>`, `hecate contract diff <old> <new>` and `hecate contract export`: the lint and the
-- breaking-change detection of `hecate.openapi` over OpenAPI documents in JSON files, and the export of the document of
-- the application of the project (`Application:contract`), made by a child process that loads the project.
global <const> require, error, ipairs, pairs, io, pcall, string, table, tostring, type

local core = require("hecate.core")
local manifest_module = require("hecate.cli.manifest")
local serve_command = require("hecate.cli.commands.serve")
local templates = require("hecate.cli.templates")
local interpreter = require("hecate.cli.internal.interpreter")

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

local function report_changes(context, changes)
  local breaking, lines = 0, {}
  for _, change in ipairs(changes) do
    if change.breaking then breaking = breaking + 1 end
    lines[#lines + 1] = string.format("%-9s %-24s %s: %s", change.breaking and "BREAKING" or "ok", change.kind, change.path, change.message)
  end
  lines[#lines + 1] = #changes == 0 and "No change." or string.format("%d change(s), %d breaking", #changes, breaking)
  context.emit({ ok = breaking == 0, breaking = breaking, changes = changes }, table.concat(lines, "\n"))
  return breaking > 0 and 1 or 0
end

--- Whether `ref` can be handed to `git show <ref>:<file>`: not an option (no leading `-`), no space, no colon.
---@param ref string
---@return boolean
function M.valid_ref(ref)
  return ref:match("^[^%-%s:][^%s:]*$") ~= nil
end

--- `hecate contract diff <ref> [--file=<path>]`: the committed contract (`git show <ref>:<path>`, default `openapi.json`)
--- against the contract of the application as it is now (made like `contract export`).
---@param context hecate.cli.Context
---@param dependencies table  the dependencies of `diff` and of `export`
---@return integer exit_code
local function diff_against_ref(context, dependencies)
  local ref = context.arguments.positionals[1]
  local file = (context.arguments.options.file --[[@as string?]]) or "openapi.json"
  if not M.valid_ref(ref) then
    context.print_error("hecate contract diff: '" .. ref .. "' is not a git ref that can be used here (no leading '-', no space, no colon)")
    return 2
  end
  if not require("hecate.cli.commands.run").inside_project(file) then
    context.print_error("hecate contract diff: --file is a relative path inside the project, got '" .. file .. "'")
    return 2
  end
  local project = (context.runtime.project_dir or "."):gsub("/+$", "")
  local old_text, new_text = dependencies.run(function()
    local shown = dependencies.run_process("git", { "show", ref .. ":" .. file }, { cwd = project })
    if shown.code ~= 0 then
      error(core.ConfigurationError({
        message = file .. " cannot be read at '" .. ref .. "': commit the contract of that version with `hecate contract export --output=" .. file
          .. "`, or name two files.\n" .. shown.stderr:gsub("%s+$", ""),
        context = { ref = ref, file = file },
      }), 0)
    end
    return shown.stdout, M.export_document(context, dependencies, false)
  end)
  local function decode(text, what)
    local ok, value = pcall(dependencies.decode, text)
    if not ok or type(value) ~= "table" then
      error(core.ConfigurationError({ message = what .. " is not a JSON OpenAPI document" }), 0)
    end
    return value
  end
  context.print_error("hecate contract diff: " .. ref .. ":" .. file .. " against the application now")
  return report_changes(context, dependencies.diff(decode(old_text, ref .. ":" .. file), decode(new_text, "the contract of the application")))
end

--- `hecate contract diff <old> <new>` (two files) or `hecate contract diff <ref>` (a git ref against the application now):
--- runs `openapi.diff`; exit 1 when a change is breaking.
---@param context hecate.cli.Context
---@param dependencies table
---@return integer exit_code
function M.diff(context, dependencies)
  local positionals = context.arguments.positionals
  if #positionals == 1 then return diff_against_ref(context, dependencies) end
  if #positionals ~= 2 then
    context.print_error("hecate contract diff: name two OpenAPI JSON files (`hecate contract diff old.json new.json`) or a git ref whose commit holds openapi.json (`hecate contract diff main`)")
    return 2
  end
  return report_changes(context, dependencies.diff(load_document(dependencies, positionals[1]), load_document(dependencies, positionals[2])))
end


--- The program that the child runs: it loads the module of the project, builds the application with the `openapi`
--- option that the manifest gives (the `contract` section), boots it and prints the document. The values come through the
--- environment, never through the text of the program.
M.CHILD_PROGRAM = [[
local name = os.getenv("HECATE_CLI_MODULE")
local loaded, project = pcall(require, name)
if not loaded then
  io.stderr:write("cannot load the module '" .. name .. "' of the project: " .. tostring(project) .. "\n")
  os.exit(3)
end
if type(project) ~= "table" or type(project.application) ~= "function" then
  io.stderr:write("the module '" .. name .. "' has no `application(options)` function\n")
  os.exit(3)
end
local servers = {}
for url in (os.getenv("HECATE_CLI_SERVERS") or ""):gmatch("[^\31]+") do servers[#servers + 1] = { url = url } end
local application = project.application({ openapi = { info = { title = os.getenv("HECATE_CLI_TITLE"), version = os.getenv("HECATE_CLI_VERSION") }, servers = servers } })
application:boot()
io.stdout:write(application:contract(os.getenv("HECATE_CLI_PRETTY") == "1"))
]]

---@class hecate.cli.ContractExportDependencies
---@field read fun(path: string): string?  the text of a file, nil when it does not exist (called inside `run`)
---@field write fun(path: string, text: string)  writes a file (called inside `run`)
---@field run fun(task: fun(): any): any  runs a suspending task to completion (the reactor)
---@field run_process fun(program: string, args: string[], options: { env?: table<string, string>, cwd?: string }): { code: integer, stdout: string, stderr: string }
---@field interpreter string
---@field interpreter_arguments? string[]

--- Makes the document of the application of the project in a child process (see `CHILD_PROGRAM`). Suspends: call it
--- inside the reactor. Raises `hecate.core.ConfigurationError` when the project cannot give one.
---@async
---@param context hecate.cli.Context
---@param dependencies hecate.cli.ContractExportDependencies
---@param pretty boolean
---@return string document  JSON text
function M.export_document(context, dependencies, pretty)
  local project = (context.runtime.project_dir or "."):gsub("/+$", "")
  local lua = context.runtime.lua_version:match("^%d+%.%d+") or context.runtime.lua_version
  local source = dependencies.read(project .. "/hecate.project.lua")
  if source == nil then
    error(core.ConfigurationError({ message = "hecate.project.lua not found in the current directory: run `hecate new <name>` to create a project" }), 0)
  end
  local manifest = manifest_module.parse(source)
  if manifest.contract == nil then
    error(core.ConfigurationError({
      message = "hecate.project.lua has no `contract` section: add one, for example `contract = { title = \"" .. manifest.name .. "\", version = \"1.0.0\" }`",
    }), 0)
  end
  local env = serve_command.environment(project, lua)
  env.HECATE_CLI_MODULE = templates.module_name(manifest.name)
  env.HECATE_CLI_TITLE = manifest.contract.title
  env.HECATE_CLI_VERSION = manifest.contract.version
  env.HECATE_CLI_SERVERS = table.concat(manifest.contract.servers or {}, "\31")
  env.HECATE_CLI_PRETTY = pretty and "1" or "0"
  local result = dependencies.run_process(dependencies.interpreter, interpreter.arguments(dependencies.interpreter_arguments, { "-e", M.CHILD_PROGRAM }), { env = env, cwd = project })
  if result.code ~= 0 then
    local detail = result.stderr ~= "" and result.stderr:gsub("%s+$", "") or ("the process exited with " .. result.code)
    error(core.ConfigurationError({ message = "the contract of the application could not be made:\n" .. detail, context = { code = result.code } }), 0)
  end
  return result.stdout
end

--- `hecate contract export [--output=<file>] [--pretty]`: the OpenAPI document of the application of the project. The
--- module of the project (the name of the manifest as a Lua module, `src/<module>/init.lua` as `hecate new` makes it)
--- must have `application(options)`; the `contract` section of the manifest (`title`, `version`, `servers`) gives its
--- `openapi` option. Without `--output` the document goes to standard output.
---@param context hecate.cli.Context
---@param dependencies hecate.cli.ContractExportDependencies
---@return integer exit_code
function M.export(context, dependencies)
  local options = context.arguments.options
  if #context.arguments.positionals > 0 then
    context.print_error("hecate contract export: takes no argument (use --output=<file>)")
    return 2
  end
  local project = (context.runtime.project_dir or "."):gsub("/+$", "")
  local output = options.output --[[@as string?]]

  local text = dependencies.run(function()
    local document = M.export_document(context, dependencies, options.pretty == true)
    if output then dependencies.write(output:match("^/") and output or (project .. "/" .. output), document) end
    return document
  end)

  if output then
    context.print_error(string.format("hecate contract export: wrote %d bytes to %s", #text, output))
  else
    context.print(text)
  end
  return 0
end

--- The real dependencies of `export`: the reactor file system and process runner.
---@param context hecate.cli.Context
---@return hecate.cli.ContractExportDependencies
function M.real_export_dependencies(context)
  local reactor = require("hecate.reactor")
  return {
    read = function(path)
      if not reactor.fs.stat(path) then return nil end
      return reactor.fs.read_file(path)
    end,
    write = function(path, text) reactor.fs.write_file(path, text) end,
    run = function(task) return reactor.run(task) end,
    run_process = function(program, args, process_options) return reactor.run_process(program, args, process_options) end,
    interpreter = context.runtime.lua_interpreter or "lua",
    interpreter_arguments = context.runtime.lua_interpreter_arguments,
  }
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
    summary = "List the changes between two OpenAPI documents, or between a git ref and the application now; exit 1 on a breaking change",
    usage = "<old> <new> | <ref>",
    options = { { name = "file", takes_value = true, summary = "With a git ref: the committed contract (default openapi.json)" } },
    run = function(context)
      local dependencies = M.real_dependencies()
      for key, value in pairs(M.real_export_dependencies(context)) do
        if dependencies[key] == nil then dependencies[key] = value end
      end
      return M.diff(context, dependencies)
    end,
  },
  {
    name = "contract export",
    summary = "Write the OpenAPI document of the application of the project (JSON)",
    options = {
      { name = "output", takes_value = true, summary = "Write the document to this file instead of standard output" },
      { name = "pretty", summary = "Indent the document" },
    },
    run = function(context) return M.export(context, M.real_export_dependencies(context)) end,
  },
}

return M
