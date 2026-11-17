---@diagnostic disable: need-check-nil, undefined-field  -- tests index generated pages that a failing assertion would reveal
-- The project documentation: the configuration reference from a JSON Schema, the LuaLS meta files, and
-- the site that `project.build` writes. The generator produces no API reference: the contract is the
-- external documentation (documentation.md, OQ-141).
local test = require("harness.test")
local doc = require("hecate.doc")
local project = require("hecate.doc.project")
local front_matter = require("hecate.doc.front_matter")
local core = require("hecate.core")
local T = test.Case("ProjectTest")

local config_schema = {
  type = "object", required = { "port" },
  properties = {
    port = { type = "integer", minimum = 1, maximum = 65535, description = "TCP port." },
    mode = { type = "string", enum = { "dev", "prod" }, default = "dev" },
    database = { type = "object", properties = { url = { type = "string", description = "Connection URL." } } },
  },
}

function T:test_configuration_page_lists_keys_with_dotted_paths()
  local page = project.configuration_page(config_schema)
  self:assert_not_nil(page:find("`port`", 1, true))
  self:assert_not_nil(page:find("`database.url`", 1, true))
  self:assert_not_nil(page:find("required", 1, true))
  self:assert_not_nil(page:find("`dev`", 1, true))
  self:assert_not_nil(page:find("1 to 65535", 1, true), page)
end

