local test = require("harness.test")
local app = require("hecate.cli.app")
local doctor = require("hecate.cli.doctor")
local command = require("hecate.cli.commands.doctor")
local T = test.Case("CliDoctorTest")

local GOOD = { hecate_version = "0.1.0", lua_version = "5.5.1", luarocks_version = "3.13.0", libuv_version = "1.53.0", platform = "linux-x86_64" }

local function probes(overrides)
  local value = {
    json_works = function() return true end,
    on_path = function(program) return program == "cc" end,
    read = function() return nil end,
    digest_backend = function() return "digest" end,
  }
  for key, fn in pairs(overrides or {}) do value[key] = fn end
  return value
end

local function statuses(checks)
  local list = {}
  for _, entry in ipairs(checks) do list[entry.name] = entry.status end
  return list
end

function T:test_a_fit_environment_has_no_problem_and_no_warning()
  local checks = doctor.run(GOOD, probes())
  local code, failures, warnings = doctor.summary(checks)
  self:assert_equal(0, code)
  self:assert_equal(0, failures)
  self:assert_equal(0, warnings)
  self:assert_equal("ok", statuses(checks)["Lua"])
end

function T:test_luarocks_says_whether_it_is_the_embedded_one()
  local embedded = { hecate_version = "0.1.0", lua_version = "5.5.1", luarocks_version = "3.13.0", libuv_version = "1.53.0", platform = "linux-x86_64", luarocks_program = "/opt/hecate" }
  local function detail(runtime)
    for _, entry in ipairs(doctor.run(runtime, probes())) do
      if entry.name == "LuaRocks" then return entry.detail end
    end
  end
  self:assert_equal("3.13.0 (embedded in the executable)", detail(embedded))
  self:assert_equal("3.13.0", detail(GOOD))
end

function T:test_each_problem_says_what_to_do()
  local runtime = { hecate_version = "0.1.0", lua_version = "5.4.7", platform = "linux-x86_64" }
  local checks = doctor.run(runtime, probes({ digest_backend = function() return nil end }))
  local by_name = statuses(checks)
  self:assert_equal("fail", by_name["Lua"])
  self:assert_equal("fail", by_name["LuaRocks"])
  self:assert_equal("fail", by_name["libuv (luv)"])
  self:assert_equal("fail", by_name["SHA-256"])
  for _, entry in ipairs(checks) do
    if entry.status ~= "ok" then self:assert_true(entry.fix ~= nil and #entry.fix > 0, entry.name .. " has no fix") end
  end
  self:assert_equal(1, (doctor.summary(checks)))
end

function T:test_warnings_do_not_fail_the_command()
  local checks = doctor.run(GOOD, probes({
    json_works = function() return false, "module 'hecate.json.native' not found\nstack" end,
    on_path = function() return false end,
  }))
  local code, failures, warnings = doctor.summary(checks)
  self:assert_equal(0, code)
  self:assert_equal(0, failures)
  self:assert_equal(2, warnings)
  for _, entry in ipairs(checks) do
    if entry.name == "hecate.json" then self:assert_true(entry.detail:find("hecate.json.native", 1, true) ~= nil and entry.detail:find("stack", 1, true) == nil) end
  end
end

function T:test_the_project_is_checked_when_there_is_a_manifest()
  local none = doctor.run(GOOD, probes())
  self:assert_nil(statuses(none)["hecate.project.lua"])
  local broken = statuses(doctor.run(GOOD, probes(), { manifest_error = "bad", has_lock = false }))
  self:assert_equal("fail", broken["hecate.project.lua"])
  self:assert_nil(broken["hecate.lock"])
  local unlocked = statuses(doctor.run(GOOD, probes(), { has_lock = false }))
  self:assert_equal("ok", unlocked["hecate.project.lua"])
  self:assert_equal("warn", unlocked["hecate.lock"])
  self:assert_equal("ok", statuses(doctor.run(GOOD, probes(), { has_lock = true }))["hecate.lock"])
end

local function run(args, rt, overrides)
  local out, err = {}, {}
  local wrapped = setmetatable({ run = function(context) return command.execute(context, probes(overrides)) end }, { __index = command })
  local code = app.run(args, {
    commands = { wrapped }, runtime = rt or GOOD,
    write = function(text) out[#out + 1] = text end,
    write_error = function(text) err[#err + 1] = text end,
    encode_json = function(value) return "json:" .. tostring(value.ok) .. ":" .. #value.checks end,
  })
  return code, table.concat(out, "\n")
end

function T:test_the_command_prints_a_line_per_check_and_a_summary()
  local code, out = run({ "doctor" })
  self:assert_equal(0, code)
  self:assert_true(out:find("%[ok  %] Lua%s+5.5.1") ~= nil, out)
  self:assert_true(out:find("The environment is fit.", 1, true) ~= nil, out)
  local failed, text = run({ "doctor" }, { hecate_version = "0.1.0", lua_version = "5.5.1", platform = "x" })
  self:assert_equal(1, failed)
  self:assert_true(text:find("%[FAIL%] LuaRocks") ~= nil and text:find("-> install LuaRocks 3.x", 1, true) ~= nil, text)
  self:assert_true(text:find("Fix the problems above.", 1, true) ~= nil, text)
  local _, json = run({ "doctor", "--json" })
  self:assert_equal("json:true:6", json)
end

function T:test_a_manifest_that_does_not_parse_is_reported()
  local code, out = run({ "doctor" }, GOOD, { read = function(path) return path == "hecate.project.lua" and "return {" or nil end })
  self:assert_equal(1, code)
  self:assert_true(out:find("[FAIL] hecate.project.lua", 1, true) ~= nil, out)
end

return T
