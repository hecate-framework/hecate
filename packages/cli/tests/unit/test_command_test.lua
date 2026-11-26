local test = require("harness.test")
local app = require("hecate.cli.app")
local test_command = require("hecate.cli.commands.tests")
local T = test.Case("CliTestCommandTest")

local runtime = { hecate_version = "0.1.0", lua_version = "5.5.1", platform = "linux-x86_64", project_dir = "/work/app" }

-- A fake of `hecate.test`: records what the command passes to the runner.
local function fake(seen, summary, files)
  local framework = {
    discover = function(directory) seen.discovered[#seen.discovered + 1] = directory; return files or { directory .. "/a_test.lua" } end,
    load = function(path)
      if path:find("broken") then error({ message = path .. " does not load" }, 0) end
      return { path = path }
    end,
    ConsoleReporter = function() return { kind = "console" } end,
    JsonLinesReporter = function(options) return { kind = "json", write = options.write } end,
    run_parallel = function(files, options)
      seen.parallel = { files = files, options = options }
      return summary or { exit_code = 0, empty = false }
    end,
    Runner = function(options)
      seen.options = options
      return { run = function(_, cases)
        -- The real runner starts a reactor for each test: it cannot be called inside the reactor of the command.
        assert(not seen.inside_reactor, "the runner was called inside the reactor")
        seen.cases = cases
        return summary or { exit_code = 0, empty = false }
      end }
    end,
  }
  return framework
end

local function run(args, opts)
  opts = opts or {}
  local seen = { discovered = {} }
  local files = opts.manifest == false and {} or { ["hecate.project.lua"] = "return {}" }
  local dependencies = {
    fs = { read = function(path) return files[path] end },
    run = function(task)
      seen.inside_reactor = true
      local result = task()
      seen.inside_reactor = false
      return result
    end,
    set_module_path = function(project, lua) seen.module_path = { project, lua } end,
    load_test = function() return fake(seen, opts.summary, opts.files) end,
  }
  local out, err = {}, {}
  local command = setmetatable({ run = function(context) return test_command.execute(context, dependencies) end }, { __index = test_command })
  local code = app.run(args, {
    commands = { command }, runtime = runtime,
    write = function(text) out[#out + 1] = text end,
    write_error = function(text) err[#err + 1] = text end,
  })
  return code, table.concat(err, "\n"), seen
end

function T:test_default_directory_and_selection_reach_the_runner()
  local code, _, seen = run({ "test", "--filter=Health", "--case", "A", "--case=B", "--tag=fast", "--exclude-tag=slow" })
  self:assert_equal(0, code)
  self:assert_equal("tests", table.concat(seen.discovered, ","))
  self:assert_equal("Health", seen.options.filter)
  self:assert_equal("A,B", table.concat(seen.options.cases, ","))
  self:assert_equal("fast", table.concat(seen.options.tags, ","))
  self:assert_equal("slow", table.concat(seen.options.exclude_tags, ","))
  self:assert_equal("/work/app 5.5", seen.module_path[1] .. " " .. seen.module_path[2])
  self:assert_equal("console", seen.options.reporter.kind)
end

function T:test_files_are_loaded_as_they_are_and_directories_discovered()
  local _, _, seen = run({ "test", "tests/x_test.lua", "more" })
  self:assert_equal("more", table.concat(seen.discovered, ","))
  self:assert_equal("tests/x_test.lua,more/a_test.lua", seen.cases[1].path .. "," .. seen.cases[2].path)
end

function T:test_a_project_without_its_rocks_is_told_to_install_them()
  local out, err = {}, {}
  local command = setmetatable({ run = function(context)
    return test_command.execute(context, {
      fs = { read = function() return "return { name = 'x' }" end },
      run = function(task) return task() end,
      set_module_path = function() end,
      load_test = function() error("module 'hecate.test' not found:\n\tno file 'x'", 0) end,
    })
  end }, { __index = test_command })
  local code = app.run({ "test" }, {
    commands = { command }, runtime = { hecate_version = "0.1.0", lua_version = "5.5.1", platform = "linux-x86_64", project_dir = "/work/app" },
    write = function(text) out[#out + 1] = text end, write_error = function(text) err[#err + 1] = text end,
  })
  self:assert_equal(1, code)
  local text = table.concat(err, "\n")
  self:assert_true(text:find("hecate install", 1, true) ~= nil, text)
  self:assert_true(text:find("no file 'x'", 1, true) == nil, text)
end

function T:test_a_failing_run_exits_1()
  local code = run({ "test" }, { summary = { exit_code = 1, empty = false } })
  self:assert_equal(1, code)
end

function T:test_a_file_that_does_not_load_fails_the_run_and_is_named()
  local code, err = run({ "test", "broken_test.lua" })
  self:assert_equal(1, code)
  self:assert_true(err:find("broken_test.lua does not load", 1, true) ~= nil, err)
end

function T:test_no_file_and_empty_selection_are_said()
  local code, err = run({ "test" }, { files = {} })
  self:assert_equal(0, code)
  self:assert_true(err:find("no test file found in tests", 1, true) ~= nil, err)
  local _, err2 = run({ "test" }, { summary = { exit_code = 0, empty = true } })
  self:assert_true(err2:find("no test matches the selection", 1, true) ~= nil, err2)
end

function T:test_json_uses_the_json_lines_reporter()
  local _, _, seen = run({ "test", "--json" })
  self:assert_equal("json", seen.options.reporter.kind)
end

function T:test_outside_a_project_fails_with_the_way_out()
  local code, err = run({ "test" }, { manifest = false })
  self:assert_equal(1, code)
  self:assert_true(err:find("hecate new", 1, true) ~= nil, err)
end

function T:test_module_paths_put_the_project_before_its_dependencies()
  local lua_paths, native_paths = test_command.module_paths("/p", "5.5")
  self:assert_equal("/p/src/?.lua", lua_paths[1])
  self:assert_equal("/p/lua_modules/share/lua/5.5/?/init.lua", lua_paths[#lua_paths])
  self:assert_equal("/p/lua_modules/lib/lua/5.5/?.so", native_paths[1])
end

function T:test_jobs_runs_the_files_in_worker_processes_of_the_interpreter()
  local code, _, seen = run({ "test", "--jobs=3", "--filter=Health" })
  self:assert_equal(0, code)
  self:assert_true(seen.cases == nil, "the in-process runner was not used")
  self:assert_equal(3, seen.parallel.options.jobs)
  self:assert_equal("Health", seen.parallel.options.filter)
  self:assert_equal("tests/a_test.lua", seen.parallel.files[1])
  self:assert_equal("console", seen.parallel.options.reporter.kind)
end

function T:test_jobs_is_a_whole_number_of_at_least_one_and_a_failure_is_exit_1()
  for _, bad in ipairs({ "0", "-2", "1.5", "many" }) do
    local code, err = run({ "test", "--jobs=" .. bad })
    self:assert_equal(2, code, bad)
    self:assert_true(err:find("--jobs", 1, true) ~= nil, err)
  end
  local code = run({ "test", "--jobs=2" }, { summary = { exit_code = 1, empty = false } })
  self:assert_equal(1, code)
end

return T
