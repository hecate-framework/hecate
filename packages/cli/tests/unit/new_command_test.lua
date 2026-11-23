local test = require("harness.test")
local app = require("hecate.cli.app")
local new = require("hecate.cli.commands.new")
local manifest = require("hecate.cli.manifest")
local T = test.Case("CliNewCommandTest")

local runtime = { hecate_version = "0.1.0", lua_version = "5.5.1", platform = "linux-x86_64" }

local function run(args, existing)
  local written = {}
  local dependencies = {
    write = function(path, text) written[path] = text end,
    exists = function(path) return existing == path end,
    run = function(task) return task() end,
  }
  local command = setmetatable({ run = function(context) return new.execute(context, dependencies) end }, { __index = new })
  local out, err = {}, {}
  local code = app.run(args, {
    commands = { command }, runtime = runtime,
    write = function(text) out[#out + 1] = text end,
    write_error = function(text) err[#err + 1] = text end,
    encode_json = function(value) return "json:" .. value.name end,
  })
  return code, table.concat(out, "\n"), table.concat(err, "\n"), written
end

function T:test_the_minimal_template_writes_a_valid_project()
  local code, out, _, written = run({ "new", "my-api" })
  self:assert_equal(0, code)
  self:assert_true(out:find("Created my%-api") ~= nil, out)
  for _, path in ipairs({ "my-api/hecate.project.lua", "my-api/main.lua", "my-api/src/my_api/init.lua", "my-api/tests/my_api_test.lua", "my-api/.gitignore", "my-api/README.md" }) do
    self:assert_true(written[path] ~= nil, path)
  end
  local loaded = manifest.parse(written["my-api/hecate.project.lua"])
  self:assert_equal("my-api", loaded.name)
  self:assert_equal("~> 0.1", loaded.dependencies.hecate)
  for path, text in pairs(written) do
    if path:match("%.lua$") then self:assert_true(load(text, "=" .. path) ~= nil, path) end
  end
end

function T:test_an_existing_directory_is_never_overwritten()
  local code, _, err, written = run({ "new", "app" }, "app")
  self:assert_equal(1, code)
  self:assert_true(err:find("already exists") ~= nil, err)
  self:assert_equal(nil, next(written))
end

function T:test_bad_names_and_templates_are_usage_errors()
  self:assert_equal(2, (run({ "new" })))
  self:assert_equal(2, (run({ "new", "My App" })))
  self:assert_equal(2, (run({ "new", "1app" })))
  local code, _, err = run({ "new", "app", "--template=crud" })
  self:assert_equal(2, code)
  self:assert_true(err:find("available: minimal") ~= nil, err)
end

function T:test_json_output()
  local _, out = run({ "new", "app", "--json" })
  self:assert_equal("json:app", out)
end

return T