function T:test_build_writes_a_site_with_the_guides_and_the_configuration_reference()
  local fs = doc.MemoryFileSystem({})
  local report = project.build({
    config = { title = "Shop docs" }, source = "docs", out = "dist", fs = fs, clean = true, strict = true,
    configuration = config_schema,
    pages = { ["index.md"] = "# Shop\n\nWelcome.\n" },
  })
  self:assert_equal(0, #report.problems, table.concat(report.problems, "\n"))
  self:assert_not_nil(fs:read("dist/en/configuration/index.html"))
  self:assert_not_nil(fs:read("dist/en/index.html"))
end

function T:test_build_reports_the_code_reference_of_the_project()
  local fs = doc.MemoryFileSystem({})
  local report = project.build({
    config = { title = "Shop docs" }, source = "docs", out = "dist", fs = fs,
    pages = { ["index.md"] = "# Shop\n\nWelcome.\n" },
    code = { root = "shop", name = "shop" },
  })
  self:assert_not_nil(report.code)
  if report.code.skipped then
    self:assert_equal(true, #report.problems >= 1)
  else
    self:assert_equal(0, report.code.pages) -- no src directory in the memory file system
  end
end

function T:test_meta_declares_classes_for_the_schemas_of_a_project()
  local text = project.meta({
    User = { type = "object", required = { "name" }, description = "An account.",
      properties = { name = { type = "string", description = "Display\nname." }, age = { type = "integer" },
        role = { enum = { "admin", "user" } }, tags = { type = "array", items = { type = "string" } },
        owner = { ["$ref"] = "#/$defs/Owner" }, extra = { type = "object" } } },
    Owner = { type = "object", properties = { id = { type = "integer" } } },
    Kind = { enum = { "a", "b" } },
  }, "shop.schemas")
  self:assert_equal("---@meta shop.schemas", text:match("^[^\n]*"))
  self:assert_not_nil(text:find("---@class shop.schemas.User\n", 1, true))
  self:assert_not_nil(text:find("---@field name string  Display name.", 1, true))
  self:assert_not_nil(text:find("---@field age? integer", 1, true))
  self:assert_not_nil(text:find('---@field role? "admin"|"user"', 1, true))
  self:assert_not_nil(text:find("---@field tags? string[]", 1, true))
  self:assert_not_nil(text:find("---@field owner? shop.schemas.Owner", 1, true))
  self:assert_not_nil(text:find("---@field extra? table", 1, true))
  self:assert_not_nil(text:find('---@alias shop.schemas.Kind "a"|"b"', 1, true))
  self:assert_equal(text, project.meta({
    Kind = { enum = { "a", "b" } },
    Owner = { type = "object", properties = { id = { type = "integer" } } },
    User = { type = "object", required = { "name" }, description = "An account.",
      properties = { name = { type = "string", description = "Display\nname." }, age = { type = "integer" },
        role = { enum = { "admin", "user" } }, tags = { type = "array", items = { type = "string" } },
        owner = { ["$ref"] = "#/$defs/Owner" }, extra = { type = "object" } } },
  }, "shop.schemas"))
end

function T:test_meta_refuses_names_that_are_not_lua_identifiers()
  local ok, err = pcall(project.meta, { ["bad name"] = { type = "object" } }, "shop")
  self:assert_equal(false, ok)
  self:assert_not_nil(tostring(err):find("bad name", 1, true))
end

function T:test_the_generator_produces_no_api_reference()
  -- The contract is the external documentation (OQ-141): no function, no option, no page.
  self:assert_nil(project.api_pages)
  local contract = { openapi = "3.1.0", info = { title = "Shop", version = "1" },
    paths = { ["/users"] = { get = { operationId = "listUsers", responses = { ["200"] = { description = "OK" } } } } } }
  local fs = doc.MemoryFileSystem({})
  -- A stray `document` option is not an option of the build: it is ignored, and nothing below `api/` is written.
  project.build({ config = { title = "Shop" }, source = "docs", out = "dist", fs = fs, document = contract,
    configuration = config_schema, pages = { ["index.md"] = "# Shop\n" } })
  for path in pairs(fs.files) do
    self:assert_nil(path:find("/api/", 1, true), path)
    self:assert_nil(path:find("listUsers", 1, true), path)
  end
  self:assert_not_nil(fs:read("docs/en/configuration.md"))
end

local function configuration_of(properties)
  return { type = "object", properties = properties }
end

function T:test_a_default_of_false_is_kept()
  local page = project.configuration_page(configuration_of({ flag = { type = "boolean", default = false } }))
  self:assert_not_nil(page:find("| `false` |", 1, true), page)
end

function T:test_table_defaults_and_values_are_rendered_deterministically()
  local value = { b = 1, a = { y = 2, x = { 1, 2 } }, [1] = nil }
  local page = project.configuration_page(configuration_of({
    opts = { type = "object", default = value }, kind = { enum = { { z = 1, a = 2 }, "s" }, const = { k = true } },
  }))
  self:assert_nil(page:find("table: 0x", 1, true), page)
  self:assert_not_nil(page:find('{"a":{"x":[1,2],"y":2},"b":1}', 1, true), page)
  self:assert_not_nil(page:find('{"a":2,"z":1}', 1, true), page)
  local other = { a = { x = { 1, 2 }, y = 2 } }
  other.b = 1
  local again = project.configuration_page(configuration_of({
    kind = { const = { k = true }, enum = { { a = 2, z = 1 }, "s" } }, opts = { default = other, type = "object" },
  }))
  self:assert_equal(page, again)
  local meta = project.meta({ K = { enum = { "a", { x = 1 } } }, N = { enum = { 1, 0 / 0 } }, E = { enum = {} } }, "shop.schemas")
  self:assert_not_nil(meta:find("---@alias shop.schemas.K any\n", 1, true), meta)
  self:assert_not_nil(meta:find("---@alias shop.schemas.N any\n", 1, true), meta)
  self:assert_not_nil(meta:find("---@alias shop.schemas.E any\n", 1, true), meta)
end

function T:test_front_matter_description_is_a_valid_double_quoted_scalar()
  local text = project.configuration_page({ type = "object", properties = {},
    description = 'tab\there \1 "q" back\\slash\nnext' })
  local meta = front_matter.parse(text)
  self:assert_equal('tab here   "q" back\\slash next', meta.description)
end

local HOSTILE = {
  "<script>alert(1)</script>", "`tick` ``two``", "[x](javascript:alert(1))", "- item", "+ item", "1. item", "1) item",
  "---", "===", "&amp; &#35; &copy;", "    indented", "| a | b |", "![i](http://x/y.png)", "> quote", "# heading",
}

local function assert_safe(self, text, label)
  -- The front matter is data for the theme, which escapes it; the body is Markdown.
  text = text:match("^%-%-%-\n.-\n%-%-%-\n(.*)$") or text
  local marker = text:find(project.GENERATED, 1, true)
  if marker then text = text:sub(1, marker - 1) .. text:sub(marker + #project.GENERATED) end
  local outside_code = text:gsub("(`+)[^`]-%1", "")
  self:assert_nil(outside_code:find("[^\\]<"), label)
  self:assert_nil(outside_code:find("^<"), label)
  self:assert_nil(outside_code:find("[x](javascript", 1, true), label)
  self:assert_nil(outside_code:find("![i](", 1, true), label)
  for line in text:gmatch("[^\n]+") do
    if line:find("^|") and not line:find("^|%-%-%-") then
      local _, pipes = line:gsub("|", "")
      local _, escaped = line:gsub("\\|", "")
      self:assert_equal(true, (pipes - escaped) >= 3, label .. ": " .. line)
    end
    local starts_list = line:find("^[%-+=] ") ~= nil and line:find("^%- `%d+`: ") == nil
    self:assert_equal(false, starts_list, label .. ": " .. line)
    self:assert_equal(false, line:find("^%-%-%-+$") ~= nil, label .. ": " .. line)
    self:assert_equal(false, line:find("^%d+[.)] ") ~= nil, label .. ": " .. line)
  end
end

function T:test_every_schema_field_is_escaped()
  for _, hostile in ipairs(HOSTILE) do
    local config = project.configuration_page({ type = "object", description = hostile, properties = {
      [hostile] = { type = "string", default = hostile, enum = { hostile }, pattern = hostile, format = hostile, description = hostile },
    } })
    assert_safe(self, config, hostile .. " in configuration")
  end
  -- A description that would start a block is escaped.
  local page = project.configuration_page(configuration_of({ key = { type = "string", description = "- item" } }))
  self:assert_not_nil(page:find("\\- item", 1, true), page)
end

function T:test_untrusted_schemas_are_expanded_within_bounds()
  local cyclic = { type = "object", properties = { self = { ["$ref"] = "#/$defs/Node" }, name = { type = "string" } } }
  local page = project.configuration_page({ type = "object", properties = { root = { ["$ref"] = "#/$defs/Node" } },
    ["$defs"] = { Node = cyclic } })
  local _, rows = page:gsub("\n| `", "")
  self:assert_equal(true, rows <= 3, page)
  local wide = {}
  for index = 1, 1200 do wide["p" .. index] = { type = "string" } end
  local text = project.configuration_page(configuration_of(wide))
  local _, count = text:gsub("\n| `p", "")
  self:assert_equal(500, count)
  self:assert_not_nil(text:find("truncated", 1, true))
  local deep = { type = "string" }
  for _ = 1, 5000 do deep = { type = "array", items = deep } end
  local ok = pcall(project.configuration_page, configuration_of({ x = deep }))
  self:assert_true(ok)
  self:assert_equal("any", project.meta({ D = deep }, "shop.schemas"):match("%-%-%-@alias shop%.schemas%.D (.-)\n"):gsub("%[%]", ""))
end

function T:test_configuration_follows_defs()
  local schema = { type = "object", properties = { db = { ["$ref"] = "#/$defs/Db" } },
    ["$defs"] = { Db = { type = "object", properties = { url = { type = "string" } } } } }
  self:assert_not_nil(project.configuration_page(schema):find("`db.url`", 1, true))
  self:assert_true(project.is_generated(project.configuration_page(schema)))
end

function T:test_is_generated_negatives()
  self:assert_false(project.is_generated("# Hand written"))
  self:assert_false(project.is_generated(nil))
  self:assert_false(project.is_generated(3))
end

function T:test_pages_are_independent_of_insertion_order()
  local function make(order)
    local properties = {}
    for _, name in ipairs(order) do properties[name] = { type = "string", description = name } end
    return project.configuration_page(configuration_of(properties))
  end
  self:assert_equal(make({ "a", "b", "c" }), make({ "c", "a", "b" }))
end

local function build_options(fs, extra)
  local options = { config = { title = "Shop" }, source = "docs", out = "dist", fs = fs, pages = { ["index.md"] = "# Shop\n" } }
  for key, value in pairs(extra or {}) do options[key] = value end
  return options
end

function T:test_a_guide_on_a_generated_path_fails_before_anything_is_written()
  for _, key in ipairs({ "configuration.md", "./configuration.md", ".//configuration.md", "Configuration.md" }) do
    local fs = doc.MemoryFileSystem({})
    local err = self:assert_error(function()
      project.build(build_options(fs, { configuration = config_schema, pages = { ["index.md"] = "# S\n", [key] = "# mine\n" } }))
    end)
    self:assert_true(core.is_instance_of(err, doc.BuildError), key .. ": " .. tostring(err))
    self:assert_nil(next(fs.files), key .. " left partial files")
  end
end

function T:test_a_file_that_is_not_generated_is_never_overwritten()
  local fs = doc.MemoryFileSystem({ ["docs/en/configuration.md"] = "# Mine\n" })
  local err = self:assert_error(function() project.build(build_options(fs, { configuration = config_schema })) end)
  self:assert_true(core.is_instance_of(err, doc.BuildError), tostring(err))
  self:assert_equal("# Mine\n", fs:read("docs/en/configuration.md"))
  self:assert_nil(fs:read("docs/en/index.md"), "nothing was written")
end

function T:test_generated_pages_that_are_no_longer_produced_are_removed()
  local fs = doc.MemoryFileSystem({})
  project.build(build_options(fs, { configuration = config_schema }))
  self:assert_not_nil(fs:read("docs/en/configuration.md"))
  project.build(build_options(fs, {}))
  self:assert_nil(fs:read("docs/en/configuration.md"))
  self:assert_not_nil(fs:read("docs/en/index.md"), "guides stay")
end

function T:test_options_are_validated_up_front_naming_the_field()
  local cases = {
    { { pages = 3 }, "pages" }, { { pages = { ["../x.md"] = "a" } }, "pages" }, { { pages = { ["/x.md"] = "a" } }, "pages" },
    { { pages = { ["con.md"] = "a" } }, "pages" }, { { pages = { ["a\\b.md"] = "a" } }, "pages" },
    { { pages = { ["x.txt"] = "a" } }, "pages" }, { { pages = { ["x.md"] = 3 } }, "pages" },
    { { pages = { ["x.md"] = "a", ["./x.md"] = "b" } }, "pages" }, { { pages = { [".h.md"] = "a" } }, "pages" },
    { { locale = "../x" }, "locale" }, { { locale = 3 }, "locale" }, { { locale = "" }, "locale" },
    { { configuration = 3 }, "configuration" }, { { config = "x" }, "config" },
    { { code = "x" }, "code" }, { { code = { root = "r", name = "../x" } }, "code" }, { { code = { root = "r" } }, "code" },
    { { code = { root = "r", name = "x", executable = 3 } }, "code.executable" },
  }
  for _, case in ipairs(cases) do
    local fs = doc.MemoryFileSystem({})
    local err = self:assert_error(function() project.build(build_options(fs, case[1])) end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError), case[2] .. ": " .. tostring(err))
    self:assert_not_nil(tostring(err):find("`" .. case[2] .. "`", 1, true), tostring(err))
    self:assert_nil(next(fs.files), case[2] .. " left files")
  end
end

function T:test_the_locale_option_and_the_default_locale_choose_the_directory()
  local fs = doc.MemoryFileSystem({})
  project.build(build_options(fs, { locale = "fr", config = { title = "S", default_locale = "fr", locales = { { code = "fr" } } },
    configuration = config_schema }))
  self:assert_not_nil(fs:read("docs/fr/configuration.md"))
  self:assert_not_nil(fs:read("dist/fr/configuration/index.html"))
  local other = doc.MemoryFileSystem({})
  project.build(build_options(other, { config = { title = "S", default_locale = "fr", locales = { { code = "fr" } } }, configuration = config_schema }))
  self:assert_not_nil(other:read("docs/fr/configuration.md"))
end

function T:test_meta_edge_cases()
  local text = project.meta({
    A = { type = "object", properties = { ["end"] = { type = "string" }, ["a-b"] = { type = "integer" },
      c = { anyOf = {} }, d = { oneOf = {} }, e = { const = "x" }, f = { type = { "string", "null" } },
      g = { type = "array", items = { type = "array", items = { type = "integer" } } },
      h = { type = "object", additionalProperties = { type = "string" } }, i = { allOf = { { ["$ref"] = "#/$defs/B" } } },
      j = { ["$ref"] = "#/$defs/not a name" }, k = { anyOf = { { type = "string" }, { type = "null" } } },
      l = { type = "array", items = { type = "string", enum = { "a", "b" } } } } },
    B = { type = "object", properties = {} },
  }, "shop.schemas")
  for _, line in ipairs({ '---@field ["end"]? string', '---@field ["a-b"]? integer', "---@field c? any", "---@field d? any",
    '---@field e? "x"', "---@field f? string|nil", "---@field g? integer[][]", "---@field h? table<string, string>",
    "---@field i? shop.schemas.B", "---@field j? any", "---@field k? string|nil", '---@field l? ("a"|"b")[]' }) do
    self:assert_not_nil(text:find(line .. "\n", 1, true), line .. "\n" .. text)
  end
  for _, bad in ipairs({ "", "a..b", "a.", ".a", "1a", "a b", "a-b" }) do
    local ok = pcall(project.meta, {}, bad)
    self:assert_false(ok, bad)
  end
  local ok = pcall(project.meta, { [1] = { type = "string" } }, "shop")
  self:assert_false(ok)
  local err = self:assert_error(function() project.meta({ A = { type = "object", properties = { [1] = {} } } }, "shop") end)
  self:assert_true(core.is_instance_of(err, core.ArgumentError))
end

return T
