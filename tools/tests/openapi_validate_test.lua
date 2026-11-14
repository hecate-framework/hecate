local test = require("harness.test")
local util = require("lib.util")
local openapi_validate = require("lib.openapi_validate")
local T = test.Case("OpenApiValidateTest")

local function remove_tree(path)
  if util.is_windows() then os.execute(('rmdir /s /q "%s" >nul 2>&1'):format(path:gsub("/", "\\")))
  else os.execute("rm -rf " .. util.quote(path)) end
end

local function write(path, text)
  local file = assert(io.open(path, "wb"))
  file:write(text)
  file:close()
end

-- A scratch repository: the golden file, the official schema entry and (optionally) the documents of the tests.
local function scratch(options)
  options = options or {}
  local root = (os.tmpname() .. "-root"):gsub("\\", "/")
  util.mkdir(root .. "/packages/openapi/tests/fixtures")
  write(root .. "/packages/openapi/tests/external.lua",
    'return { { name = "spec.openapis.org", repository = "x", commit = "y", path = "oas/3.1/schema" } }')
  write(root .. "/" .. openapi_validate.GOLDEN, "{}")
  if options.documents ~= false then
    util.mkdir(root .. "/" .. openapi_validate.DOCUMENTS)
    write(root .. "/" .. openapi_validate.DOCUMENTS .. "/a.json", "{}")
  end
  if options.schema ~= false then
    local dir = root .. "/.hecate/fixtures/openapi/spec.openapis.org/oas/3.1/schema"
    util.mkdir(dir)
    write(dir .. "/" .. openapi_validate.SCHEMA_DATE, "{}")
  end
  return root
end

local function cleanup(root)
  remove_tree(root)
  os.remove((root:gsub("-root$", "")))
end

local function env(values) return function(name) return values[name] end end

--- A fake interpreter (POSIX shell): succeeds on the import probe, then prints `report` and exits with `code`.
local function fake_python(root, report, code)
  local path = root .. "/fake-python"
  write(path, ('#!/bin/sh\nif [ "$2" = "-c" ]; then exit 0; fi\ncat <<\'EOF\'\n%s\nEOF\nexit %d\n'):format(report, code))
  os.execute("chmod +x " .. util.quote(path))
  return path
end

function T:test_no_document_directory_skips_locally_and_fails_in_ci()
  local root = scratch { documents = false }
  local local_report = openapi_validate.run { root = root, ci = false, getenv = env {} }
  self:assert_true(local_report.ok)
  self:assert_true(local_report.data.skipped)
  self:assert_true(local_report.output:find("lua tools/run.lua test openapi", 1, true) ~= nil)
  local ci_report = openapi_validate.run { root = root, ci = true, getenv = env {} }
  self:assert_false(ci_report.ok)
  self:assert_true(ci_report.problems[1]:find("test openapi", 1, true) ~= nil)
  cleanup(root)
end

function T:test_an_empty_document_directory_counts_as_no_document()
  local root = scratch { documents = false }
  util.mkdir(root .. "/" .. openapi_validate.DOCUMENTS)
  self:assert_false(openapi_validate.run({ root = root, ci = true, getenv = env {} }).ok)
  cleanup(root)
end

function T:test_an_absent_schema_fixture_skips_locally_and_fails_in_ci()
  local root = scratch { schema = false }
  local local_report = openapi_validate.run { root = root, ci = false, getenv = env {} }
  self:assert_true(local_report.ok)
  self:assert_true(local_report.data.skipped)
  self:assert_true(local_report.output:find("fetch-fixtures openapi", 1, true) ~= nil)
  local ci_report = openapi_validate.run { root = root, ci = true, getenv = env {} }
  self:assert_false(ci_report.ok)
  self:assert_true(ci_report.problems[1]:find("fetch-fixtures openapi", 1, true) ~= nil)
  cleanup(root)
end

function T:test_an_absent_environment_skips_locally_and_fails_in_ci()
  local root = scratch()
  local local_report = openapi_validate.run { root = root, ci = false, getenv = env {} }
  self:assert_true(local_report.ok)
  self:assert_true(local_report.data.skipped)
  self:assert_true(local_report.output:find("python3 -m venv .hecate/venv-openapi", 1, true) ~= nil)
  self:assert_true(local_report.output:find("--require-hashes --only-binary :all: --no-deps -r tools/ci/openapi-validator-requirements.txt", 1, true) ~= nil)
  local ci_report = openapi_validate.run { root = root, ci = true, getenv = env {} }
  self:assert_false(ci_report.ok)
  self:assert_true(ci_report.problems[1]:find("venv-openapi", 1, true) ~= nil)
  cleanup(root)
