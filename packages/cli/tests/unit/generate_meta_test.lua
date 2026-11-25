local test = require("harness.test")
local app = require("hecate.cli.app")
local generate_meta = require("hecate.cli.commands.generate_meta")
local T = test.Case("CliGenerateMetaTest")
local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or "."
local nested = dofile(here .. "/../support/nested_guard.lua")

local MANIFEST = 'return { name = "my-shop", version = "0.1.0", contract = { title = "My shop", version = "1.2.3" } }'

local function run(args, opts)
  opts = opts or {}
  local written, spawned = {}, {}
  local files = { ["hecate.project.lua"] = opts.manifest == nil and MANIFEST or opts.manifest }
  local dependencies = {
    fs = { read = nested.outside(function(path) return files[path] end) }, -- the real read starts a reactor: valid only outside `run`
    write = function(path, text) written[path] = text end,
    exists = function(path) return path == opts.existing end,
    run = nested.run,
    run_process = function(program, process_args, options)
      spawned[#spawned + 1] = { program = program, args = process_args, options = options }
      return { code = opts.code or 0, stdout = "---@meta my_shop.schemas\n", stderr = opts.stderr or "" }
    end,
    interpreter = "/usr/bin/lua",
  }
  local out, err = {}, {}
  local command = setmetatable({ run = function(context) return generate_meta.execute(context, dependencies) end }, { __index = generate_meta })
  local code = app.run(args, {
    commands = { command },
    runtime = { hecate_version = "0.1.0", lua_version = "5.5.1", platform = "linux-x86_64", project_dir = "/work/shop" },
    write = function(text) out[#out + 1] = text end,
    write_error = function(text) err[#err + 1] = text end,
  })
  return code, table.concat(out, "\n"), table.concat(err, "\n"), written, spawned
end

function T:test_the_file_is_written_under_meta_with_the_module_of_the_project()
  local code, out, _, written, spawned = run({ "generate", "meta" })
  self:assert_equal(0, code)
  self:assert_true(out:find("meta/my_shop.schemas.lua", 1, true) ~= nil, out)
  self:assert_equal("---@meta my_shop.schemas\n", written["meta/my_shop.schemas.lua"])
  local env = spawned[1].options.env
  self:assert_equal("my_shop", env.HECATE_CLI_MODULE)
  self:assert_equal("my_shop.schemas", env.HECATE_CLI_NAMESPACE)
  self:assert_equal("My shop", env.HECATE_CLI_TITLE)
  self:assert_equal("1.2.3", env.HECATE_CLI_VERSION)
  self:assert_equal("-e", spawned[1].args[1])
end

function T:test_namespace_and_output_can_be_given_and_an_existing_output_needs_force()
  local code, _, _, written = run({ "generate", "meta", "--namespace=shop.types", "--output=types.lua" })
  self:assert_equal(0, code)
  self:assert_true(written["types.lua"] ~= nil)
  local code2, _, err = run({ "generate", "meta", "--output=types.lua" }, { existing = "types.lua" })
  self:assert_equal(1, code2)
  self:assert_true(err:find("--force", 1, true) ~= nil, err)
  local code3 = run({ "generate", "meta", "--output=types.lua", "--force" }, { existing = "types.lua" })
  self:assert_equal(0, code3)
  local code4, _, err4 = run({ "generate", "meta", "--namespace=1 bad" })
  self:assert_equal(2, code4)
  self:assert_true(err4:find("--namespace", 1, true) ~= nil, err4)
end

function T:test_a_contract_section_is_required_and_a_failing_child_is_reported()
  local code, _, err = run({ "generate", "meta" }, { manifest = 'return { name = "shop" }' })
  self:assert_true(code ~= 0)
  self:assert_true(err:find("contract", 1, true) ~= nil, err)
  local code2, _, err2 = run({ "generate", "meta" }, { code = 3, stderr = "the module 'my_shop' has no `application(options)` function" })
  self:assert_true(code2 ~= 0)
  self:assert_true(err2:find("application(options)", 1, true) ~= nil, err2)
end

return T
