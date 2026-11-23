local test = require("harness.test")
local app = require("hecate.cli.app")
local contract = require("hecate.cli.commands.contract")
local T = test.Case("CliContractCommandTest")

local runtime = { hecate_version = "0.1.0", lua_version = "5.5.1", platform = "linux-x86_64" }

--- A tiny JSON stand-in: the "documents" of these tests are `ok`, `bad` or a name; decode returns a table.
local function dependencies(files, lint_result, diff_result)
  return {
    read = function(path) return files[path] end,
    decode = function(text)
      if text == "not json" then error("expected a value at position 1", 0) end
      if text == "3" then return 3 end
      return { name = text }
    end,
    lint = function(document) assert(type(document) == "table"); return lint_result or {} end,
    diff = function(old, new) assert(old.name and new.name); return diff_result or {} end,
  }
end

local function run(which, args, deps)
  local out, err = {}, {}
  local wrapped = setmetatable({ run = function(context) return contract[which](context, deps) end }, { __index = contract.commands[which == "lint" and 1 or 2] })
  local code = app.run(args, {
    commands = { wrapped }, runtime = runtime,
    write = function(text) out[#out + 1] = text end,
    write_error = function(text) err[#err + 1] = text end,
    encode_json = function(value) return "json:" .. tostring(value.ok) .. ":" .. #(value.findings or value.changes) end,
  })
  return code, table.concat(out, "\n"), table.concat(err, "\n")
end

local FINDINGS = {
  { rule = "operation-id-missing", severity = "error", path = "GET /users", message = "the operation has no operationId" },
  { rule = "description-missing", severity = "warning", path = "GET /users", message = "no description" },
}

function T:test_lint_lists_findings_and_fails_on_an_error()
  local code, out = run("lint", { "contract", "lint", "a.json" }, dependencies({ ["a.json"] = "doc" }, FINDINGS))
  self:assert_equal(1, code)
  self:assert_true(out:find("error%s+operation%-id%-missing%s+GET /users: the operation has no operationId") ~= nil, out)
  self:assert_true(out:find("1 error(s), 1 warning(s)", 1, true) ~= nil, out)
end

function T:test_warnings_alone_do_not_fail_and_json_is_available()
  local code, out = run("lint", { "contract", "lint", "a.json" }, dependencies({ ["a.json"] = "doc" }, { FINDINGS[2] }))
  self:assert_equal(0, code)
  self:assert_true(out:find("0 error(s), 1 warning(s)", 1, true) ~= nil, out)
  local _, json = run("lint", { "contract", "lint", "a.json", "--json" }, dependencies({ ["a.json"] = "doc" }, { FINDINGS[2] }))
  self:assert_equal("json:true:1", json)
  local clean, text = run("lint", { "contract", "lint", "a.json" }, dependencies({ ["a.json"] = "doc" }))
  self:assert_equal(0, clean)
  self:assert_equal("0 error(s), 0 warning(s)", text)
end

local CHANGES = {
  { kind = "property_removed", breaking = true, path = "GET /users", message = "a response property was removed" },
  { kind = "description_changed", breaking = false, path = "GET /users", message = "the description changed" },
}

function T:test_diff_marks_breaking_changes_and_fails_on_one()
  local files = { ["old.json"] = "old", ["new.json"] = "new" }
  local code, out = run("diff", { "contract", "diff", "old.json", "new.json" }, dependencies(files, nil, CHANGES))
  self:assert_equal(1, code)
  self:assert_true(out:find("BREAKING%s+property_removed%s+GET /users") ~= nil, out)
  self:assert_true(out:find("ok%s+description_changed") ~= nil, out)
  self:assert_true(out:find("2 change(s), 1 breaking", 1, true) ~= nil, out)
  local fine, text = run("diff", { "contract", "diff", "old.json", "new.json" }, dependencies(files, nil, { CHANGES[2] }))
  self:assert_equal(0, fine)
  self:assert_true(text:find("1 change(s), 0 breaking", 1, true) ~= nil, text)
  local same, nothing = run("diff", { "contract", "diff", "old.json", "new.json" }, dependencies(files))
  self:assert_equal(0, same)
  self:assert_equal("No change.", nothing)
end

function T:test_files_that_cannot_be_used_say_so()
  local files = { ["a.json"] = "doc", ["junk.json"] = "not json", ["three.json"] = "3" }
  local function fails(args, which, fragment)
    local code, _, err = run(which, args, dependencies(files))
    self:assert_equal(1, code)
    self:assert_true(err:find(fragment, 1, true) ~= nil, err)
  end
  fails({ "contract", "lint", "missing.json" }, "lint", "missing.json: no such file")
  fails({ "contract", "lint", "junk.json" }, "lint", "junk.json: not valid JSON")
  fails({ "contract", "lint", "three.json" }, "lint", "is a JSON object")
  fails({ "contract", "diff", "a.json", "missing.json" }, "diff", "missing.json: no such file")
end

function T:test_usage_errors()
  local deps = dependencies({})
  self:assert_equal(2, (run("lint", { "contract", "lint" }, deps)))
  self:assert_equal(2, (run("lint", { "contract", "lint", "a", "b" }, deps)))
  self:assert_equal(2, (run("diff", { "contract", "diff" }, deps)))
  self:assert_equal(2, (run("diff", { "contract", "diff", "a", "b", "c" }, deps)))
end


local export_runtime = { hecate_version = "0.1.0", lua_version = "5.5.1", platform = "linux-x86_64", project_dir = "/work/app", lua_interpreter = "/usr/bin/lua5.5" }

local function export_setup(files, result)
  local calls, written = {}, {}
  return calls, written, {
    read = function(path) return files[path] end,
    write = function(path, text) written[path] = text end,
    run = function(task) return task() end,
    run_process = function(program, args, options)
      calls[#calls + 1] = { program = program, args = args, options = options }
      return result or { code = 0, stdout = '{"openapi":"3.1.0"}', stderr = "" }
    end,
    interpreter = "lua",
  }
end

local function run_export(args, dependencies)
  local out, err = {}, {}
  local wrapped = setmetatable({ run = function(context) return contract.export(context, dependencies) end }, { __index = contract.commands[3] })
  local code = app.run(args, {
    commands = { wrapped }, runtime = export_runtime,
    write = function(text) out[#out + 1] = text end,
    write_error = function(text) err[#err + 1] = text end,
  })
  return code, table.concat(out, "\n"), table.concat(err, "\n")
end

local EXPORT_MANIFEST = 'return { name = "acme-api", contract = { title = "ACME API", version = "1.0.0", servers = { "https://api.acme.example", "https://staging.acme.example" } } }'

function T:test_export_runs_the_project_in_a_child_and_prints_the_document()
  local calls, _, dependencies = export_setup({ ["/work/app/hecate.project.lua"] = EXPORT_MANIFEST })
  local code, out = run_export({ "contract", "export", "--pretty" }, dependencies)
  self:assert_equal(0, code)
  self:assert_equal('{"openapi":"3.1.0"}', out)
  self:assert_equal(1, #calls)
  local call = calls[1]
  self:assert_equal("lua", call.program)
  self:assert_equal("-e", call.args[1])
  self:assert_equal(contract.CHILD_PROGRAM, call.args[2])
  self:assert_equal("/work/app", call.options.cwd)
  local env = call.options.env
  self:assert_equal("acme_api", env.HECATE_CLI_MODULE)
  self:assert_equal("ACME API", env.HECATE_CLI_TITLE)
  self:assert_equal("1.0.0", env.HECATE_CLI_VERSION)
  self:assert_equal("https://api.acme.example\31https://staging.acme.example", env.HECATE_CLI_SERVERS)
  self:assert_equal("1", env.HECATE_CLI_PRETTY)
  self:assert_true(env.LUA_PATH:find("/work/app/lua_modules/share/lua/5.5/?.lua", 1, true) ~= nil)
  local plain_calls, _, plain_dependencies = export_setup({ ["/work/app/hecate.project.lua"] = EXPORT_MANIFEST })
  run_export({ "contract", "export" }, plain_dependencies)
  self:assert_equal("0", plain_calls[1].options.env.HECATE_CLI_PRETTY)
end

function T:test_export_can_write_a_file()
  local _, written, dependencies = export_setup({ ["/work/app/hecate.project.lua"] = EXPORT_MANIFEST })
  local code, out, err = run_export({ "contract", "export", "--output=openapi.json" }, dependencies)
  self:assert_equal(0, code)
  self:assert_equal("", out)
  self:assert_equal('{"openapi":"3.1.0"}', written["/work/app/openapi.json"])
  self:assert_true(err:find("wrote 19 bytes to openapi.json", 1, true) ~= nil, err)
end

function T:test_export_failures_say_what_to_do()
  local function fails(files, result, fragment, args)
    local _, written, dependencies = export_setup(files, result)
    local code, _, err = run_export(args or { "contract", "export" }, dependencies)
    self:assert_equal(1, code)
    self:assert_true(err:find(fragment, 1, true) ~= nil, err)
    self:assert_nil(next(written))
  end
  fails({}, nil, "hecate new")
  fails({ ["/work/app/hecate.project.lua"] = 'return { name = "acme-api" }' }, nil, "has no `contract` section")
  fails({ ["/work/app/hecate.project.lua"] = EXPORT_MANIFEST }, { code = 3, stdout = "", stderr = "cannot load the module 'acme_api' of the project: boom\n" },
    "cannot load the module 'acme_api' of the project: boom", { "contract", "export", "--output=x.json" })
  fails({ ["/work/app/hecate.project.lua"] = EXPORT_MANIFEST }, { code = 1, stdout = "", stderr = "" }, "the process exited with 1")
  local _, _, dependencies = export_setup({})
  self:assert_equal(2, (run_export({ "contract", "export", "extra" }, dependencies)))
end


--- Dependencies for `diff <ref>`: `git` answers `git_output` (or fails), the interpreter prints the contract now.
local function ref_setup(git_result, now)
  local calls = {}
  local files = { ["/work/app/hecate.project.lua"] = EXPORT_MANIFEST }
  return calls, {
    read = function(path) return files[path] end,
    write = function() end,
    run = function(task) return task() end,
    run_process = function(program, args, options)
      calls[#calls + 1] = { program = program, args = args, options = options }
      if program == "git" then return git_result end
      return { code = 0, stdout = now or "now", stderr = "" }
    end,
    interpreter = "lua",
    decode = function(text)
      if text == "not json" then error("expected a value", 0) end
      return { name = text }
    end,
    diff = function(old, new) return { { kind = "property_removed", breaking = old.name ~= new.name, path = "GET /x", message = old.name .. " -> " .. new.name } } end,
  }
end

local function run_diff(args, dependencies)
  local out, err = {}, {}
  local wrapped = setmetatable({ run = function(context) return contract.diff(context, dependencies) end }, { __index = contract.commands[2] })
  local code = app.run(args, {
    commands = { wrapped }, runtime = export_runtime,
    write = function(text) out[#out + 1] = text end,
    write_error = function(text) err[#err + 1] = text end,
  })
  return code, table.concat(out, "\n"), table.concat(err, "\n")
end

function T:test_diff_with_a_ref_compares_the_committed_contract_with_the_application_now()
  local calls, dependencies = ref_setup({ code = 0, stdout = "before", stderr = "" }, "after")
  local code, out, err = run_diff({ "contract", "diff", "origin/main" }, dependencies)
  self:assert_equal(1, code)   -- the fake reports a breaking change when the two differ
  self:assert_true(out:find("BREAKING%s+property_removed%s+GET /x: before %-> after") ~= nil, out)
  self:assert_true(err:find("origin/main:openapi.json against the application now", 1, true) ~= nil, err)
  self:assert_equal("git", calls[1].program)
  self:assert_equal("show,origin/main:openapi.json", table.concat(calls[1].args, ","))
  self:assert_equal("/work/app", calls[1].options.cwd)
  self:assert_equal("lua", calls[2].program)
  local same_calls, same = ref_setup({ code = 0, stdout = "same", stderr = "" }, "same")
  self:assert_equal(0, (run_diff({ "contract", "diff", "v1.0", "--file=docs/openapi.json" }, same)))
  self:assert_equal("show,v1.0:docs/openapi.json", table.concat(same_calls[1].args, ","))
end

function T:test_a_ref_that_cannot_be_used_is_refused_before_git_runs()
  for _, ref in ipairs({ "--output=x", "-x", "a b", "a:b" }) do
    local calls, dependencies = ref_setup({ code = 0, stdout = "", stderr = "" })
    local code, _, err = run_diff({ "contract", "diff", "--", ref }, dependencies)
    self:assert_equal(2, code, ref)
    self:assert_true(err:find("not a git ref", 1, true) ~= nil, err)
    self:assert_equal(0, #calls)
  end
  local calls, dependencies = ref_setup({ code = 0, stdout = "", stderr = "" })
  local code, _, err = run_diff({ "contract", "diff", "main", "--file=../x.json" }, dependencies)
  self:assert_equal(2, code)
  self:assert_true(err:find("inside the project", 1, true) ~= nil, err)
  self:assert_equal(0, #calls)
end

function T:test_a_ref_without_a_committed_contract_says_how_to_commit_one()
  local _, dependencies = ref_setup({ code = 128, stdout = "", stderr = "fatal: path 'openapi.json' does not exist in 'main'\n" })
  local code, _, err = run_diff({ "contract", "diff", "main" }, dependencies)
  self:assert_equal(1, code)
  self:assert_true(err:find("hecate contract export --output=openapi.json", 1, true) ~= nil, err)
  self:assert_true(err:find("does not exist in 'main'", 1, true) ~= nil, err)
  local _, junk = ref_setup({ code = 0, stdout = "not json", stderr = "" })
  local bad, _, err2 = run_diff({ "contract", "diff", "main" }, junk)
  self:assert_equal(1, bad)
  self:assert_true(err2:find("main:openapi.json is not a JSON OpenAPI document", 1, true) ~= nil, err2)
end

function T:test_the_executable_exports_the_contract_in_interpreter_mode()
  local calls, _, dependencies = export_setup({ ["/work/app/hecate.project.lua"] = EXPORT_MANIFEST })
  dependencies.interpreter_arguments = { "--lua" }
  run_export({ "contract", "export" }, dependencies)
  self:assert_equal("--lua", calls[1].args[1])
  self:assert_equal("-e", calls[1].args[2])
  self:assert_equal(contract.CHILD_PROGRAM, calls[1].args[3])
end

return T
