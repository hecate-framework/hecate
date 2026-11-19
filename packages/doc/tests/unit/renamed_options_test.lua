-- The vocabulary rule of OQ-143 (every name says what it is; `_dir` a directory, `_path` a file; British spelling
-- `licence` for our own identifiers), applied to the whole public API with no alias: the new names work, the old ones
-- do nothing, and `internal.renamed_options` records old to new.
local test = require("harness.test")
local doc = require("hecate.doc")
local config = require("hecate.doc.config")
local core = require("hecate.core")
local reference = require("hecate.doc.reference")
local reference_site = require("hecate.doc.reference_site")
local renamed = require("hecate.doc.internal.renamed_options")
local T = test.Case("RenamedOptionsTest")

-- A valid value of each key of `site.lua`, to check that the new name is the one `normalise` reads.
local VALID = {
  logo_path = "a.svg", favicon_path = "a.svg", stylesheet_path = "a.css", generate_llms_txt = true, base_path = "/x/",
  site_origin = "https://x.test", repository_url = "https://github.com/x/y", edit_link_template = "https://x.test/{path}",
  source_edit_link_template = "https://x.test/{path}", exclude_file_names = { "A.md" }, outline_levels = { 2 },
  interface_strings = { en = { search = "Find" } }, top_links = { { text = "x", link = "a/" } },
}

function T:test_site_keys_are_the_ones_the_site_configuration_reads()
  local seen = {}
  for old, new in pairs(renamed.site_keys) do
    self:assert_equal("string", type(new), old)
    self:assert_true(old ~= new, old)
    self:assert_not_nil(VALID[new], "no sample value for " .. new)
    local normalised = config.normalise({ title = "t", [new] = VALID[new] })
    -- `logo_path` and `favicon_path` keep their `{ light, dark }` form after normalisation.
    self:assert_not_nil(normalised[new], new)
    self:assert_nil(normalised[old], old .. " is not an alias")
    seen[new] = true
  end
  for key in pairs(VALID) do self:assert_true(seen[key], key .. " has an old name in site_keys") end
end

function T:test_an_old_site_key_is_refused_with_its_replacement()
  for old, new in pairs(renamed.site_keys) do
    local sample = ({ colors = "a.css", theme = "a.css", llms = true, base = "/x/", url = "https://x.test",
      repository = "https://github.com/x/y", edit_link = "https://x.test/{path}",
      source_edit_link = "https://x.test/{path}", exclude = { "A.md" }, outline = { 2 }, strings = { en = {} },
      nav = { { text = "x", link = "a/" } }, logo = "a.svg", favicon = "a.svg" })[old]
    self:assert_not_nil(sample, "no sample value for " .. old)
    local err = self:assert_error(function() config.normalise({ title = "t", [old] = sample }) end)
    self:assert_true(core.is_instance_of(err, core.ConfigurationError), old .. ": " .. tostring(err))
    self:assert_equal(old, err.context.field)
    self:assert_not_nil(tostring(err):find("`" .. old .. "` was renamed `" .. new .. "`", 1, true), tostring(err))
  end
end

function T:test_a_typo_in_a_site_key_is_refused_with_a_suggestion()
  local cases = { { "audience", "audiences" }, { "logos", "logo_path" }, { "default_audiences", "default_audience" },
    { "titel", "title" }, { "base_paht", "base_path" } }
  for _, case in ipairs(cases) do
    local err = self:assert_error(function() config.normalise({ title = "t", [case[1]] = "x" }) end)
    self:assert_true(core.is_instance_of(err, core.ConfigurationError), case[1])
    self:assert_equal(case[1], err.context.field)
    self:assert_not_nil(tostring(err):find("did you mean `" .. case[2] .. "`", 1, true), tostring(err))
  end
  local far = self:assert_error(function() config.normalise({ title = "t", zzzzzz = 1 }) end)
  self:assert_equal("zzzzzz", far.context.field)
  self:assert_nil(tostring(far):find("did you mean", 1, true))
  local numeric = self:assert_error(function() config.normalise({ title = "t", [1] = "x" }) end)
  self:assert_true(core.is_instance_of(numeric, core.ConfigurationError))
  -- A configuration that was normalised once is still valid.
  local once = config.normalise({ title = "t", audiences = { "user" }, logo_path = "a.svg", locales = { { code = "fr", label = "Français", lang = "fr" } },
    default_locale = "fr", top_links = { { text = "x", link = "a/" } } })
  self:assert_equal("t", config.normalise(once).title)
end

