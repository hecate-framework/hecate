---@diagnostic disable: need-check-nil, param-type-mismatch, undefined-field, inject-field
-- The configuration is immutable after boot (invariant) and typed access (configuration.md, "Immutability and typed access").
local test = require("harness.test")
local core = require("hecate.core")
local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or "."
local fixture = dofile(here .. "/../support/fixture.lua")
local T = test.Case("ConfigImmutabilityTest")

local function write_fails(self, fn)
  local ok, err = pcall(fn)
  self:assert_false(ok)
  self:assert_true(core.is_instance_of(err, core.ConformanceError), tostring(err))
end

function T:test_sections_are_frozen_at_every_depth()
  local configuration = fixture.load({})
  local values = configuration:values()
  write_fails(self, function() values.name = "other" end)
  write_fails(self, function() values.database.port = 1 end)
  write_fails(self, function() values.extra = 1 end)
  write_fails(self, function() values.labels.x = "y" end)
  write_fails(self, function() values.logging.sinks[1] = "file" end)
  write_fails(self, function() values.logging.file = {} end)
  self:assert_equal(5432, values.database.port)
end

function T:test_lists_are_frozen_and_readable()
  local tags = fixture.load({ files = { ["config/default.lua"] = "return { tags = { 'x', 'y' } }" } }):get("tags")
  self:assert_equal(2, #tags)
  write_fails(self, function() tags[3] = "z" end)
  local seen = {}
  for index, item in ipairs(tags) do seen[index] = item end
  self:assert_equal("x", seen[1])
  self:assert_equal("y", seen[2])
  local count = 0
  for _ in pairs(tags) do count = count + 1 end
  self:assert_equal(2, count)
end

function T:test_empty_list_has_length_zero()
  local configuration = fixture.load({ files = { ["config/default.lua"] = "return { tags = {} }" } })
  self:assert_equal(0, #configuration:get("tags"))
end

function T:test_pairs_iterates_a_section()
  local labels = fixture.load({ files = { ["config/default.lua"] = "return { labels = { a = '1', b = '2' } }" } }):get("labels")
  local keys = {}
  for key, value in pairs(labels) do keys[#keys + 1] = key .. "=" .. value end
  table.sort(keys)
  self:assert_equal("a=1,b=2", table.concat(keys, ","))
end

function T:test_map_keys_named_like_methods_are_readable()
  local labels = fixture.load({ files = { ["config/default.lua"] = "return { labels = { get = 'g', values = 'v' } }" } }):get("labels")
  self:assert_equal("g", labels.get)
  self:assert_equal("v", labels.values)
end

function T:test_later_changes_to_inputs_do_not_reach_the_configuration()
  local text = "return { tags = { 'x' } }"
  local configuration = fixture.load({ files = { ["config/default.lua"] = text } })
  self:assert_equal("x", configuration:get("tags")[1])
  self:assert_equal("x", fixture.load({ files = { ["config/default.lua"] = text } }):get("tags")[1])
end

function T:test_defaults_are_copied_per_load()
  local first = fixture.load({})
  local second = fixture.load({})
  self:assert_equal("a", first:get("tags")[1])
  self:assert_equal("a", second:get("tags")[1])
end

function T:test_get_of_an_undeclared_path_is_an_argument_error()
  local configuration = fixture.load({})
  local ok, err = pcall(configuration.get, configuration, "database.nope")
  self:assert_false(ok)
  self:assert_true(core.is_instance_of(err, core.ArgumentError))
  self:assert_error(function() configuration:get("nope") end, "nope")
  self:assert_error(function() configuration:get("tags.1") end, "tags")
  self:assert_error(function() configuration:get(1) end, "path")
end

function T:test_get_of_an_absent_optional_is_nil_and_of_a_section_is_a_section()
  local configuration = fixture.load({})
  self:assert_nil(configuration:get("database.password"))
  self:assert_equal(5432, configuration:get("database").port)
  self:assert_nil(configuration:get("labels.anything"))
end

function T:test_source_of_an_undeclared_path_is_an_argument_error()
  self:assert_error(function() fixture.load({}):source("nope") end, "nope")
end

function T:test_configuration_object_has_no_setters()
  local configuration = fixture.load({})
  self:assert_nil(configuration.set)
  self:assert_nil(configuration.put)
end

return T
