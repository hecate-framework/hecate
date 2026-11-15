-- Logic of the `validate-openapi` task (ADR 0031): validates the OpenAPI documents the tests produce, and the golden
-- file, against the pinned official OpenAPI 3.1 JSON Schema with the Python `jsonschema` of a development-only virtual
-- environment (`.hecate/venv-openapi`, tools/ci/openapi-validator-requirements.txt). A missing prerequisite (documents,
-- official schema, Python environment) is a skip locally and a failure when CI is `true`. Standard library only.
local util = require("lib.util")

local M = {}

M.SCHEMA_DATE = "2026-11-05" -- the file of the official schema read by tests/unit/conformance_test.lua
M.VENV = ".hecate/venv-openapi"
M.DOCUMENTS = ".hecate/openapi-validate"
M.GOLDEN = "packages/openapi/tests/fixtures/shop.openapi.json"
M.PYTHON_VARIABLE = "HECATE_OPENAPI_VALIDATOR_PYTHON"

M.VENV_COMMANDS = "python3 -m venv .hecate/venv-openapi\n"
  .. ".hecate/venv-openapi/bin/pip install --require-hashes --only-binary :all: --no-deps -r tools/ci/openapi-validator-requirements.txt"

--- The interpreter of the virtual environment (`bin/python`, `Scripts/python.exe` on Windows).
---@param root string
---@return string
function M.venv_python(root)
  return root .. "/" .. M.VENV .. (util.is_windows() and "/Scripts/python.exe" or "/bin/python")
end

--- Sorted `.json` files of the directory of documents written by the tests.
---@param root string
---@return string[]
function M.test_documents(root)
  local dir = root .. "/" .. M.DOCUMENTS
  local files = {}
  for _, name in ipairs(util.list_dir(dir)) do
    if name:match("%.json$") then files[#files + 1] = dir .. "/" .. name end
  end
  return files
end

--- Locates the fetched official schema: the entry of `packages/openapi/tests/external.lua`.
---@param root string
---@return string? schema_path
---@return string resources_dir  the `oas/3.1` directory (dialect, meta, schema, schema-base)
function M.schema_paths(root)
  local chunk = loadfile(root .. "/packages/openapi/tests/external.lua")
  local entry = chunk and chunk()[1]
  if not entry then return nil, "" end
  local base = ("%s/.hecate/fixtures/openapi/%s/%s"):format(root, entry.name, entry.path)
  return base .. "/" .. M.SCHEMA_DATE, (base:gsub("/[^/]*$", ""))
end

--- Runs the validation.
--- `options`: `root`, `ci` (boolean), `getenv` (function, default `os.getenv`), `documents` (list of paths replacing the
--- directory of the tests, for the tests of the task).
---@param options table
---@return table report
function M.run(options)
  local root = options.root
  local getenv = options.getenv or os.getenv
  local ci = options.ci
  if ci == nil then ci = getenv("CI") == "true" end
  -- A prerequisite that is missing: skipped locally, a failure in CI (a green CI always means validated).
  local function missing(message)
    if ci then return { ok = false, problems = { message }, data = { skipped = false } } end
    return { ok = true, problems = {}, data = { skipped = true, reason = message }, output = "skipped: " .. message }
  end

  local documents = options.documents and { table.unpack(options.documents) } or M.test_documents(root)
  if #documents == 0 then
    return missing("no document to validate in " .. M.DOCUMENTS .. ": run the tests that write them first (lua tools/run.lua test openapi)")
  end
  documents[#documents + 1] = root .. "/" .. M.GOLDEN
  if not util.exists(root .. "/" .. M.GOLDEN) then
    return { ok = false, problems = { "the golden document " .. M.GOLDEN .. " is missing" }, data = { skipped = false } }
  end

  local schema, resources = M.schema_paths(root)
  if not schema or not util.exists(schema) then
    return missing("the official OpenAPI 3.1 schema is not downloaded: run lua tools/run.lua fetch-fixtures openapi")
  end

  local python = getenv(M.PYTHON_VARIABLE)
  if python == "" then python = nil end
  python = python or M.venv_python(root)
  local probe = ("%s -I -c %s 2>&1"):format(util.quote(python), util.quote("import jsonschema, referencing, jsonschema_specifications"))
  local _, usable = util.capture(probe)
  if not usable then
    return missing(("the Python environment with jsonschema is not available (%s). Create it with:\n%s\nor set %s to an interpreter that has jsonschema")
      :format(python, M.VENV_COMMANDS, M.PYTHON_VARIABLE))
  end

  local args = { util.quote(python), "-I", util.quote(root .. "/tools/lib/validate_openapi.py"),
    "--resources", util.quote(resources), "--schema", util.quote(schema) }
  -- The wrapper schema validates the Schema Objects with the OpenAPI dialect (the main one accepts any schema there).
  local wrapper = (schema:gsub("/schema/([^/]*)$", "/schema-base/%1"))
  if wrapper ~= schema and util.exists(wrapper) then
    args[#args + 1] = "--schema"
    args[#args + 1] = util.quote(wrapper)
  end
  for _, path in ipairs(documents) do args[#args + 1] = util.quote(path) end
  local out, ok = util.capture(table.concat(args, " ") .. " 2>&1")

  local problems, lines = {}, {}
  for line in out:gmatch("[^\r\n]+") do
    if line:match("^ok ") then lines[#lines + 1] = line else problems[#problems + 1] = line end
  end
  if not ok and #problems == 0 then problems[1] = "the validator failed without a report" end
  if ok and #problems > 0 then problems = {} end
  return { ok = ok and #problems == 0, problems = problems, output = table.concat(lines, "\n"),
    data = { skipped = false, documents = #documents, schema = schema } }
end

return M