function T:test_the_renamed_options_have_a_new_name_or_a_removal_with_its_replacement()
  for section, entries in pairs(renamed.options) do
    for old, entry in pairs(entries) do
      local label = section .. "." .. old
      if type(entry) == "string" then
        self:assert_true(entry ~= old and entry:find("^[a-z_]+$") ~= nil, label)
      else
        self:assert_equal("table", type(entry), label)
        self:assert_equal("string", type(entry.removed), label)
        self:assert_true(#entry.removed > 0, label)
      end
    end
  end
  local entry = renamed.options.generate_project_documentation
  self:assert_equal("guides_dir", entry.source)
  self:assert_equal("output_dir", entry.out)
  self:assert_equal("fail_on_problems", entry.strict)
  self:assert_equal("clean_output_dir", entry.clean)
  self:assert_equal("site_configuration", entry.config)
  self:assert_equal("file_system", entry.fs)
  self:assert_equal("licences_page", entry.licenses)
  for _, removed in ipairs({ "pages", "guide_texts", "configuration", "secrets", "code" }) do
    self:assert_equal("table", type(entry[removed]), removed)
  end
  self:assert_equal("locale_dir", renamed.options.reference_site.out)
  self:assert_equal("pages_dir", renamed.options.reference.root)
end

function T:test_the_module_of_the_licences_page_is_spelled_with_a_c()
  self:assert_equal("function", type(require("hecate.doc.licences").read))
  self:assert_false(pcall(require, "hecate.doc.licenses"))
end

function T:test_the_entry_points_carry_the_new_names_and_no_alias()
  self:assert_equal("function", type(doc.load_site_configuration))
  self:assert_equal("function", type(doc.normalise_site_configuration))
  ---@diagnostic disable-next-line: undefined-field  -- the old name is absent on purpose
  self:assert_nil(doc.load_config)
  ---@diagnostic disable-next-line: undefined-field
  self:assert_nil(doc.normalise_config)
  self:assert_equal("T", doc.load_site_configuration(doc.MemoryFileSystem({ ["s.lua"] = 'return { title = "T" }' }), "s.lua").title)
  self:assert_equal("/", doc.normalise_site_configuration({ title = "t" }).base_path)
end

function T:test_every_old_option_name_is_refused_naming_its_replacement()
  local memory = doc.MemoryFileSystem({ ["c/en/index.md"] = "---\ntitle: Home\n---\nhi\n" })
  local base = { site_configuration = { title = "t" }, guides_dir = "c", output_dir = "o", file_system = memory }
  local cases = { { "out", "output_dir" }, { "source", "guides_dir" }, { "fs", "file_system" }, { "strict", "fail_on_problems" },
    { "clean", "clean_output_dir" }, { "config", "site_configuration" }, { "theme_fs", "theme_file_system" } }
  for _, case in ipairs(cases) do
    local options = {}
    for key, value in pairs(base) do options[key] = value end
    options[case[1]] = "x"
    local err = self:assert_error(function() doc.build(options) end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError), case[1])
    self:assert_equal(case[1], err.context.argument)
    self:assert_not_nil(tostring(err):find(("option `%s` was renamed `%s`"):format(case[1], case[2]), 1, true), tostring(err))
  end
  local typo = self:assert_error(function() doc.build({ site_configuration = { title = "t" }, guides_dir = "c", output_dir = "o",
    file_system = memory, fail_on_problem = true }) end)
  self:assert_equal("fail_on_problem", typo.context.argument)
  self:assert_not_nil(tostring(typo):find("did you mean `fail_on_problems`", 1, true), tostring(typo))
  self:assert_nil(memory:read("o/en/index.html"), "nothing was built")
end

function T:test_the_builder_wants_the_new_option_names()
  local memory = doc.MemoryFileSystem({ ["c/en/index.md"] = "---\ntitle: Home\n---\nhi\n" })
  ---@diagnostic disable: missing-fields  -- the old option names are given on purpose
  local err = self:assert_error(function() doc.build({ site_configuration = { title = "t" }, source = "c", out = "o", fs = memory }) end)
  self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
  err = self:assert_error(function() doc.Site({ config = { title = "t" }, source = "c", fs = memory }) end)
  self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
  ---@diagnostic enable: missing-fields
  local report = doc.build({ site_configuration = { title = "t" }, guides_dir = "c", output_dir = "o", file_system = memory })
  self:assert_true(report.files > 0)
  self:assert_not_nil(memory:read("o/en/index.html"))
  self:assert_equal("t", doc.Site({ site_configuration = { title = "t" }, guides_dir = "c", file_system = memory }).site_configuration.title)
end

function T:test_reference_pages_go_below_pages_dir()
  local fixtures = (debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/unit/")) .. "/fixtures/reference"
  local file = assert(io.open(fixtures .. "/export.json", "rb"))
  local export = file:read("a")
  file:close()
  local result = reference.generate({ { name = "demo", export = export } }, { pages_dir = "api" })
  self:assert_true(#result.order > 0)
  for _, path in ipairs(result.order) do self:assert_true(path:find("^api/demo/") ~= nil, path) end
  local default = reference.generate({ { name = "demo", export = export } })
  for _, path in ipairs(default.order) do self:assert_true(path:find("^reference/demo/") ~= nil, path) end
  local err = self:assert_error(function() reference.generate({ { name = "demo", export = export } }, { root = "api" }) end)
  self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
  self:assert_equal("root", err.context.argument)
  self:assert_not_nil(tostring(err):find("renamed `pages_dir`", 1, true), tostring(err))
end

function T:test_the_code_reference_asks_for_the_new_names()
  local memory = doc.MemoryFileSystem({})
  ---@diagnostic disable-next-line: missing-fields  -- the old option names are given on purpose
  local err = self:assert_error(function() reference_site.run({ root = ".", out = "en", fs = memory }) end)
  self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
  for _, name in ipairs({ "project_dir", "locale_dir", "file_system" }) do
    self:assert_true(tostring(err):find(name, 1, true) ~= nil, name .. " in " .. tostring(err))
  end
end

return T
