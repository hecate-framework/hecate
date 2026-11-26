local test = require("harness.test")
local app = require("hecate.cli.app")
local package_command = require("hecate.cli.commands.package")
local T = test.Case("CliPackageCommandTest")
local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or "."
local nested = dofile(here .. "/../support/nested_guard.lua")

local MANIFEST = 'return { name = "shop", version = "0.2.0" }'

local function run(args, opts)
  opts = opts or {}
  local written, removed, spawned = {}, {}, {}
  local present = opts.present or { ["/work/shop/hecate.project.lua"] = MANIFEST, ["/work/shop/hecate.lock"] = true,
    ["/work/shop/main.lua"] = true, ["/work/shop/src"] = true, ["/work/shop/lua_modules"] = true, ["/work/shop/config"] = true }
  local dependencies = {
    fs = {
      read = function(path) local value = present[path]; return type(value) == "string" and value or nil end,
      exists = function(path) return present[path] ~= nil end,
      write = function(path, text) written[path] = text end,
      remove = function(path) removed[#removed + 1] = path end,
    },
    run = nested.run,
    run_process = function(program, process_args, options)
      spawned[#spawned + 1] = { program = program, args = process_args, options = options }
      return { code = opts.code or 0, stdout = "", stderr = opts.stderr or "" }
    end,
    sha256_file = function() return string.rep("ab", 32) end,
    tar = "tar",
    windows = opts.windows == true,
  }
  local out, err = {}, {}
  local command = setmetatable({ run = function(context) return package_command.execute(context, dependencies) end }, { __index = package_command })
  local code = app.run(args, {
    commands = { command },
    runtime = { hecate_version = "0.1.0", lua_version = "5.5.1", platform = "linux-x86_64", project_dir = "/work/shop" },
    write = function(text) out[#out + 1] = text end,
    write_error = function(text) err[#err + 1] = text end,
  })
  return code, table.concat(out, "\n"), table.concat(err, "\n"), written, removed, spawned
end

function T:test_the_archive_holds_the_content_and_a_release_file_and_a_checksum_goes_next_to_it()
  local code, out, _, written, removed, spawned = run({ "package" })
  self:assert_equal(0, code)
  self:assert_true(out:find("shop-0.2.0-linux-x86_64.tar.gz", 1, true) ~= nil, out)
  self:assert_equal("tar", spawned[1].program)
  self:assert_equal("-z -c -f /work/shop/shop-0.2.0-linux-x86_64.tar.gz -C /work/shop RELEASE hecate.project.lua hecate.lock main.lua src config lua_modules",
    table.concat(spawned[1].args, " "))
  self:assert_true(written["/work/shop/RELEASE"]:find("version = 0.2.0", 1, true) ~= nil)
  self:assert_true(written["/work/shop/RELEASE"]:find("platform = linux-x86_64", 1, true) ~= nil)
  self:assert_equal("/work/shop/RELEASE", removed[1])
  self:assert_equal(string.rep("ab", 32) .. "  shop-0.2.0-linux-x86_64.tar.gz\n", written["/work/shop/shop-0.2.0-linux-x86_64.tar.gz.sha256"])
end

function T:test_config_is_optional_and_a_zip_is_written_on_windows()
  local present = { ["/work/shop/hecate.project.lua"] = MANIFEST, ["/work/shop/hecate.lock"] = true, ["/work/shop/main.lua"] = true,
    ["/work/shop/src"] = true, ["/work/shop/lua_modules"] = true, tar = true }
  local code, _, _, _, _, spawned = run({ "package", "--output=/out/r.zip" }, { present = present, windows = true })
  self:assert_equal(0, code)
  self:assert_equal("-a -c -f /out/r.zip -C /work/shop RELEASE hecate.project.lua hecate.lock main.lua src lua_modules", table.concat(spawned[1].args, " "))
end

function T:test_an_output_with_a_colon_cannot_be_read_as_a_remote_file_by_tar()
  local code, _, _, _, _, spawned = run({ "package", "--output=host:evil.tar.gz" })
  self:assert_equal(0, code)
  self:assert_equal("./host:evil.tar.gz", spawned[1].args[4])
  local _, _, _, _, _, absolute = run({ "package", "--output=/tmp/a:b.tar.gz" })
  self:assert_equal("/tmp/a:b.tar.gz", absolute[1].args[4])
end

function T:test_the_suffix_of_the_output_names_the_format()
  local code, _, err, _, _, spawned = run({ "package", "--output=/out/r.zip" })
  self:assert_equal(2, code)
  self:assert_true(err:find(".tar.gz", 1, true) ~= nil, err)
  self:assert_equal(0, #spawned)
  self:assert_equal(2, (run({ "package", "--output=/out/release" })))
  self:assert_equal(0, (run({ "package", "--output=/out/r.tgz" })))
end

function T:test_a_missing_tar_on_windows_is_explained_and_macos_metadata_is_not_archived()
  local present = { ["/work/shop/hecate.project.lua"] = MANIFEST, ["/work/shop/hecate.lock"] = true, ["/work/shop/main.lua"] = true,
    ["/work/shop/src"] = true, ["/work/shop/lua_modules"] = true }
  local code, _, err, _, _, spawned = run({ "package", "--output=/out/r.zip" }, { present = present, windows = true })
  self:assert_equal(1, code)
  self:assert_true(err:find("tar was not found", 1, true) ~= nil, err)
  self:assert_equal(0, #spawned)
  local _, _, _, _, _, ok = run({ "package" })
  self:assert_equal("1", ok[1].options.env.COPYFILE_DISABLE)
end

function T:test_a_missing_lock_or_tree_is_refused_with_the_command_that_fixes_it()
  local present = { ["/work/shop/hecate.project.lua"] = MANIFEST, ["/work/shop/main.lua"] = true, ["/work/shop/src"] = true }
  local code, _, err = run({ "package" }, { present = present })
  self:assert_equal(1, code)
  self:assert_true(err:find("hecate install", 1, true) ~= nil, err)
  present["/work/shop/hecate.lock"] = true
  local code2, _, err2 = run({ "package" }, { present = present })
  self:assert_equal(1, code2)
  self:assert_true(err2:find("install --frozen", 1, true) ~= nil, err2)
end

function T:test_a_failing_tar_is_reported_and_release_is_removed_anyway()
  local code, _, err, _, removed = run({ "package" }, { code = 2, stderr = "tar: boom" })
  self:assert_equal(1, code)
  self:assert_true(err:find("tar: boom", 1, true) ~= nil, err)
  self:assert_equal("/work/shop/RELEASE", removed[1])
end

return T