end

function T:test_the_ci_variable_decides_when_ci_is_not_given()
  local root = scratch { documents = false }
  self:assert_true(openapi_validate.run({ root = root, getenv = env { CI = "false" } }).ok)
  self:assert_false(openapi_validate.run({ root = root, getenv = env { CI = "true" } }).ok)
  cleanup(root)
end

function T:test_an_interpreter_without_jsonschema_is_an_absent_environment()
  if util.is_windows() then return end
  local root = scratch()
  write(root .. "/no-jsonschema", "#!/bin/sh\nexit 1\n")
  os.execute("chmod +x " .. util.quote(root .. "/no-jsonschema"))
  local getenv = env { [openapi_validate.PYTHON_VARIABLE] = root .. "/no-jsonschema" }
  self:assert_true(openapi_validate.run({ root = root, ci = false, getenv = getenv }).data.skipped)
  self:assert_false(openapi_validate.run({ root = root, ci = true, getenv = getenv }).ok)
  cleanup(root)
end

function T:test_the_environment_variable_names_the_interpreter_and_a_valid_report_passes()
  if util.is_windows() then return end
  local root = scratch()
  local python = fake_python(root, "ok a.json [schema/2026-11-05]\nok shop.openapi.json [schema/2026-11-05]", 0)
  local report = openapi_validate.run { root = root, ci = true, getenv = env { [openapi_validate.PYTHON_VARIABLE] = python } }
  self:assert_true(report.ok)
  self:assert_equal(0, #report.problems)
  self:assert_equal(2, report.data.documents)
  self:assert_true(report.output:find("ok a.json", 1, true) ~= nil)
  cleanup(root)
end

function T:test_an_invalid_document_is_rejected_with_its_errors()
  if util.is_windows() then return end
  local root = scratch()
  local python = fake_python(root, "invalid a.json [schema/2026-11-05]: 1 error(s)\n  /info: 'title' is a required property", 1)
  local report = openapi_validate.run { root = root, ci = false, getenv = env { [openapi_validate.PYTHON_VARIABLE] = python } }
  self:assert_false(report.ok)
  self:assert_equal(2, #report.problems)
  self:assert_true(report.problems[2]:find("/info", 1, true) ~= nil)
  cleanup(root)
end

function T:test_a_failure_without_a_report_is_still_a_failure()
  if util.is_windows() then return end
  local root = scratch()
  local python = fake_python(root, "", 1)
  local report = openapi_validate.run { root = root, ci = false, getenv = env { [openapi_validate.PYTHON_VARIABLE] = python } }
  self:assert_false(report.ok)
  self:assert_equal(1, #report.problems)
  cleanup(root)
end

function T:test_the_virtual_environment_interpreter_path_depends_on_the_platform()
  local path = openapi_validate.venv_python("/r")
  self:assert_equal(util.is_windows() and "/r/.hecate/venv-openapi/Scripts/python.exe" or "/r/.hecate/venv-openapi/bin/python", path)
end

--- The real validator, only when the environment and the official schema exist here (never required).
function T:test_the_real_validator_accepts_a_good_document_and_rejects_a_broken_one()
  local repository = (debug.getinfo(1, "S").source:match("^@(.*)[/\\]tools[/\\]tests[/\\][^/\\]*$") or "."):gsub("\\", "/")
  local schema = openapi_validate.schema_paths(repository)
  local python = openapi_validate.venv_python(repository)
  if not (schema and util.exists(schema) and util.exists(python)) then return end
  local golden = assert(io.open(repository .. "/" .. openapi_validate.GOLDEN, "rb"))
  local good = golden:read("a")
  golden:close()
  local directory = (os.tmpname() .. "-docs"):gsub("\\", "/")
  util.mkdir(directory)
  write(directory .. "/good.json", good)
  write(directory .. "/bad.json", (good:gsub('"3%.1%.%d+"', '"3.0.3"', 1)))
  local getenv = env { [openapi_validate.PYTHON_VARIABLE] = python }
  local accepted = openapi_validate.run { root = repository, ci = true, getenv = getenv, documents = { directory .. "/good.json" } }
  self:assert_true(accepted.ok, table.concat(accepted.problems, "\n"))
  local rejected = openapi_validate.run { root = repository, ci = true, getenv = getenv, documents = { directory .. "/bad.json" } }
  self:assert_false(rejected.ok)
  local text = table.concat(rejected.problems, "\n")
  self:assert_true(text:find("invalid bad.json", 1, true) ~= nil, text)
  self:assert_true(text:find("/openapi: ", 1, true) ~= nil, text)
  remove_tree(directory)
  os.remove((directory:gsub("-docs$", "")))
end

return T
