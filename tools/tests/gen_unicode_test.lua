---@diagnostic disable: need-check-nil, param-type-mismatch, undefined-field
local test = require("harness.test")
local task = require("tasks.gen_unicode")
local sha256 = require("lib.sha256")
local util = require("lib.util")
local T = test.Case("GenUnicodeTaskTest")

local ROOT = ((debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or ".") .. "/../.."):gsub("\\", "/")
local OUT = "packages/unicode-data/src/hecate/unicode_data"
local FILES = { "init.lua", "combining_class.lua", "decomposition.lua", "composition.lua" }

local UNICODE_DATA = table.concat({
  "0041;LATIN CAPITAL LETTER A;Lu;0;L;;;;;N;;;;0061;",
  "0300;COMBINING GRAVE ACCENT;Mn;230;NSM;;;;;N;NON-SPACING GRAVE;;;;",
  "0323;COMBINING DOT BELOW;Mn;220;NSM;;;;;N;NON-SPACING DOT BELOW;;;;",
  "00C0;LATIN CAPITAL LETTER A WITH GRAVE;Lu;0;L;0041 0300;;;;N;LATIN CAPITAL LETTER A GRAVE;;;00E0;",
  "1EA0;LATIN CAPITAL LETTER A WITH DOT BELOW;Lu;0;L;0041 0323;;;;N;;;;1EA1;",
  "2126;OHM SIGN;Lu;0;L;03A9;;;;N;OHM;;;03C9;",
}, "\n") .. "\n"
local PROPERTIES = "# comment\n2126          ; Full_Composition_Exclusion # L&       OHM SIGN\n"

local function write(path, data)
  local f = assert(io.open(path, "wb"))
  f:write(data)
  f:close()
end
local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local d = f:read("a")
  f:close()
  return d
end

-- A root of its own: the external.lua of the package, the downloaded inputs and the output directory.
function T:set_up()
  self.root = assert(util.make_temp_dir(ROOT .. "/.hecate/tmp", "gen-unicode-test"))
  util.mkdir(self.root .. "/packages/unicode-data/tests")
  util.mkdir(self.root .. "/.hecate/fixtures/unicode-data")
end

function T:tear_down() util.remove_tree(self.root) end

