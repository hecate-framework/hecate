local test = require("harness.test")
local core = require("hecate.core")
local manifest = require("hecate.cli.manifest")
local T = test.Case("CliManifestTest")

local function rejects(self, source, fragment, limits)
  local err = self:assert_error(function() manifest.parse(source, "m.lua", limits) end)
  self:assert_true(core.is_instance_of(err, core.ConfigurationError), tostring(err))
  local message = (err --[[@as hecate.core.Error]]).message
  self:assert_true(message:find(fragment, 1, true) ~= nil, message)
  return err
end

function T:test_the_example_of_the_specification_is_valid()
  local m = manifest.parse([[
return {
  name = "acme-api", version = "0.1.0", description = "ACME public API", license = "MIT", lua = "5.5",
  hecate = "~> 0.3",
  dependencies = { ["hecate"] = "~> 0.3", ["hecate-postgresql"] = "~> 0.3" },
  development_dependencies = { ["hecate-test"] = "~> 0.3" },
  scripts = { seed = "scripts/seed.lua" },
  contract = { title = "ACME API", version = "1.0.0", servers = { "https://api.acme.example" } },
  rocks_servers = { },
  doc = { guides_dir = "docs", package_name = "acme-api" },
}]])
  self:assert_equal("acme-api", m.name)
  self:assert_equal("~> 0.3", m.dependencies["hecate-postgresql"])
  self:assert_equal("docs", m.doc.guides_dir)
end

function T:test_only_the_name_is_required()
  self:assert_equal("x", manifest.parse('return { name = "x" }').name)
  rejects(self, "return {}", "name")
end

function T:test_violations_are_listed_with_their_pointer()
  local err = rejects(self, 'return { name = "Bad Name", version = "1", dependencies = { a = 3 }, extra = 1 }', "/version")
  local message = (err --[[@as hecate.core.Error]]).message
  self:assert_true(message:find("/name", 1, true) ~= nil, message)
  self:assert_true(message:find("/dependencies/a", 1, true) ~= nil, message)
  self:assert_true(message:find("extra", 1, true) ~= nil, message)
  self:assert_true(#err.context.violations >= 4)
end

function T:test_the_environment_is_empty()
  rejects(self, 'local os = require("os") return { name = "x" }', "require")
  rejects(self, 'return { name = tostring(1) }', "tostring")
  rejects(self, 'return { name = _G.x }', "_G")
end

function T:test_runaway_code_hits_the_instruction_limit()
  rejects(self, "while true do end", "instruction limit", { instructions = 10000 })
end

function T:test_syntax_errors_precompiled_chunks_and_non_tables_are_refused()
  rejects(self, "return {", "m.lua")
  rejects(self, string.dump(function() return { name = "x" } end), "m.lua")
  rejects(self, 'return "x"', "must return a table")
  rejects(self, "return nil", "must return a table")
  rejects(self, 'local x = nil return x.y', "attempt to index")
end

function T:test_doc_section_is_closed()
  rejects(self, 'return { name = "x", doc = { unknown = "y" } }', "unknown")
  rejects(self, 'return { name = "x", doc = { guides_dir = "" } }', "/doc/guides_dir")
end

return T
