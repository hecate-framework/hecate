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
  self:assert_equal(2, (run("diff", { "contract", "diff", "a" }, deps)))
end

return T
