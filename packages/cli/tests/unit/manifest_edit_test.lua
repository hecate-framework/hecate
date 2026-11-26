local test = require("harness.test")
local core = require("hecate.core")
local edit = require("hecate.cli.manifest_edit")
local manifest = require("hecate.cli.manifest")
local T = test.Case("CliManifestEditTest")

local SPEC = [[
-- The manifest of the application.
return {
  name        = "acme-api",          -- required
  version     = "0.1.0",             -- SemVer

  dependencies = {
    -- the framework
    ["hecate"]            = "~> 0.3",
    ["hecate-postgresql"] = "~> 0.3",   -- the driver
  },
  development_dependencies = {
    ["hecate-test"] = "~> 0.3",
  },

  scripts = {
    seed = "scripts/seed.lua",
  },
}
]]

local function refused(self, run, fragment)
  local err = self:assert_error(run)
  self:assert_true(core.is_instance_of(err, core.ConfigurationError), tostring(err))
  local message = (err --[[@as hecate.core.Error]]).message
  self:assert_true(message:find(fragment, 1, true) ~= nil, message)
  return err
end

function T:test_a_new_dependency_is_one_line_and_everything_else_is_untouched()
  local text = edit.set(SPEC, "dependencies", "plc", "~> 0.5")
  local expected = SPEC:gsub('(    %["hecate%-postgresql"%] = "~> 0.3",   %-%- the driver\n)', '%1    ["plc"] = "~> 0.5",\n')
  self:assert_equal(expected, text)
  self:assert_equal("~> 0.5", manifest.parse(text).dependencies.plc)
end

function T:test_a_constraint_is_replaced_in_place_keeping_the_comment()
  local text = edit.set(SPEC, "dependencies", "hecate-postgresql", ">= 0.3, < 0.5")
  self:assert_true(text:find('["hecate-postgresql"] = ">= 0.3, < 0.5",   -- the driver', 1, true) ~= nil, text)
  self:assert_equal(">= 0.3, < 0.5", manifest.parse(text).dependencies["hecate-postgresql"])
  -- A bare-name key is found too.
  local bare = edit.set('return {\n  name = "x",\n  dependencies = {\n    plc = "~> 0.5",\n  },\n}\n', "dependencies", "plc", "~> 0.6")
  self:assert_true(bare:find('plc = "~> 0.6",', 1, true) ~= nil, bare)
end

function T:test_a_development_dependency_goes_to_its_own_table()
  local text = edit.set(SPEC, "development_dependencies", "busted", ">= 2.0")
  self:assert_equal(">= 2.0", manifest.parse(text).development_dependencies.busted)
  self:assert_equal("~> 0.3", manifest.parse(text).development_dependencies["hecate-test"])
end

function T:test_a_missing_table_is_added_before_the_last_brace()
  local bare = 'return {\n  name = "x",\n  version = "0.1.0"\n}\n'
  local text = edit.set(bare, "dependencies", "plc", "~> 0.5")
  self:assert_equal('return {\n  name = "x",\n  version = "0.1.0",\n  dependencies = {\n    ["plc"] = "~> 0.5",\n  },\n}\n', text)
  self:assert_equal("~> 0.5", manifest.parse(text).dependencies.plc)
end

function T:test_an_empty_one_line_table_becomes_a_block()
  local text = edit.set('return {\n  name = "x",\n  dependencies = { },\n}\n', "dependencies", "plc", "~> 0.5")
  self:assert_equal('return {\n  name = "x",\n  dependencies = {\n    ["plc"] = "~> 0.5",\n  },\n}\n', text)
end

function T:test_comments_inside_an_empty_table_are_kept()
  local source = 'return {\n  name = "x",\n  dependencies = {\n    -- (none yet)\n  },\n}\n'
  local text = edit.set(source, "dependencies", "plc", "~> 0.5")
  self:assert_equal('return {\n  name = "x",\n  dependencies = {\n    -- (none yet)\n    ["plc"] = "~> 0.5",\n  },\n}\n', text)
  refused(self, function() edit.set('return {\n  name = "x",\n  dependencies = { --[[ none ]] },\n}\n', "dependencies", "plc", "~> 0.5") end, "a comment stands inside")
end

