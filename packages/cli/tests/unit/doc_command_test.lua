local test = require("harness.test")
local app = require("hecate.cli.app")
local doc_command = require("hecate.cli.commands.doc")
local T = test.Case("CliDocCommandTest")
local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or "."
local nested = dofile(here .. "/../support/nested_guard.lua")

local runtime = { hecate_version = "0.1.0", lua_version = "5.5.1", platform = "linux-x86_64", project_dir = "/work/app" }

local function run(args, opts)
  opts = opts or {}
  local seen = { asked = 0 }
  local manifest = opts.manifest or 'return { name = "shop", doc = { guides_dir = "guides", package_name = "shop" } }'
  local dependencies = {
    fs = { read = nested.outside(function(path) if opts.no_manifest then return nil end; return path == "hecate.project.lua" and manifest or nil end) }, -- the real read starts a reactor: valid only outside `run`
    run = nested.run,
    ask = function() seen.asked = seen.asked + 1; return opts.answer == true end,
    generate = function(options, module)
      seen.options = options
      seen.module = module
      return { files = 3, bytes = 30, problems = opts.problems or {}, sites = { { audience = "maintainer", files = 3, bytes = 30, directory = "docs/dist/maintainer" } } }
    end,
  }
  local out, err = {}, {}
  local command = setmetatable({ run = function(context) return doc_command.execute(context, dependencies) end }, { __index = doc_command })
  local code = app.run(args, {
    commands = { command }, runtime = runtime,
    write = function(text) out[#out + 1] = text end,
    write_error = function(text) err[#err + 1] = text end,
  })
  return code, table.concat(out, "\n"), table.concat(err, "\n"), seen
end

function T:test_manifest_section_and_flags_reach_the_generator()
  local code, out, _, seen = run({ "doc", "build", "--yes", "--output=site", "--audience=user" })
  self:assert_equal(0, code)
  self:assert_equal("guides", seen.options.guides_dir)
  self:assert_equal("site", seen.options.output_dir)
  self:assert_equal("user", seen.options.audiences[1])
  self:assert_equal("/work/app", seen.options.project_dir)
  self:assert_equal(0, seen.asked)
  self:assert_true(out:find("maintainer", 1, true) ~= nil)
end

function T:test_the_code_reference_asks_and_stops_on_no()
  local code, _, err, seen = run({ "doc", "build" })
  self:assert_equal(1, code)
  self:assert_equal(1, seen.asked)
  self:assert_equal(nil, seen.options)
  self:assert_true(err:find("LuaLS", 1, true) ~= nil)
end

function T:test_a_yes_answer_builds()
  local code, _, _, seen = run({ "doc", "build" }, { answer = true })
  self:assert_equal(0, code)
  self:assert_equal("shop", seen.options.package_name)
end

function T:test_no_question_without_a_code_reference()
  local code, _, _, seen = run({ "doc", "build" }, { manifest = 'return { name = "shop" }' })
  self:assert_equal(0, code)
  self:assert_equal(0, seen.asked)
end

function T:test_problems_fail_the_build()
  local code, out = run({ "doc", "build", "--yes" }, { problems = { "maintainer site: broken link" } })
  self:assert_equal(1, code)
  self:assert_true(out:find("broken link", 1, true) ~= nil)
end

function T:test_missing_manifest_is_an_error()
  local code, _, err = run({ "doc", "build" }, { no_manifest = true })
  self:assert_equal(1, code)
  self:assert_true(err:find("hecate.project.lua not found", 1, true) ~= nil)
end

function T:test_the_module_of_the_project_goes_to_the_generator_for_the_configuration_reference()
  local _, _, _, seen = run({ "doc", "build", "--yes" })
  self:assert_equal("shop", seen.module)
  local _, _, _, other = run({ "doc", "build", "--yes" }, { manifest = 'return { name = "my-api" }' })
  self:assert_equal("my_api", other.module)
end

return T
