---@diagnostic disable: need-check-nil, undefined-field  -- tests index generated pages that a failing assertion would reveal
-- The project documentation: the configuration reference from a JSON Schema, the LuaLS meta files, and
-- the site that `doc.generate_project_documentation` writes. The generator produces no API reference: the
-- contract is the external documentation (documentation.md, OQ-141).
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

-- The application is duck-typed: `hecate.doc` calls `configuration_schema()` and never requires `hecate.kernel`.
local function application(schema, secrets)
  return { configuration_schema = function() return schema, secrets end }
end

function T:test_configuration_page_lists_keys_with_dotted_paths()
  local page = project.configuration_page(config_schema)
  self:assert_not_nil(page:find("`port`", 1, true))
  self:assert_not_nil(page:find("`database.url`", 1, true))
  self:assert_not_nil(page:find("required", 1, true))
  self:assert_not_nil(page:find("`dev`", 1, true))
  self:assert_not_nil(page:find("1 to 65535", 1, true), page)
end

function T:test_build_writes_a_site_with_the_guides_and_the_configuration_reference()
  local fs = doc.MemoryFileSystem({ ["docs/en/index.md"] = "# Shop\n\nWelcome.\n" })
  local report = doc.generate_project_documentation({
    site_configuration = { title = "Shop docs", audiences = { "user", "maintainer" }, audience_sites = "merged" },
    guides_dir = "docs", output_dir = "dist", file_system = fs, clean_output_dir = true, fail_on_problems = true,
    application = application(config_schema),
  })
  self:assert_equal(0, #report.problems, table.concat(report.problems, "\n"))
  self:assert_not_nil(fs:read("dist/en/configuration/index.html"))
  self:assert_not_nil(fs:read("dist/en/index.html"))
end

function T:test_build_reports_the_code_reference_of_the_project()
  local fs = doc.MemoryFileSystem({ ["shop/docs/en/index.md"] = "# Shop\n\nWelcome.\n" })
  local report = doc.generate_project_documentation({
    site_configuration = { title = "Shop docs" }, project_dir = "shop", guides_dir = "docs", output_dir = "dist",
    file_system = fs, package_name = "shop",
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
  local fs = doc.MemoryFileSystem({ ["docs/en/index.md"] = "# Shop\n" })
  -- A stray `document` option is not an option of the build: it is ignored, and nothing below `api/` is written.
  doc.generate_project_documentation({ site_configuration = { title = "Shop" }, guides_dir = "docs", output_dir = "dist",
    file_system = fs, document = contract, application = application(config_schema) })
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

-- The options of a build of the guides directory `docs` of `fs`; the guide `index.md` is written into `fs` first,
-- below the locale directory of the build, as the only way to give a guide is to put it in the guides directory.
local function build_options(fs, extra)
  local options = { site_configuration = { title = "Shop" }, guides_dir = "docs", output_dir = "dist", file_system = fs }
  for key, value in pairs(extra or {}) do options[key] = value end
  local locale = options.content_locale or options.site_configuration.default_locale or "en"
  fs:write("docs/" .. locale .. "/index.md", "# Shop\n")
  return options
end

local generate = doc.generate_project_documentation

function T:test_a_hand_written_guide_on_a_generated_path_is_never_overwritten_and_nothing_is_written()
  local fs = doc.MemoryFileSystem({ ["docs/en/configuration.md"] = "# Mine\n" })
  local err = self:assert_error(function() generate(build_options(fs, { application = application(config_schema) })) end)
  self:assert_true(core.is_instance_of(err, doc.BuildError), tostring(err))
  self:assert_equal("# Mine\n", fs:read("docs/en/configuration.md"))
  self:assert_nil(fs:read("dist/en/index.html"), "the site was not built")
  self:assert_nil(fs:read("docs/en/third-party-licences.md"), "no generated page was written")
end

function T:test_generated_pages_that_are_no_longer_produced_are_removed()
  local fs = doc.MemoryFileSystem({})
  generate(build_options(fs, { application = application(config_schema) }))
  self:assert_not_nil(fs:read("docs/en/configuration.md"))
  generate(build_options(fs, {}))
  self:assert_nil(fs:read("docs/en/configuration.md"))
  self:assert_not_nil(fs:read("docs/en/index.md"), "guides stay")
end

function T:test_options_are_validated_up_front_naming_the_field()
  local cases = {
    { { content_locale = "../x" }, "content_locale" }, { { content_locale = 3 }, "content_locale" },
    { { content_locale = "" }, "content_locale" },
    { { site_configuration = "x" }, "site_configuration" },
    { { project_dir = "" }, "project_dir" }, { { guides_dir = 3 }, "guides_dir" }, { { output_dir = "" }, "output_dir" },
    { { sources_dir = "/abs/src" }, "sources_dir" }, { { site_configuration_path = {} }, "site_configuration_path" },
    { { language_server_config_path = "" }, "language_server_config_path" },
    { { package_name = "../x" }, "package_name" }, { { package_name = 3 }, "package_name" },
    { { language_server_path = 3 }, "language_server_path" }, { { clean_output_dir = "yes" }, "clean_output_dir" },
    { { fail_on_problems = 1 }, "fail_on_problems" }, { { file_system = "disk" }, "file_system" },
  }
  for _, case in ipairs(cases) do
    local fs = doc.MemoryFileSystem({})
    local options = { site_configuration = { title = "Shop" }, guides_dir = "docs", output_dir = "dist", file_system = fs }
    for key, value in pairs(case[1]) do options[key] = value end
    local err = self:assert_error(function() generate(options) end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError), case[2] .. ": " .. tostring(err))
    self:assert_not_nil(tostring(err):find("`" .. case[2] .. "`", 1, true), tostring(err))
    self:assert_nil(next(fs.files), case[2] .. " left files")
  end
end

function T:test_the_old_option_names_and_the_explicit_configuration_schema_are_gone()
  self:assert_nil(project.build, "the entry point is `hecate.doc.generate_project_documentation`")
  -- Without an application there is nothing to document: a hand-passed schema or secrets list is not an option.
  local fs = doc.MemoryFileSystem({})
  generate(build_options(fs, { configuration = config_schema, secrets = { "port" } }))
  self:assert_nil(fs:read("docs/en/configuration.md"))
end

-- The defaults are those of the conventional layout of a project (OQ-143): `docs`, `docs/dist`, `src`.
function T:test_every_path_option_has_a_default_of_the_conventional_layout()
  local fs = doc.MemoryFileSystem({ ["docs/site.lua"] = 'return { title = "Shop" }', ["docs/en/index.md"] = "# Shop\n" })
  local report = generate({ file_system = fs, application = application(config_schema) })
  self:assert_equal(0, #report.problems, table.concat(report.problems, "\n"))
  self:assert_not_nil(fs:read("docs/en/configuration.md"), "guides_dir defaults to docs, read from docs/site.lua")
  self:assert_not_nil(fs:read("docs/dist/en/configuration/index.html"), "output_dir defaults to docs/dist")
  self:assert_not_nil(fs:read("docs/dist/en/index.html"))
end

function T:test_relative_paths_are_resolved_against_the_project_directory()
  local fs = doc.MemoryFileSystem({ ["acme/docs/site.lua"] = 'return { title = "Acme" }', ["acme/docs/en/index.md"] = "# Acme\n",
    ["acme/config/site.lua"] = 'return { title = "Other" }' })
  generate({ file_system = fs, project_dir = "acme", application = application(config_schema) })
  self:assert_not_nil(fs:read("acme/docs/en/configuration.md"))
  self:assert_not_nil(fs:read("acme/docs/dist/en/index.html"))
  generate({ file_system = fs, project_dir = "acme", guides_dir = "docs", output_dir = "site",
    site_configuration_path = "config/site.lua" })
  self:assert_not_nil(fs:read("acme/site/en/index.html"))
  self:assert_nil(fs:read("acme/docs/en/configuration.md"), "no application: the stale reference is removed")
end

function T:test_a_missing_site_configuration_file_is_a_build_error()
  local fs = doc.MemoryFileSystem({})
  local err = self:assert_error(function() generate({ file_system = fs }) end)
  self:assert_true(core.is_instance_of(err, doc.BuildError), tostring(err))
  self:assert_not_nil(tostring(err):find("docs/site.lua", 1, true), tostring(err))
end

function T:test_the_locale_option_and_the_default_locale_choose_the_directory()
  local fs = doc.MemoryFileSystem({})
  generate(build_options(fs, { content_locale = "fr", site_configuration = { title = "S", default_locale = "fr",
    locales = { { code = "fr" } }, audiences = { "user", "maintainer" }, audience_sites = "merged" },
    application = application(config_schema) }))
  self:assert_not_nil(fs:read("docs/fr/configuration.md"))
  self:assert_not_nil(fs:read("dist/fr/configuration/index.html"))
  local other = doc.MemoryFileSystem({})
  generate(build_options(other, { site_configuration = { title = "S", default_locale = "fr", locales = { { code = "fr" } } },
    application = application(config_schema) }))
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

-- Audiences (OQ-144): the generated site is the project team's own documentation.
function T:test_the_configuration_reference_is_maintainer_documentation()
  local meta = front_matter.parse(project.configuration_page(config_schema))
  self:assert_equal("maintainer", meta.audience)
end

local function build_with(config)
  local fs = doc.MemoryFileSystem({ ["docs/en/index.md"] = "# Shop\n\nWelcome.\n" })
  local report = generate({
    site_configuration = config, guides_dir = "docs", output_dir = "dist", file_system = fs,
    application = application(config_schema),
  })
  return fs, report
end

function T:test_a_project_site_publishes_the_maintainer_audience_only_by_default()
  local fs, report = build_with({ title = "Shop docs" })
  self:assert_not_nil(fs:read("dist/en/configuration/index.html"), "the configuration reference is maintainer documentation")
  self:assert_not_nil(fs:read("dist/assets/search-en.json"):find("1 to 65535", 1, true))
  self:assert_not_nil(fs:read("dist/en/index.html"), "a guide without the key is maintainer documentation")
  self:assert_equal(0, report.locales.en.unpublished)
  self:assert_equal(1, #report.sites)
  -- A site for the users has no configuration reference.
  local users, user_report = build_with({ title = "Shop docs", audiences = { "user" } })
  self:assert_nil(users:read("dist/en/configuration/index.html"))
  self:assert_nil(users:read("dist/assets/search-en.json"):find("1 to 65535", 1, true))
  self:assert_equal(2, user_report.locales.en.unpublished, "the guide without the key and the configuration reference")
  -- The page stays in the source tree: generated pages are written, publication is a build decision.
  self:assert_not_nil(fs:read("docs/en/configuration.md"))
end

function T:test_a_project_that_asks_for_both_audiences_gets_everything_in_a_merged_site()
  local fs, report = build_with({ title = "Shop docs", audiences = { "user", "maintainer" }, audience_sites = "merged" })
  self:assert_not_nil(fs:read("dist/en/configuration/index.html"))
  self:assert_equal(0, report.locales.en.unpublished)
end

function T:test_a_project_that_asks_for_both_audiences_gets_one_site_each_with_every_generated_page_in_its_own()
  local fs, report = build_with({ title = "Shop docs", audiences = { "user", "maintainer" } })
  self:assert_equal(2, #report.sites)
  -- The configuration reference is maintainer documentation; the guide below is labelled by the front matter.
  self:assert_not_nil(fs:read("dist/maintainer/en/configuration/index.html"))
  self:assert_nil(fs:read("dist/user/en/configuration/index.html"))
  self:assert_nil(fs:read("dist/user/assets/search-en.json"):find("1 to 65535", 1, true))
  self:assert_not_nil(fs:read("dist/maintainer/assets/search-en.json"):find("1 to 65535", 1, true))
  self:assert_nil(fs:read("dist/en/index.html"))
  self:assert_equal(0, report.locales.en.unpublished)
end

function T:test_a_wrong_audiences_option_fails_before_anything_is_written()
  local fs = doc.MemoryFileSystem({})
  local err = self:assert_error(function()
    ---@diagnostic disable-next-line: assign-type-mismatch  -- the wrong value is the point of the test
    generate({ site_configuration = { title = "x", audiences = { "everyone" } }, guides_dir = "docs",
      output_dir = "dist", file_system = fs, application = application(config_schema) })
  end)
  self:assert_true(core.is_instance_of(err, core.ConfigurationError))
  self:assert_equal("audiences[1]", err.context.field)
  self:assert_nil(fs:read("docs/en/configuration.md"))
end

function T:test_the_configuration_reference_never_prints_the_default_of_a_secret()
  local page = project.configuration_page(configuration_of({
    token = { type = "string", default = "hunter2-token", writeOnly = true },
    pass = { type = "string", default = "hunter2-pass", format = "password" },
    key = { type = "string", default = "hunter2-key", enum = { "hunter2-key", "other" } },
    db = { type = "object", properties = { password = { type = "string", default = "hunter2-db" } } },
    mode = { type = "string", default = "dev" },
  }), { secrets = { "key", "db.password" } })
  self:assert_nil(page:find("hunter2", 1, true), page)
  self:assert_not_nil(page:find("[redacted]", 1, true), page)
  self:assert_not_nil(page:find("`dev`", 1, true), "other defaults are kept")
end

local app_schema = {
  type = "object",
  properties = {
    port = { type = "integer", default = 8080 },
    database = { type = "object", properties = { password = { type = "string", default = "dev-password" } } },
  },
}

function T:test_build_reads_the_configuration_schema_and_the_secrets_from_the_application()
  local fs = doc.MemoryFileSystem({})
  generate(build_options(fs, { application = application(app_schema, { "database.password" }) }))
  local page = fs:read("docs/en/configuration.md")
  self:assert_not_nil(page:find("`database.password`", 1, true), page)
  self:assert_not_nil(page:find("`8080`", 1, true), page)
  self:assert_not_nil(page:find("[redacted]", 1, true), page)
  self:assert_nil(page:find("dev-password", 1, true), "the default of a secret is not printed")
end

function T:test_the_application_is_the_only_source_of_the_configuration_reference()
  local fs = doc.MemoryFileSystem({})
  generate(build_options(fs, { application = application(app_schema, {}), configuration = config_schema }))
  local page = fs:read("docs/en/configuration.md")
  self:assert_nil(page:find("`database.url`", 1, true), "a hand-passed schema is not an option")
  self:assert_not_nil(page:find("8080", 1, true))
end

function T:test_an_application_without_a_configuration_adds_no_page()
  local fs = doc.MemoryFileSystem({})
  generate(build_options(fs, { application = application(nil) }))
  self:assert_nil(fs:read("docs/en/configuration.md"))
end

function T:test_the_application_must_have_the_method_and_return_a_schema()
  local fs = doc.MemoryFileSystem({})
  local err = self:assert_error(function() generate(build_options(fs, { application = {} })) end)
  self:assert_not_nil(tostring(err):find("application", 1, true))
  err = self:assert_error(function() generate(build_options(fs, { application = application("no") })) end)
  self:assert_not_nil(tostring(err):find("configuration_schema", 1, true))
  self:assert_nil(fs:read("dist/en/index.html"), "nothing is written when an option is wrong")
  self:assert_nil(fs:read("docs/en/configuration.md"), "nothing is written when an option is wrong")
end

return T