function T:test_a_last_entry_without_a_comma_gets_one()
  local text = edit.set('return {\n  name = "x",\n  dependencies = {\n    a = "1.0"\n  },\n}\n', "dependencies", "plc", "~> 0.5")
  self:assert_true(text:find('a = "1.0",\n    ["plc"] = "~> 0.5",\n  },', 1, true) ~= nil, text)
  self:assert_equal("1.0", manifest.parse(text).dependencies.a)
end

function T:test_strings_and_comments_that_look_like_tables_do_not_fool_it()
  local tricky = 'return {\n  name = "x",\n  -- dependencies = {\n  description = "dependencies = { }",\n  dependencies = {\n    a = "1.0",\n  },\n  --[[ dependencies = {\n  ]]\n}\n'
  local text = edit.set(tricky, "dependencies", "plc", "~> 0.5")
  self:assert_equal("~> 0.5", manifest.parse(text).dependencies.plc)
  self:assert_equal("dependencies = { }", manifest.parse(text).description)
end

function T:test_removing_deletes_the_line_and_only_the_line()
  local text = edit.remove(SPEC, "dependencies", "hecate-postgresql")
  self:assert_equal((SPEC:gsub('    %["hecate%-postgresql"%] = "~> 0.3",   %-%- the driver\n', "")), text)
  self:assert_nil(manifest.parse(text).dependencies["hecate-postgresql"])
  local emptied = edit.remove(edit.remove(SPEC, "dependencies", "hecate-postgresql"), "dependencies", "hecate")
  self:assert_nil(next(manifest.parse(emptied).dependencies))
end

function T:test_it_refuses_when_unsure_and_names_the_line_to_write()
  local one_line = 'return {\n  name = "x",\n  dependencies = { a = "1.0" },\n}\n'
  local err = refused(self, function() edit.set(one_line, "dependencies", "plc", "~> 0.5") end, "on one line")
  self:assert_equal('["plc"] = "~> 0.5",', err.context.line)
  refused(self, function() edit.set('return {\n  name = "x",\n  dependencies = {\n    a = "1.0", b = "2.0",\n  },\n}\n', "dependencies", "plc", "~> 0.5") end, "shares its line")
  refused(self, function() edit.set('return { name = "x" }', "dependencies", "plc", "~> 0.5") end, "on one line")
  refused(self, function() edit.set('local x = 1\nreturn {\n  name = "x",\n}\n', "dependencies", "plc", "~> 0.5") end, "return {")
  refused(self, function() edit.set('return {\n  name = "x",\n  dependencies = {\n  },\n  dependencies = {\n  },\n}\n', "dependencies", "plc", "~> 0.5") end, "more than once")
  refused(self, function() edit.set('return {\n  name = "x\n}\n', "dependencies", "plc", "~> 0.5") end, "never closed")
  refused(self, function() edit.remove(SPEC, "dependencies", "ghost") end, "not in the `dependencies` table")
  refused(self, function() edit.remove('return {\n  name = "x",\n}\n', "dependencies", "ghost") end, "no `dependencies` table")
  refused(self, function() edit.remove('return {\n  name = "x",\n  dependencies = {\n    a = "1.0", b = "2.0",\n  },\n}\n', "dependencies", "a") end, "alone on its line")
end

function T:test_windows_line_ends_are_kept()
  local crlf = SPEC:gsub("\n", "\r\n")
  local text = edit.set(crlf, "dependencies", "plc", "~> 0.5")
  self:assert_true(text:find('["plc"] = "~> 0.5",\r\n', 1, true) ~= nil)
  self:assert_nil(text:find("[^\r]\n"))
  self:assert_equal("~> 0.5", manifest.parse(text).dependencies.plc)
  local removed = edit.remove(crlf, "dependencies", "hecate")
  self:assert_nil(removed:find("[^\r]\n"))
end

function T:test_has_reports_the_presence_of_an_entry()
  self:assert_true(edit.has(SPEC, "dependencies", "hecate"))
  self:assert_false(edit.has(SPEC, "dependencies", "plc"))
  self:assert_false(edit.has(SPEC, "development_dependencies", "hecate"))
  self:assert_nil(edit.has("return {", "dependencies", "x"))
end

return T
