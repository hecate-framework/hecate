-- `hecate generate meta [--namespace <name>] [--output <file>]`: the LuaLS declaration file (`---@meta`) of the schemas of the
-- application of the project (OQ-121, `hecate.doc.project.meta`): a `---@class` per object schema of its contract, an
-- `---@alias` per enumeration, so that an editor knows the types of the requests and responses. The module of the project
-- (the name of the manifest) must have `application(options)`, as for `hecate contract export`; the schemas are the
-- `components.schemas` of the document the application gives. The file is `meta/<namespace>.lua` unless `--output` says
-- otherwise; list `meta` in `workspace.library` of `.luarc.json`. It is written on demand, never by another command.
-- An existing file given with `--output` is kept unless `--force`; when it is overwritten (`--force`, or the default file, which is
-- regenerated) the unified diff of the existing and the new content is printed first, and nothing is rewritten when they are equal.
global <const> require, error, string, type, tostring

local core = require("hecate.core")
local manifest_module = require("hecate.cli.manifest")
local templates = require("hecate.cli.templates")
local line_diff = require("hecate.cli.internal.line_diff")
local project_process = require("hecate.cli.internal.project_process")

local MANIFEST = "hecate.project.lua"

--- The program that the child runs (see `hecate contract export` for the module convention): it builds the application with the
--- `openapi` option of the manifest, boots it, takes the schemas of its contract and prints the declaration file. The names of the
--- rocks of the project are built in the text (`check-boundaries` reads the sources).
local PROGRAM = [[
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
local json = require("hecate.json")
local doc = require("hecate" .. ".doc")
local application = project.application({ openapi = { info = { title = os.getenv("HECATE_CLI_TITLE"), version = os.getenv("HECATE_CLI_VERSION") } } })
application:boot()
local document = json.decode(application:contract(false))
io.write(doc.project.meta((document.components or {}).schemas or {}, os.getenv("HECATE_CLI_NAMESPACE")))
]]

---@class hecate.cli.GenerateMetaDependencies
---@field fs { read: fun(path: string): string? }
---@field write fun(path: string, text: string)
---@field exists fun(path: string): boolean
---@field run fun(task: fun(): any): any
---@field run_process fun(program: string, args: string[], options: table): { code: integer, stdout: string, stderr: string }
---@field interpreter string
---@field interpreter_arguments? string[]

--- The `generate meta` command.
---@class hecate.cli.commands.generate_meta: hecate.cli.Command
---@field execute fun(context: hecate.cli.Context, dependencies: hecate.cli.GenerateMetaDependencies): integer
---@field PROGRAM string
local command = {
  name = "generate meta",
  summary = "Generate the LuaLS declaration file of the schemas of the application",
  options = {
    { name = "namespace", takes_value = true, summary = "The module name the types live in (default: <module>.schemas)" },
    { name = "output", takes_value = true, summary = "Write the file here (default: meta/<namespace>.lua)" },
    { name = "force", summary = "Overwrite the output file when it exists" },
  },
  PROGRAM = PROGRAM,
}

--- Runs the command.
---@param context hecate.cli.Context
---@param dependencies hecate.cli.GenerateMetaDependencies
---@return integer exit_code
function command.execute(context, dependencies)
  local options = context.arguments.options
  local text = dependencies.fs.read(MANIFEST)
  if text == nil then
    error(core.ConfigurationError({ message = MANIFEST .. " not found in the current directory: run `hecate new <name>` to create a project" }), 0)
  end
  local manifest = manifest_module.parse(text)
  if manifest.contract == nil then
    error(core.ConfigurationError({
      message = MANIFEST .. " has no `contract` section: add one, for example `contract = { title = \"" .. manifest.name .. "\", version = \"1.0.0\" }`",
    }), 0)
  end
  local module = templates.module_name(manifest.name)
  local namespace = options.namespace --[[@as string?]] or (module .. ".schemas")
  if type(namespace) ~= "string" or not namespace:match("^[%a_][%w_]*[%w_%.]*$") then
    context.print_error("hecate generate meta: --namespace takes a Lua module name such as shop.schemas (got '" .. tostring(namespace) .. "')")
    return 2
  end
  local output = options.output --[[@as string?]] or ("meta/" .. namespace .. ".lua")
  local previous = dependencies.fs.read(output) -- starts a reactor: outside `run`
  local diff, unchanged
  local code = dependencies.run(function()
    if dependencies.exists(output) and not options.force and not (options.output == nil) then
      context.print_error("hecate generate meta: " .. output .. " already exists; pass --force to overwrite it")
      return 1
    end
    local result = project_process.run(context, dependencies, PROGRAM, {
      HECATE_CLI_MODULE = module, HECATE_CLI_TITLE = manifest.contract.title, HECATE_CLI_VERSION = manifest.contract.version,
      HECATE_CLI_NAMESPACE = namespace,
    }, "the declaration file of the schemas")
    if dependencies.exists(output) then
      diff = line_diff.unified(previous or "", result.stdout, output, output .. " (new)")
      unchanged = diff == nil
      if unchanged then return 0 end
    end
    dependencies.write(output, result.stdout)
    return 0
  end)
  if code ~= 0 then return code end
  if unchanged then
    context.emit({ output = output, namespace = namespace, unchanged = true }, output .. " is unchanged.")
    return 0
  end
  context.emit({ output = output, namespace = namespace, diff = diff }, (diff and (diff .. "\n") or "") .. "Wrote " .. output .. " (" .. namespace .. ").")
  return 0
end

--- Runs `hecate generate meta` with the real file system, reactor and interpreter.
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
    run_process = function(program, args, options) return reactor.run_process(program, args, options) end,
    interpreter = context.runtime.lua_interpreter or "lua",
    interpreter_arguments = context.runtime.lua_interpreter_arguments,
  })
end

return command
