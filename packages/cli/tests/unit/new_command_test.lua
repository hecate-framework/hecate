local test = require("harness.test")
local app = require("hecate.cli.app")
local new = require("hecate.cli.commands.new")
local manifest = require("hecate.cli.manifest")
local T = test.Case("CliNewCommandTest")
local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or "."
local nested = dofile(here .. "/../support/nested_guard.lua")

local runtime = { hecate_version = "0.1.0", lua_version = "5.5.1", platform = "linux-x86_64" }

local function run(args, existing)
  local written = {}
  local dependencies = {
    write = function(path, text) written[path] = text end,
    exists = function(path) return existing == path end,
    run = nested.run,
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
  for _, path in ipairs({ "my-api/hecate.project.lua", "my-api/main.lua", "my-api/src/my_api/init.lua", "my-api/tests/my_api_test.lua", "my-api/.gitignore", "my-api/README.md", "my-api/docs/site.lua", "my-api/docs/maintainer/en/index.md", "my-api/config/development.lua", "my-api/config/test.lua" }) do
    self:assert_true(written[path] ~= nil, path)
  end
  local loaded = manifest.parse(written["my-api/hecate.project.lua"])
  self:assert_equal("my-api", loaded.name)
  self:assert_equal("~> 0.1", loaded.dependencies.hecate)
  self:assert_equal("docs", loaded.doc.guides_dir) -- the conventional layout of `hecate doc build`
  self:assert_equal("docs/dist", loaded.doc.output_dir)
  self:assert_equal("my-api", loaded.doc.package_name)
  for path, text in pairs(written) do
    if path:match("%.lua$") then self:assert_true(load(text, "=" .. path) ~= nil, path) end
  end
end

function T:test_ci_github_adds_the_ci_workflow()
  local code, _, _, written = run({ "new", "shop", "--ci", "github" })
  self:assert_equal(0, code)
  local text = written["shop/.github/workflows/ci.yml"]
  self:assert_true(text ~= nil and text:find("hecate install --frozen", 1, true) ~= nil)
  self:assert_true(text:find("hecate contract lint", 1, true) ~= nil) -- the api template has a contract
  local _, _, _, minimal = run({ "new", "shop", "--template", "minimal", "--ci", "github" })
  self:assert_true(minimal["shop/.github/workflows/ci.yml"]:find("contract", 1, true) == nil)
  local _, _, _, plain = run({ "new", "shop" })
  self:assert_equal(nil, plain["shop/.github/workflows/ci.yml"])
  local bad, _, err, none = run({ "new", "shop", "--ci", "gitlab" })
  self:assert_equal(2, bad)
  self:assert_true(err:find("github", 1, true) ~= nil, err)
  self:assert_equal(nil, next(none))
end

function T:test_a_name_that_windows_reserves_is_refused_everywhere()
  for _, name in ipairs({ "con", "nul", "aux", "prn", "com1", "lpt9", "con.txt", "nul.v2", "app." }) do
    local code, _, err, written = run({ "new", name })
    self:assert_equal(2, code, name)
    self:assert_true(err:find("Windows reserves", 1, true) ~= nil, err)
    self:assert_equal(nil, next(written))
  end
  self:assert_equal(0, (run({ "new", "console" })))
  self:assert_equal(0, (run({ "new", "com10" })))
end

function T:test_the_gitignore_keeps_secrets_and_release_archives_out_of_the_repository()
  local _, _, _, written = run({ "new", "shop" })
  for _, line in ipairs({ "lua_modules/", ".env", "/*.tar.gz", "/RELEASE" }) do
    self:assert_true(written["shop/.gitignore"]:find(line, 1, true) ~= nil, line)
  end
  self:assert_true(written["shop/README.md"]:find("hecate install --frozen", 1, true) ~= nil)
end

function T:test_the_next_step_names_the_environment_to_serve()
  local _, out = run({ "new", "shop" })
  self:assert_true(out:find("hecate serve --env development", 1, true) ~= nil, out)
end

function T:test_the_api_template_adds_a_resource_with_its_schemas_and_tests()
  local code, out, _, written = run({ "new", "shop", "--template=api" })
  self:assert_equal(0, code)
  self:assert_true(out:find("from the api template", 1, true) ~= nil, out)
  for _, path in ipairs({ "shop/hecate.project.lua", "shop/main.lua", "shop/src/shop/init.lua", "shop/src/shop/items.lua",
    "shop/src/shop/schemas.lua", "shop/tests/shop_test.lua", "shop/.gitignore", "shop/README.md" }) do
    self:assert_true(written[path] ~= nil, path)
  end
  for path, text in pairs(written) do
    if path:match("%.lua$") then self:assert_true(load(text, "=" .. path) ~= nil, path) end
  end
  self:assert_true(written["shop/src/shop/init.lua"]:find('require("shop.items")', 1, true) ~= nil)
  self:assert_true(written["shop/src/shop/items.lua"]:find('require("shop.schemas")', 1, true) ~= nil)
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
  local code, _, err = run({ "new", "app", "--template=nope" })
  self:assert_equal(2, code)
  self:assert_true(err:find("available: api, minimal") ~= nil, err)
end

function T:test_json_output()
  local _, out = run({ "new", "app", "--json" })
  self:assert_equal("json:app", out)
end

return T
