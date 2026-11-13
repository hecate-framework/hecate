local test = require("harness.test")
local config_reference = require("lib.config_reference")
local T = test.Case("ConfigReferenceTest")

-- A fixture declaration in the shape of packages/config/src/hecate/config/declaration.lua (Lua 5.5 global
-- declarations, schema constructors, module constants and the variable_name function).
local DECLARATION = [[
global <const> require, table

local core = require("hecate.core")
local schema = require("hecate.schema")

local M = {}
M.LEVELS = { "low", "high" }
M.CEILING = 100

function M.framework_properties()
  local level = schema.enumeration(M.LEVELS)
  return {
    logging = schema.default(schema.object({
      level = schema.default(level, "low"),
      levels = schema.default(schema.map(level), {}),
      sinks = schema.default(schema.array(schema.enumeration({ "console", "file" })), { "console" }),
      file = schema.optional(schema.object({ path = schema.optional(schema.string({ min_length = 1 })) })),
    }), {}),
    limits = schema.default(schema.object({
      depth = schema.default(schema.integer({ minimum = 1, maximum = M.CEILING }), M.CEILING),
      grace = schema.default(schema.number({ minimum = 0 }), 2.5),
      name = schema.string({ pattern = "^a|b$" }),
    }), {}),
  }
end

function M.variable_name(prefix, segments)
  local joined = table.concat(segments, "__"):upper():gsub("[^%w_]", "_")
  return prefix .. "_" .. joined
end

return M
]]

local LOAD = 'local prefix = options.env_prefix or "APP"\n'

local SPECIFICATION = [[
# Configuration

| Key | Type | Default | Meaning |
|---|---|---|---|
| `logging.level` | one of `low`, `high` | `low` | the level, see [the guide](guide.md) and [RFC 5424](https://www.rfc-editor.org/rfc/rfc5424) |
| `logging.levels` | map | `{}` | named levels |
| `logging.sinks` | array | `{ "console" }` | the sinks `a \| b` |
| `logging.file.path` | string | none | the file |

Text between the tables.

| Key | Type | Default | Meaning |
|---|---|---|---|
| `limits.depth` | integer | `100` | the depth |
| `limits.grace` | number | `2.5` | the grace |
| `limits.name` | string | none | the name |
]]

local function fixture(specification)
  return config_reference.build({ declaration = DECLARATION, load = LOAD, specification = specification or SPECIFICATION })
end

local function find(model, key)
  for _, entry in ipairs(model.keys) do
    if entry.key == key then return entry end
  end
  error("no key " .. key)
end

function T:test_the_declaration_is_loaded_without_any_package()
  local module = assert(config_reference.load_declaration(DECLARATION))
  self:assert_equal("APP_A__B", module.variable_name("APP", { "a", "b" }))
  local _, err = config_reference.load_declaration('local x = require("hecate.json")\nreturn {}')
  self:assert_true(assert(err):find("hecate.json", 1, true) ~= nil)
end

function T:test_keys_are_the_leaves_and_maps_in_path_order()
  local model = fixture()
  self:assert_equal(0, #model.problems)
  self:assert_equal("APP", model.prefix)
  local keys = {}
  for i, entry in ipairs(model.keys) do keys[i] = entry.key end
  self:assert_equal("limits.depth limits.grace limits.name logging.file.path logging.level logging.levels logging.sinks",
    table.concat(keys, " "))
end

function T:test_type_default_range_and_variable()
  local model = fixture()
  local depth = find(model, "limits.depth")
  self:assert_equal("integer", depth.type)
  self:assert_equal("100", depth.default)
  self:assert_equal("1 to 100", depth.allowed[1])
  self:assert_equal("APP_LIMITS__DEPTH", depth.variable)
  self:assert_equal("at least 0", find(model, "limits.grace").allowed[1])
  self:assert_equal('"low"', find(model, "logging.level").default)
  self:assert_equal("one of `low`, `high`", find(model, "logging.level").allowed[1])
  local sinks = find(model, "logging.sinks")
  self:assert_equal("array of enumeration", sinks.type)
  self:assert_equal('{ "console" }', sinks.default)
  self:assert_true(sinks.list)
  local levels = find(model, "logging.levels")
  self:assert_equal("map of string to enumeration", levels.type)
  self:assert_true(levels.files_only)
  self:assert_nil(levels.variable)
  local path = find(model, "logging.file.path")
  self:assert_nil(path.default)
  self:assert_true(path.optional)
  self:assert_equal("APP_LOGGING__FILE__PATH", path.variable)
  local name = find(model, "limits.name")
  self:assert_false(name.optional)
  self:assert_equal("matches `^a|b$`", name.allowed[1])
end

function T:test_descriptions_come_from_the_specification_without_relative_links()
  local model = fixture()
  self:assert_equal("the level, see the guide and [RFC 5424](https://www.rfc-editor.org/rfc/rfc5424)",
    find(model, "logging.level").description)
  self:assert_equal("the sinks `a \\| b`", find(model, "logging.sinks").description)
end

function T:test_the_specification_and_the_declaration_must_agree()
  local spec = SPECIFICATION:gsub("| `limits.grace` [^\n]*\n", "") .. "\n| Key | Type | Default | Meaning |\n|---|---|---|---|\n| `limits.gone` | x | y | z |\n"
  local model = fixture(spec)
  self:assert_equal(2, #model.problems)
  self:assert_true(model.problems[1]:find("limits.grace has no row", 1, true) ~= nil)
  self:assert_true(model.problems[2]:find("limits.gone is not a declared framework key", 1, true) ~= nil)
end

function T:test_the_page_is_deterministic_and_marked()
  local page = config_reference.render(fixture())
  self:assert_equal(page, config_reference.render(fixture()))
  self:assert_true(config_reference.is_generated(page))
  self:assert_true(page:find("default prefix `APP`", 1, true) ~= nil)
  self:assert_true(page:find("| `limits.depth` | integer | `100` | 1 to 100 | `APP_LIMITS__DEPTH` | the depth |", 1, true) ~= nil)
  self:assert_true(page:find("| `logging.levels` | map of string to enumeration | `{}` | values: one of `low`, `high` | "
    .. "none (files only) | named levels |", 1, true) ~= nil)
  self:assert_true(page:find("`APP_LOGGING__SINKS` (comma separated)", 1, true) ~= nil)
  self:assert_true(page:find("| `logging.file.path` | string | none (optional) |", 1, true) ~= nil)
  self:assert_true(page:find("| `limits.name` | string | none (required) | matches `^a\\|b$` |", 1, true) ~= nil)
end

return T
