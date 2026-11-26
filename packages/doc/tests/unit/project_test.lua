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

-- The application is duck-typed: `hecate.doc` calls `configuration_schema()` and never requires `hecate.kernel`. The schema is the
-- only thing it gives: the secrets are marked in it (`writeOnly`).
local function application(schema)
  return { configuration_schema = function() return schema end }
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
  local fs = doc.MemoryFileSystem({ ["docs/maintainer/en/index.md"] = "# Shop\n\nWelcome.\n" })
  local report = doc.generate_project_documentation({
    site_configuration = { title = "Shop docs" },
    guides_dir = "docs", output_dir = "dist", file_system = fs, clean_output_dir = true, fail_on_problems = true,
    application = application(config_schema),
  })
  self:assert_equal(0, #report.problems, table.concat(report.problems, "\n"))
  self:assert_not_nil(fs:read("dist/maintainer/en/configuration/index.html"))
  self:assert_not_nil(fs:read("dist/maintainer/en/index.html"))
end

function T:test_build_reports_the_code_reference_of_the_project()
  local fs = doc.MemoryFileSystem({ ["shop/docs/maintainer/en/index.md"] = "# Shop\n\nWelcome.\n" })
  local report = doc.generate_project_documentation({
    site_configuration = { title = "Shop docs" }, project_dir = "shop", guides_dir = "docs", output_dir = "dist",
    file_system = fs, package_name = "shop",
  })
  self:assert_not_nil(report.code)
  if report.code.skipped then
    -- Skipped locally without LuaLS; CI installs it on every platform (lua tools/run.lua setup-luals).
    if os.getenv("CI") then self:fail("lua-language-server is not installed (CI installs it: lua tools/run.lua setup-luals)") end
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
  local fs = doc.MemoryFileSystem({ ["docs/maintainer/en/index.md"] = "# Shop\n" })
  -- A stray `document` option is not an option of the build: it is refused, and nothing below `api/` is written.
  local err = self:assert_error(function()
    doc.generate_project_documentation({ site_configuration = { title = "Shop" }, guides_dir = "docs", output_dir = "dist",
      file_system = fs, document = contract, application = application(config_schema) })
  end)
  self:assert_equal("document", err.context.argument)
  doc.generate_project_documentation({ site_configuration = { title = "Shop" }, guides_dir = "docs", output_dir = "dist",
    file_system = fs, application = application(config_schema) })
  for path in pairs(fs.files) do
    self:assert_nil(path:find("/api/", 1, true), path)
    self:assert_nil(path:find("listUsers", 1, true), path)
  end
  self:assert_not_nil(fs:read("docs/maintainer/en/configuration.md"))
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
  -- The home page of the tree of each audience that is built (the default is the maintainer tree alone).
  for _, audience in ipairs(options.audiences or { "maintainer" }) do
    fs:write("docs/" .. audience .. "/" .. locale .. "/index.md", "# Shop\n")
  end
  return options
end

local generate = doc.generate_project_documentation

function T:test_a_hand_written_guide_on_a_generated_path_is_never_overwritten_and_nothing_is_written()
  local fs = doc.MemoryFileSystem({ ["docs/maintainer/en/configuration.md"] = "# Mine\n" })
  local err = self:assert_error(function() generate(build_options(fs, { application = application(config_schema) })) end)
  self:assert_true(core.is_instance_of(err, doc.BuildError), tostring(err))
  self:assert_equal("# Mine\n", fs:read("docs/maintainer/en/configuration.md"))
  self:assert_nil(fs:read("dist/maintainer/en/index.html"), "the site was not built")
  self:assert_nil(fs:read("docs/maintainer/en/third-party-licences.md"), "no generated page was written")
end

function T:test_generated_pages_that_are_no_longer_produced_are_removed()
  local fs = doc.MemoryFileSystem({})
  generate(build_options(fs, { application = application(config_schema) }))
  self:assert_not_nil(fs:read("docs/maintainer/en/configuration.md"))
  generate(build_options(fs, {}))
  self:assert_nil(fs:read("docs/maintainer/en/configuration.md"))
  self:assert_not_nil(fs:read("docs/maintainer/en/index.md"), "guides stay")
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
  -- Without an application there is nothing to document: a hand-passed schema or secrets list is not an option, and says so.
  for _, name in ipairs({ "configuration", "secrets" }) do
    local fs = doc.MemoryFileSystem({})
    local err = self:assert_error(function() generate(build_options(fs, { [name] = config_schema })) end)
    self:assert_equal(name, err.context.argument)
    self:assert_nil(fs:read("docs/maintainer/en/configuration.md"))
  end
end

-- The defaults are those of the conventional layout of a project (OQ-143): `docs`, `docs/dist`, `src`.
function T:test_every_path_option_has_a_default_of_the_conventional_layout()
  local fs = doc.MemoryFileSystem({ ["docs/site.lua"] = 'return { title = "Shop" }', ["docs/maintainer/en/index.md"] = "# Shop\n" })
  local report = generate({ file_system = fs, application = application(config_schema) })
  self:assert_equal(0, #report.problems, table.concat(report.problems, "\n"))
  self:assert_not_nil(fs:read("docs/maintainer/en/configuration.md"), "guides_dir defaults to docs, read from docs/site.lua")
  self:assert_not_nil(fs:read("docs/dist/maintainer/en/configuration/index.html"), "output_dir defaults to docs/dist")
  self:assert_not_nil(fs:read("docs/dist/maintainer/en/index.html"))
end

function T:test_relative_paths_are_resolved_against_the_project_directory()
  local fs = doc.MemoryFileSystem({ ["acme/docs/site.lua"] = 'return { title = "Acme" }', ["acme/docs/maintainer/en/index.md"] = "# Acme\n",
    ["acme/config/site.lua"] = 'return { title = "Other" }' })
  generate({ file_system = fs, project_dir = "acme", application = application(config_schema) })
  self:assert_not_nil(fs:read("acme/docs/maintainer/en/configuration.md"))
  self:assert_not_nil(fs:read("acme/docs/dist/maintainer/en/index.html"))
  generate({ file_system = fs, project_dir = "acme", guides_dir = "docs", output_dir = "site",
    site_configuration_path = "config/site.lua" })
  self:assert_not_nil(fs:read("acme/site/maintainer/en/index.html"))
  self:assert_nil(fs:read("acme/docs/maintainer/en/configuration.md"), "no application: the stale reference is removed")
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
    locales = { { code = "fr" } } },
    application = application(config_schema) }))
  self:assert_not_nil(fs:read("docs/maintainer/fr/configuration.md"))
  self:assert_not_nil(fs:read("dist/maintainer/fr/configuration/index.html"))
  local other = doc.MemoryFileSystem({})
  generate(build_options(other, { site_configuration = { title = "S", default_locale = "fr", locales = { { code = "fr" } } },
    application = application(config_schema) }))
  self:assert_not_nil(other:read("docs/maintainer/fr/configuration.md"))
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

