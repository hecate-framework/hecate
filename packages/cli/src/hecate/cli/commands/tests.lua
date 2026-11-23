-- `hecate test [paths] [--filter=<pattern>] [--case=<name>] [--tag=<tag>] [--exclude-tag=<tag>]`: runs the tests of the
-- project with `hecate.test`, inside the reactor, with the dependencies of `lua_modules` and the sources of the project
-- on the module path.
global <const> require, error, ipairs, package, table, type, pcall, tostring

local core = require("hecate.core")

local MANIFEST = "hecate.project.lua"
local DEFAULT_DIRECTORY = "tests"

---@class hecate.cli.TestDependencies
---@field fs { read: fun(path: string): string? }  reads a file, nil when it does not exist
---@field run fun(task: fun(): any): any  runs a suspending task to completion (the reactor)
---@field load_test fun(): hecate.test  loads the test framework, after the module path is set
---@field set_module_path fun(project: string, lua: string)  puts the directories of the project on the module path of the process

--- The `test` command.
---@class hecate.cli.commands.test: hecate.cli.Command
---@field execute fun(context: hecate.cli.Context, dependencies: hecate.cli.TestDependencies): integer
local command = {
  name = "test",
  summary = "Run the tests of the project",
  usage = "[<file or directory>...]",
  options = {
    { name = "filter", takes_value = true, summary = "Run the tests whose full name matches this Lua pattern" },
    { name = "case", takes_value = true, repeatable = true, summary = "Run only the case with this name (repeatable)" },
    { name = "tag", takes_value = true, repeatable = true, summary = "Run only the tests carrying this tag (repeatable)" },
    { name = "exclude-tag", takes_value = true, repeatable = true, summary = "Skip the tests carrying this tag (repeatable)" },
  },
}

--- The directories that the tests of a project need on the module path: the dependencies installed by `hecate install`,
--- then the sources of the project (`src` and the root).
---@param project string  absolute path of the project, forward slashes, no trailing slash
---@param lua string  the Lua line (`5.5`)
---@return string[] lua_paths  `?.lua` and `?/init.lua` templates, in priority order
---@return string[] native_paths  `?.so` and `?.dll` templates
function command.module_paths(project, lua)
  local tree = project .. "/lua_modules"
  local share, lib = tree .. "/share/lua/" .. lua .. "/", tree .. "/lib/lua/" .. lua .. "/"
  return {
    project .. "/src/?.lua", project .. "/src/?/init.lua",
    project .. "/?.lua", project .. "/?/init.lua",
    share .. "?.lua", share .. "?/init.lua",
  }, { lib .. "?.so", lib .. "?.dll" }
end

--- Puts the module paths of the project in front of those of the process.
---@param project string
---@param lua string
local function set_module_path(project, lua)
  local lua_paths, native_paths = command.module_paths(project, lua)
  package.path = table.concat(lua_paths, ";") .. ";" .. package.path
  package.cpath = table.concat(native_paths, ";") .. ";" .. package.cpath
end

--- The test files named by the paths: a file as it is, a directory by discovery.
---@param test hecate.test
---@param paths string[]
---@return string[] files
local function files_of(test, paths)
  local files = {}
  for _, path in ipairs(paths) do
    if path:match("%.lua$") then
      files[#files + 1] = path
    else
      for _, file in ipairs(test.discover(path)) do files[#files + 1] = file end
    end
  end
  return files
end

--- Runs the command with the given file system, reactor and test framework.
---@param context hecate.cli.Context
---@param dependencies hecate.cli.TestDependencies
---@return integer exit_code
function command.execute(context, dependencies)
  if dependencies.fs.read(MANIFEST) == nil then
    error(core.ConfigurationError({ message = MANIFEST .. " not found in the current directory: run `hecate new <name>` to create a project" }), 0)
  end
  local arguments = context.arguments
  local paths = #arguments.positionals > 0 and arguments.positionals or { DEFAULT_DIRECTORY }
  local options = arguments.options
  local filter = options.filter --[[@as string?]]
  dependencies.set_module_path((context.runtime.project_dir or "."):gsub("/+$", ""), (context.runtime.lua_version:match("^%d+%.%d+")) or context.runtime.lua_version)
  local test = dependencies.load_test()

  -- Discovery reads the file system, which suspends: it runs in a reactor. The runner runs each test in a reactor of its
  -- own (it cannot be called inside one), so it runs outside.
  local found = dependencies.run(function()
    local files = files_of(test, paths)
    local cases, load_errors = {}, {}
    for _, file in ipairs(files) do
      local ok, loaded = pcall(test.load, file)
      if ok then cases[#cases + 1] = loaded
      else load_errors[#load_errors + 1] = type(loaded) == "table" and loaded.message or tostring(loaded) end
    end
    return { files = files, cases = cases, load_errors = load_errors }
  end)
  local reporter = context.json and test.JsonLinesReporter({ write = context.print }) or test.ConsoleReporter()
  local runner = test.Runner({
    reporter = reporter,
    filter = filter,
    cases = options.case --[[@as string[]?]],
    tags = options.tag --[[@as string[]?]],
    exclude_tags = options["exclude-tag"] --[[@as string[]?]],
  })
  local summary = { summary = runner:run(found.cases), files = #found.files, load_errors = found.load_errors }

  for _, message in ipairs(summary.load_errors) do context.print_error("hecate test: " .. message) end
  if summary.files == 0 then
    context.print_error("hecate test: no test file found in " .. table.concat(paths, ", ") .. " (test files end in _test.lua)")
  elseif summary.summary.empty and #summary.load_errors == 0 then
    context.print_error("hecate test: no test matches the selection")
  end
  return (summary.summary.exit_code ~= 0 or #summary.load_errors > 0) and 1 or 0
end

--- Runs `hecate test` with the real file system and reactor, and the `hecate.test` of the project.
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
    set_module_path = set_module_path,
    -- `hecate.test` is a rock of the project (installed in `lua_modules`), not a dependency of the CLI: it is loaded by a
    -- name built here, after the module path is set, as the generated tests do (see `templates`).
    load_test = function() local framework = require("hecate" .. ".test"); return framework end,
  })
end

return command