-- Declares the inputs (`versions` per file) and downloads (writes) them.
function T:declare(versions, texts)
  versions = versions or { "18.0.0", "18.0.0" }
  texts = texts or { UNICODE_DATA, PROPERTIES }
  local names = { "UnicodeData.txt", "DerivedNormalizationProps.txt" }
  local lines = { "return {" }
  for i, name in ipairs(names) do
    lines[#lines + 1] = ("  { name = %q, url = %q, sha256 = %q },"):format(name,
      ("https://www.unicode.org/Public/%s/ucd/%s"):format(versions[i], name), sha256.hex(texts[i]))
    write(self.root .. "/.hecate/fixtures/unicode-data/" .. name, texts[i])
  end
  lines[#lines + 1] = "}"
  write(self.root .. "/packages/unicode-data/tests/external.lua", table.concat(lines, "\n") .. "\n")
end

function T:run(...) return task.run({ root = self.root, args = { ... } }) end

function T:contents()
  local out = {}
  for _, name in ipairs(FILES) do out[name] = read(("%s/%s/%s"):format(self.root, OUT, name)) end
  return out
end

function T:test_a_run_writes_deterministic_files_and_a_second_run_writes_none()
  self:declare()
  local first = self:run()
  self:assert_true(first.ok, table.concat(first.problems, "; "))
  self:assert_equal("18.0.0", first.data.version)
  self:assert_equal(4, #first.data.written)
  self:assert_equal(4, first.data.count)
  local before = self:contents()
  for _, name in ipairs(FILES) do
    self:assert_not_nil(before[name], name)
    self:assert_true(before[name]:find("^%-%- GENERATED") ~= nil, name)
  end
  self:assert_true(before["decomposition.lua"]:find("[0x00C0] = { 0x0041, 0x0300 },", 1, true) ~= nil)
  local second = self:run()
  self:assert_true(second.ok, table.concat(second.problems, "; "))
  self:assert_equal(0, #second.data.written, "an up-to-date directory is not rewritten")
  local after = self:contents()
  for _, name in ipairs(FILES) do self:assert_equal(before[name], after[name], name) end
  local check = self:run("--check")
  self:assert_true(check.ok, table.concat(check.problems, "; "))
end

function T:test_the_files_of_another_root_with_the_same_inputs_are_identical()
  self:declare()
  self:assert_true(self:run().ok)
  local one = self:contents()
  util.remove_tree(self.root .. "/" .. OUT)
  self:assert_true(self:run().ok)
  local two = self:contents()
  for _, name in ipairs(FILES) do self:assert_equal(one[name], two[name], name) end
end

function T:test_check_fails_on_a_modified_committed_table_and_writes_nothing()
  self:declare()
  self:assert_true(self:run().ok)
  local path = ("%s/%s/composition.lua"):format(self.root, OUT)
  local edited = read(path) .. "-- hand edit\n"
  write(path, edited)
  local before = self:contents()
  local report = self:run("--check")
  self:assert_false(report.ok)
  self:assert_equal("composition.lua", report.data.stale[1])
  self:assert_equal(1, #report.data.stale)
  self:assert_true(report.problems[1]:find("composition.lua", 1, true) ~= nil)
  self:assert_true(report.problems[1]:find("gen-unicode", 1, true) ~= nil)
  local after = self:contents()
  for _, name in ipairs(FILES) do self:assert_equal(before[name], after[name], name .. " is untouched by --check") end
  self:assert_equal(edited, read(path))
  -- Without --check the same state is repaired.
  self:assert_true(self:run().ok)
  self:assert_true(read(path):find("hand edit", 1, true) == nil)
end

function T:test_check_without_any_committed_table_fails_and_creates_nothing()
  self:declare()
  local report = self:run("--check")
  self:assert_false(report.ok)
  self:assert_equal(4, #report.data.stale)
  self:assert_false(util.exists(self.root .. "/" .. OUT))
end

function T:test_a_tampered_input_fails_and_names_fetch_fixtures()
  self:declare()
  write(self.root .. "/.hecate/fixtures/unicode-data/UnicodeData.txt", UNICODE_DATA .. "0042;B;Lu;0;L;;;;;N;;;;;\n")
  local report = self:run()
  self:assert_false(report.ok)
  self:assert_equal(1, #report.problems)
  self:assert_true(report.problems[1]:find("UnicodeData.txt: sha256 differs from the pin", 1, true) ~= nil, report.problems[1])
  self:assert_true(report.problems[1]:find("fetch-fixtures unicode-data", 1, true) ~= nil)
  self:assert_false(util.exists(self.root .. "/" .. OUT), "nothing is generated from a tampered input")
end

function T:test_a_missing_input_fails_and_names_fetch_fixtures()
  self:declare()
  os.remove(self.root .. "/.hecate/fixtures/unicode-data/DerivedNormalizationProps.txt")
  local report = self:run()
  self:assert_false(report.ok)
  self:assert_true(report.problems[1]:find("DerivedNormalizationProps.txt: not downloaded", 1, true) ~= nil, report.problems[1])
  self:assert_true(report.problems[1]:find("fetch-fixtures unicode-data", 1, true) ~= nil)
  self:assert_false(util.exists(self.root .. "/" .. OUT))
end

function T:test_inputs_of_different_unicode_versions_fail()
  self:declare({ "18.0.0", "17.0.0" })
  local report = self:run()
  self:assert_false(report.ok)
  self:assert_true(report.problems[1]:find("version 17.0.0, the other inputs are 18.0.0", 1, true) ~= nil, report.problems[1])
  self:assert_false(util.exists(self.root .. "/" .. OUT))
end

function T:test_a_url_without_a_unicode_version_fails()
  self:declare({ "latest", "18.0.0" })
  local report = self:run()
  self:assert_false(report.ok)
  self:assert_true(report.problems[1]:find("does not name a Unicode version", 1, true) ~= nil, report.problems[1])
end

function T:test_a_missing_external_lua_fails()
  local report = self:run()
  self:assert_false(report.ok)
  self:assert_true(report.problems[1]:find("external.lua is missing", 1, true) ~= nil)
end

function T:test_inputs_that_cannot_be_built_fail_with_the_reason()
  local cyclic = "0041;A;Lu;0;L;0042;;;;N;;;;;\n0042;B;Lu;0;L;0041;;;;N;;;;;\n"
  self:declare(nil, { cyclic, PROPERTIES })
  local report = self:run()
  self:assert_false(report.ok)
  self:assert_true(report.problems[1]:find("does not end", 1, true) ~= nil, report.problems[1])
  self:assert_false(util.exists(self.root .. "/" .. OUT))
end

function T:test_an_unknown_argument_is_a_usage_error()
  self:declare()
  for _, args in ipairs({ { "--bogus" }, { "--check", "extra" }, { "check" } }) do
    local report = self:run(table.unpack(args))
    self:assert_false(report.ok)
    self:assert_true(report.problems[1]:find("usage: gen-unicode [--check]", 1, true) ~= nil, report.problems[1])
  end
  self:assert_false(util.exists(self.root .. "/" .. OUT))
end

return T