-- Audiences (OQ-144, owner decision of 2026-11-21): two content trees, two sites.
function T:test_the_configuration_reference_carries_no_audience_key()
  local meta = front_matter.parse(project.configuration_page(config_schema))
  self:assert_nil(meta.audience, "the tree it is written into is the audience")
  self:assert_equal(true, meta.generated)
end

local function trees(extra)
  local files = {
    ["docs/user/en/index.md"] = "# Shop\n\nWelcome, users.\n",
    ["docs/maintainer/en/index.md"] = "# Shop team\n\nWelcome, maintainers.\n",
    ["docs/maintainer/en/design.md"] = "# Design\n\nHow it works.\n",
  }
  for path, data in pairs(extra or {}) do files[path] = data end
  return doc.MemoryFileSystem(files)
end

local function build_trees(fs, extra)
  local options = { site_configuration = { title = "Shop docs" }, guides_dir = "docs", output_dir = "dist", file_system = fs,
    application = application(config_schema) }
  for key, value in pairs(extra or {}) do options[key] = value end
  if options.application == false then options.application = nil end
  return generate(options)
end

function T:test_a_project_builds_the_maintainer_tree_only_by_default()
  local fs = trees()
  local report = build_trees(fs, { fail_on_problems = true })
  self:assert_equal(0, #report.problems, table.concat(report.problems, "\n"))
  self:assert_equal(1, #report.sites)
  self:assert_equal("maintainer", report.sites[1].audience)
  self:assert_equal("maintainer", report.sites[1].directory)
  self:assert_not_nil(fs:read("dist/maintainer/en/index.html"))
  self:assert_not_nil(fs:read("dist/maintainer/en/configuration/index.html"))
  self:assert_not_nil(fs:read("dist/maintainer/en/design/index.html"))
  self:assert_not_nil(fs:read("dist/maintainer/assets/search-en.js"):find("1 to 65535", 1, true))
  -- The user tree is not listed: it is not built, nothing is written into it, and that is no error.
  self:assert_nil(fs:read("dist/user/en/index.html"))
  self:assert_nil(fs:read("dist/en/index.html"), "no site at the root of the output")
  self:assert_nil(fs:read("docs/user/en/configuration.md"))
  -- The root of the output holds the marker and a redirect to the first site.
  self:assert_not_nil(fs:read("dist/.hecate-doc-output"))
  self:assert_not_nil(fs:read("dist/index.html"):find('content="0; url=maintainer/en/index.html"', 1, true))
  self:assert_equal(3, report.locales.en.pages, "the home page, the design page and the configuration reference")
end

function T:test_a_project_that_asks_for_both_audiences_gets_two_sites_in_two_output_directories()
  local fs = trees()
  local report = build_trees(fs, { audiences = { "user", "maintainer" }, fail_on_problems = true })
  self:assert_equal(0, #report.problems, table.concat(report.problems, "\n"))
  self:assert_equal(2, #report.sites)
  self:assert_equal("user", report.sites[1].directory)
  self:assert_equal("maintainer", report.sites[2].directory)
  self:assert_not_nil(fs:read("dist/user/en/index.html"))
  self:assert_not_nil(fs:read("dist/maintainer/en/index.html"))
  -- The configuration reference is a maintainer page: it is in that tree and that site only.
  self:assert_not_nil(fs:read("docs/maintainer/en/configuration.md"))
  self:assert_nil(fs:read("docs/user/en/configuration.md"))
  self:assert_not_nil(fs:read("dist/maintainer/en/configuration/index.html"))
  self:assert_nil(fs:read("dist/user/en/configuration/index.html"))
  -- Independent search index, sitemap-free navigation and `404.html` per site, and nothing of the other tree in either.
  self:assert_nil(fs:read("dist/user/assets/search-en.js"):find("1 to 65535", 1, true))
  self:assert_nil(fs:read("dist/user/assets/search-en.js"):find("How it works", 1, true))
  self:assert_not_nil(fs:read("dist/maintainer/assets/search-en.js"):find("1 to 65535", 1, true))
  self:assert_nil(fs:read("dist/maintainer/assets/search-en.js"):find("Welcome, users", 1, true))
  self:assert_nil(fs:read("dist/user/404.html"):find("Design", 1, true))
  self:assert_not_nil(fs:read("dist/user/en/index.html"):find('href="../assets/theme.css"', 1, true), "the links of a site are relative to the page")
  self:assert_not_nil(fs:read("dist/maintainer/en/index.html"):find('href="../assets/theme.css"', 1, true))
  self:assert_not_nil(fs:read("dist/index.html"):find('content="0; url=user/en/index.html"', 1, true), "the first audience listed")
  -- The report adds the sites up: two files at the root of the output, and the files of each site.
  self:assert_equal(2 + report.sites[1].files + report.sites[2].files, report.files)
  self:assert_equal(report.sites[1].locales.en.pages + report.sites[2].locales.en.pages, report.locales.en.pages)
end

function T:test_a_listed_audience_whose_tree_does_not_exist_is_a_problem_and_a_tree_that_is_not_listed_is_not()
  local fs = doc.MemoryFileSystem({ ["docs/maintainer/en/index.md"] = "# Shop team\n" })
  local report = build_trees(fs, { audiences = { "user", "maintainer" } })
  self:assert_equal(1, #report.problems, table.concat(report.problems, "\n"))
  self:assert_true(report.problems[1]:find('audience "user" is listed in `audiences` but its content tree docs/user does not exist: add docs/user/en/index.md', 1, true) ~= nil,
    report.problems[1])
  self:assert_equal(1, #report.sites, "the tree that exists is built")
  self:assert_not_nil(fs:read("dist/maintainer/en/index.html"))
  self:assert_nil(fs:read("dist/user/en/index.html"))
  -- An error under `fail_on_problems`, after the site that exists is written.
  local strict = doc.MemoryFileSystem({ ["docs/maintainer/en/index.md"] = "# Shop team\n" })
  local err = self:assert_error(function() build_trees(strict, { audiences = { "user" }, fail_on_problems = true }) end)
  self:assert_true(core.is_instance_of(err, doc.BuildError))
  self:assert_true(tostring(err):find("add docs/user/en/index.md", 1, true) ~= nil, tostring(err))
  self:assert_nil(strict:read("dist/maintainer/en/index.html"), "the maintainer tree is not listed, so not built")
  -- A tree that is not listed and does not exist is no problem.
  local plain = build_trees(doc.MemoryFileSystem({ ["docs/maintainer/en/index.md"] = "# Shop team\n" }), { fail_on_problems = true })
  self:assert_equal(0, #plain.problems)
end

function T:test_each_tree_reports_its_own_missing_home_page()
  local fs = doc.MemoryFileSystem({ ["docs/user/en/guide.md"] = "# Guide\n", ["docs/maintainer/en/design.md"] = "# Design\n" })
  local report = build_trees(fs, { audiences = { "user", "maintainer" }, application = false })
  self:assert_equal(2, #report.problems, table.concat(report.problems, "\n"))
  self:assert_equal(1, #report.sites[1].problems)
  self:assert_equal(1, #report.sites[2].problems)
  self:assert_true(report.sites[1].problems[1]:find("add docs/user/en/index.md", 1, true) ~= nil, report.sites[1].problems[1])
  self:assert_true(report.sites[2].problems[1]:find("add docs/maintainer/en/index.md", 1, true) ~= nil, report.sites[2].problems[1])
  self:assert_true(report.problems[1]:find("^maintainer site: ") ~= nil or report.problems[1]:find("^user site: ") ~= nil, report.problems[1])
  -- A home page in one tree does not satisfy the other.
  local half = doc.MemoryFileSystem({ ["docs/user/en/index.md"] = "# Home\n", ["docs/maintainer/en/design.md"] = "# Design\n" })
  local second = build_trees(half, { audiences = { "user", "maintainer" }, application = false })
  self:assert_equal(1, #second.problems, table.concat(second.problems, "\n"))
  self:assert_true(second.problems[1]:find("add docs/maintainer/en/index.md", 1, true) ~= nil, second.problems[1])
end

function T:test_a_page_that_still_carries_the_audience_key_is_refused_and_nothing_is_written_to_the_output()
  local fs = trees({ ["docs/user/en/old.md"] = "---\ntitle: Old\naudience: user\n---\nx\n" })
  local err = self:assert_error(function() build_trees(fs, { audiences = { "user", "maintainer" } }) end)
  self:assert_true(core.is_instance_of(err, doc.BuildError), tostring(err))
  self:assert_true(tostring(err):find("docs/user/en/old.md", 1, true) ~= nil, tostring(err))
  self:assert_true(tostring(err):find("<guides_dir>/<audience>/<locale>/", 1, true) ~= nil, tostring(err))
  -- The trees are loaded before anything is written to the output: the maintainer tree is not written either.
  self:assert_nil(fs:read("dist/maintainer/en/index.html"))
  self:assert_nil(fs:read("dist/index.html"))
end

function T:test_the_site_configuration_is_shared_and_the_clean_option_empties_the_whole_output()
  local fs = trees()
  local options = { audiences = { "user", "maintainer" }, clean_output_dir = true,
    site_configuration = { title = "Shop docs", base_path = "/docs/", edit_link_template = "https://x.test/edit/docs/{path}" } }
  build_trees(fs, options)
  self:assert_not_nil(fs:read("dist/user/en/index.html"):find("Shop docs", 1, true))
  self:assert_not_nil(fs:read("dist/maintainer/en/index.html"):find("Shop docs", 1, true))
  self:assert_not_nil(fs:read("dist/user/en/index.html"):find('href="../assets/theme.css"', 1, true), "the base path builds no link")
  self:assert_not_nil(fs:read("dist/index.html"):find('url=user/en/index.html', 1, true))
  self:assert_nil(fs:read("dist/user/en/index.html"):find('href="/', 1, true), "no root-relative link")
  -- The edit link names the tree: the template of the project is relative to the guides directory.
  self:assert_not_nil(fs:read("dist/user/en/index.html"):find("https://x.test/edit/docs/user/en/index.md", 1, true))
  self:assert_not_nil(fs:read("dist/maintainer/en/design/index.html"):find("https://x.test/edit/docs/maintainer/en/design.md", 1, true))
  -- A second build with a single audience empties the site that is no longer built (the marker is at the root of the output).
  fs:write("dist/stale.txt", "old")
  build_trees(fs, { clean_output_dir = true, site_configuration = options.site_configuration })
  self:assert_nil(fs:read("dist/stale.txt"))
  self:assert_nil(fs:read("dist/user/en/index.html"))
  self:assert_not_nil(fs:read("dist/maintainer/en/index.html"))
  -- An output directory that is not ours is refused.
  local foreign = trees({ ["dist/mine.txt"] = "mine" })
  self:assert_error(function() build_trees(foreign, { clean_output_dir = true }) end)
  self:assert_equal("mine", foreign:read("dist/mine.txt"))
end

function T:test_the_audiences_option_is_a_closed_list_of_trees()
  local fs = trees()
  for _, bad in ipairs({ {}, "user", { "everyone" }, { "user", "user" }, { 1 }, { user = true } }) do
    local err = self:assert_error(function() build_trees(fs, { audiences = bad }) end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
    self:assert_equal("audiences", err.context.argument)
  end
  self:assert_nil(fs:read("dist/maintainer/en/index.html"), "nothing was built")
  -- The site configuration refuses what was removed from it, with what to do.
  for _, key in ipairs({ "audiences", "default_audience", "audience_sites" }) do
    local err = self:assert_error(function()
      build_trees(fs, { site_configuration = { title = "x", [key] = "user" } })
    end)
    self:assert_true(core.is_instance_of(err, core.ConfigurationError), key)
    self:assert_equal(key, err.context.field)
    self:assert_nil(fs:read("docs/maintainer/en/configuration.md"), "refused before anything is written")
  end
end

function T:test_the_configuration_reference_never_prints_the_default_of_a_secret()
  local page = project.configuration_page(configuration_of({
    token = { type = "string", default = "hunter2-token", writeOnly = true },
    pass = { type = "string", default = "hunter2-pass", format = "password" },
    key = { type = "string", writeOnly = true, default = "hunter2-key", enum = { "hunter2-key", "other" } },
    db = { type = "object", properties = { password = { type = "string", writeOnly = true, default = "hunter2-db" } } },
    mode = { type = "string", default = "dev" },
  }))
  self:assert_nil(page:find("hunter2", 1, true), page)
  self:assert_not_nil(page:find("[redacted]", 1, true), page)
  self:assert_not_nil(page:find("`dev`", 1, true), "other defaults are kept")
end

local app_schema = {
  type = "object",
  properties = {
    port = { type = "integer", default = 8080 },
    database = { type = "object", properties = { password = { type = "string", writeOnly = true, default = "dev-password" } } },
  },
}

function T:test_build_reads_the_configuration_schema_from_the_application_and_redacts_what_it_marks()
  local fs = doc.MemoryFileSystem({})
  generate(build_options(fs, { application = application(app_schema) }))
  local page = fs:read("docs/maintainer/en/configuration.md")
  self:assert_not_nil(page:find("`database.password`", 1, true), page)
  self:assert_not_nil(page:find("`8080`", 1, true), page)
  self:assert_not_nil(page:find("[redacted]", 1, true), page)
  self:assert_nil(page:find("dev-password", 1, true), "the default of a secret is not printed")
end

function T:test_the_application_is_the_only_source_of_the_configuration_reference()
  local fs = doc.MemoryFileSystem({})
  local err = self:assert_error(function()
    generate(build_options(fs, { application = application(app_schema), configuration = config_schema }))
  end)
  self:assert_equal("configuration", err.context.argument, "a hand-passed schema is not an option")
  generate(build_options(fs, { application = application(app_schema) }))
  local page = fs:read("docs/maintainer/en/configuration.md")
  self:assert_nil(page:find("`database.url`", 1, true))
  self:assert_not_nil(page:find("8080", 1, true))
end

function T:test_an_application_without_a_configuration_adds_no_page()
  local fs = doc.MemoryFileSystem({})
  generate(build_options(fs, { application = application(nil) }))
  self:assert_nil(fs:read("docs/maintainer/en/configuration.md"))
end

function T:test_the_application_must_have_the_method_and_return_a_schema()
  local fs = doc.MemoryFileSystem({})
  local err = self:assert_error(function() generate(build_options(fs, { application = {} })) end)
  self:assert_not_nil(tostring(err):find("application", 1, true))
  err = self:assert_error(function() generate(build_options(fs, { application = application("no") })) end)
  self:assert_not_nil(tostring(err):find("configuration_schema", 1, true))
  self:assert_nil(fs:read("dist/maintainer/en/index.html"), "nothing is written when an option is wrong")
  self:assert_nil(fs:read("docs/maintainer/en/configuration.md"), "nothing is written when an option is wrong")
end

return T
