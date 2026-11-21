local test = require("harness.test")
local config = require("hecate.doc.config")
local core = require("hecate.core")
local T = test.Case("ConfigTest")

local function invalid(self, raw, field)
  local err = self:assert_error(function() config.normalise(raw) end)
  self:assert_true(core.is_instance_of(err, core.ConfigurationError), tostring(err))
  self:assert_equal(field, err.context.field)
end

function T:test_defaults()
  local normalised = config.normalise({ title = "t" })
  self:assert_equal("/", normalised.base_path)
  self:assert_equal("en", normalised.default_locale)
  self:assert_equal(1, #normalised.locales)
  self:assert_equal("en", normalised.locales[1].lang)
  self:assert_equal("README.md", normalised.exclude_file_names[1])
  self:assert_equal("2,3", table.concat(normalised.outline_levels, ","))
  self:assert_nil(normalised.top_links)
end

function T:test_base_path_is_normalised_to_start_and_end_with_a_slash()
  self:assert_equal("/hecate/", config.normalise({ title = "t", base_path = "/hecate" }).base_path)
  self:assert_equal("/hecate/", config.normalise({ title = "t", base_path = "/hecate///" }).base_path)
  self:assert_equal("/", config.normalise({ title = "t", base_path = "/" }).base_path)
end

function T:test_unsafe_urls_in_repository_and_nav_are_rejected()
  invalid(self, { title = "t", repository_url = "javascript:alert(1)" }, "repository_url")
  invalid(self, { title = "t", top_links = { { text = "x", link = "javascript:alert(1)" } } }, "top_links[1].link")
  config.normalise({ title = "t", repository_url = "https://github.com/x/y" })
end

function T:test_the_public_url_loses_its_trailing_slash()
  self:assert_equal("https://x.test", config.normalise({ title = "t", site_origin = "https://x.test/" }).site_origin)
end

function T:test_invalid_values_name_the_field()
  invalid(self, nil, "site_configuration")
  invalid(self, { title = "" }, "title")
  invalid(self, { title = "t", base_path = "hecate/" }, "base_path")
  invalid(self, { title = "t", description = 3 }, "description")
  invalid(self, { title = "t", locales = { { code = "en" }, { code = "en" } } }, "locales[2].code")
  invalid(self, { title = "t", locales = { { code = "e n" } } }, "locales[1].code")
  invalid(self, { title = "t", default_locale = "fr", locales = { { code = "en" } } }, "default_locale")
  invalid(self, { title = "t", top_links = { { text = "x" } } }, "top_links[1]")
  invalid(self, { title = "t", edit_link_template = "https://x.test/edit" }, "edit_link_template")
  invalid(self, { title = "t", source_edit_link_template = "https://x.test/edit" }, "source_edit_link_template")
  invalid(self, { title = "t", outline_levels = { 7 } }, "outline_levels")
end

function T:test_a_protocol_relative_or_malformed_base_is_rejected()
  invalid(self, { title = "t", base_path = "//evil.test/" }, "base_path")
  invalid(self, { title = "t", base_path = "//" }, "base_path")
  invalid(self, { title = "t", base_path = "/\\evil.test/" }, "base_path")
  invalid(self, { title = "t", base_path = "/a b/" }, "base_path")
  invalid(self, { title = "t", base_path = "/a?x=1/" }, "base_path")
  invalid(self, { title = "t", base_path = 3 }, "base_path")
  self:assert_equal("/a/b/", config.normalise({ title = "t", base_path = "/a/b" }).base_path)
end

function T:test_every_key_is_validated_by_type_and_shape()
  invalid(self, { title = "t", site_origin = 3 }, "site_origin")
  invalid(self, { title = "t", site_origin = "javascript:alert(1)" }, "site_origin")
  invalid(self, { title = "t", site_origin = "/relative" }, "site_origin")
  invalid(self, { title = "t", site_origin = "https://" }, "site_origin")
  invalid(self, { title = "t", exclude_file_names = "README.md" }, "exclude_file_names")
  invalid(self, { title = "t", exclude_file_names = { 1 } }, "exclude_file_names[1]")
  invalid(self, { title = "t", exclude_file_names = { "a/b.md" } }, "exclude_file_names[1]")
  invalid(self, { title = "t", outline_levels = 3 }, "outline_levels")
  invalid(self, { title = "t", outline_levels = { "2" } }, "outline_levels")
  invalid(self, { title = "t", outline_levels = { 2.5 } }, "outline_levels")
  invalid(self, { title = "t", sidebar = "x" }, "sidebar")
  invalid(self, { title = "t", sidebar = { guide = "a" } }, "sidebar.guide")
  invalid(self, { title = "t", sidebar = { guide = { 3 } } }, "sidebar.guide[1]")
  invalid(self, { title = "t", sidebar = { guide = { { link = 3 } } } }, "sidebar.guide[1].link")
  invalid(self, { title = "t", sidebar = { guide = { { text = 3 } } } }, "sidebar.guide[1].text")
  invalid(self, { title = "t", sidebar = { guide = { { items = "x" } } } }, "sidebar.guide[1].items")
  invalid(self, { title = "t", sidebar = { guide = { { items = { 3 } } } } }, "sidebar.guide[1].items[1]")
  invalid(self, { title = "t", interface_strings = "x" }, "interface_strings")
  invalid(self, { title = "t", interface_strings = { en = "x" } }, "interface_strings.en")
  invalid(self, { title = "t", interface_strings = { en = { search = 3 } } }, "interface_strings.en.search")
  invalid(self, { title = "t", repository_url = 3 }, "repository_url")
  invalid(self, { title = "t", edit_link_template = 3 }, "edit_link_template")
  invalid(self, { title = "t", top_links = "x" }, "top_links")
  invalid(self, { title = "t", locales = "en" }, "locales")
  invalid(self, { title = "t", default_locale = 3 }, "default_locale")
  invalid(self, { title = "t", locales = { { code = "en", label = 3 } } }, "locales[1].label")
  invalid(self, { title = "t", locales = { { code = "en", lang = 3 } } }, "locales[1].lang")
  local normalised = config.normalise({
    title = "t", site_origin = "https://x.test/docs/", exclude_file_names = { "A.md" }, outline_levels = { 2 },
    sidebar = { guide = { "a", { text = { en = "B" }, link = "b", items = { "c" } } } },
    interface_strings = { en = { search = "Find" } },
  })
  self:assert_equal("https://x.test/docs", normalised.site_origin)
  self:assert_equal("A.md", normalised.exclude_file_names[1])
end

function T:test_localise_falls_back_to_the_default_locale()
  self:assert_equal("x", config.localise("x", "fr", "en"))
  self:assert_equal("fr!", config.localise({ en = "en!", fr = "fr!" }, "fr", "en"))
  self:assert_equal("en!", config.localise({ en = "en!" }, "fr", "en"))
  self:assert_nil(config.localise(nil, "fr", "en"))
end

function T:test_logo_and_theme()
  local normalised = config.normalise({ title = "t", logo_path = "a.svg", stylesheet_path = "c.css" })
  self:assert_equal("a.svg", normalised.logo_path.light)
  self:assert_nil(normalised.logo_path.dark)
  self:assert_equal("c.css", normalised.stylesheet_path)
  local both = config.normalise({ title = "t", logo_path = { light = "a.svg", dark = "b.svg" } })
  self:assert_equal("b.svg", both.logo_path.dark)
  invalid(self, { title = "t", logo_path = "../a.svg" }, "logo_path")
  invalid(self, { title = "t", logo_path = "https://x.test/a.svg" }, "logo_path")
  invalid(self, { title = "t", logo_path = { dark = "b.svg" } }, "logo_path.light")
  invalid(self, { title = "t", stylesheet_path = "/abs.css" }, "stylesheet_path")
  invalid(self, { title = "t", stylesheet_path = 3 }, "stylesheet_path")
  invalid(self, { title = "t", stylesheet_path = "style.txt" }, "stylesheet_path")
  invalid(self, { title = "t", stylesheet_path = "style" }, "stylesheet_path")
  self:assert_equal("fonts/Own.CSS", config.normalise({ title = "t", stylesheet_path = "fonts/Own.CSS" }).stylesheet_path)
end

function T:test_sidebar_marker_is_an_opt_in_boolean()
  self:assert_equal(false, config.normalise({ title = "t" }).sidebar_marker)
  self:assert_equal(true, config.normalise({ title = "t", sidebar_marker = true }).sidebar_marker)
  self:assert_equal(false, config.normalise({ title = "t", sidebar_marker = false }).sidebar_marker)
  invalid(self, { title = "t", sidebar_marker = "yes" }, "sidebar_marker")
  invalid(self, { title = "t", sidebar_marker = 1 }, "sidebar_marker")
end

function T:test_favicon_is_a_file_of_public_with_a_known_type()
  self:assert_nil(config.normalise({ title = "t" }).favicon_path)
  local single = config.normalise({ title = "t", favicon_path = "icons/a.svg" }).favicon_path
  self:assert_not_nil(single)
  ---@cast single -nil
  self:assert_equal("icons/a.svg", single.light)
  self:assert_nil(single.dark)
  local both = config.normalise({ title = "t", favicon_path = { light = "a.png", dark = "b.ICO" } }).favicon_path
  self:assert_not_nil(both)
  ---@cast both -nil
  self:assert_equal("a.png", both.light)
  self:assert_equal("b.ICO", both.dark)
  invalid(self, { title = "t", favicon_path = "../a.svg" }, "favicon_path")
  invalid(self, { title = "t", favicon_path = "https://x.test/a.svg" }, "favicon_path")
  invalid(self, { title = "t", favicon_path = ".hidden.svg" }, "favicon_path")
  invalid(self, { title = "t", favicon_path = "a.gif" }, "favicon_path")
  invalid(self, { title = "t", favicon_path = "a" }, "favicon_path")
  invalid(self, { title = "t", favicon_path = 3 }, "favicon_path")
  invalid(self, { title = "t", favicon_path = { dark = "b.svg" } }, "favicon_path.light")
  invalid(self, { title = "t", favicon_path = { light = "a.svg", dark = "../b.svg" } }, "favicon_path.dark")
  invalid(self, { title = "t", favicon_path = { light = "a.svg", dark = "b.txt" } }, "favicon_path.dark")
end

function T:test_logo_and_theme_paths_are_plain_files_of_public()
  for _, bad in ipairs({ "", ".", "..", "a/..", "a/./b", "a//b", "a\\b", "a?b", "C:/x", "%2e%2e/x", "/abs.svg", "a/", ".hidden.svg",
    "dir/.x/logo_path.svg", "../x", "a#b" }) do
    invalid(self, { title = "t", logo_path = bad }, "logo_path")
    invalid(self, { title = "t", stylesheet_path = bad }, "stylesheet_path")
    invalid(self, { title = "t", logo_path = { light = "ok.svg", dark = bad } }, "logo_path.dark")
  end
  invalid(self, { title = "t", logo_path = 3 }, "logo_path")
  invalid(self, { title = "t", logo_path = { dark = "d.svg" } }, "logo_path.light")
  self:assert_equal("my logo_path.svg", config.normalise({ title = "t", logo_path = "my logo_path.svg" }).logo_path.light)
end

function T:test_the_site_configuration_has_no_audience_key()
  -- OQ-144 (owner decision of 2026-11-21): one site configuration for every audience tree, and no audience in it.
  local normalised = config.normalise({ title = "t" }) --[[@as table]]
  self:assert_nil(normalised.audiences)
  self:assert_nil(normalised.default_audience)
  self:assert_nil(normalised.audience_sites)
  for _, key in ipairs({ "audiences", "default_audience", "audience_sites" }) do
    invalid(self, { title = "t", [key] = "user" }, key)
  end
end

function T:test_llms_is_off_unless_asked_and_must_be_a_boolean()
  self:assert_equal(false, config.normalise({ title = "t" }).generate_llms_txt)
  self:assert_equal(true, config.normalise({ title = "t", generate_llms_txt = true }).generate_llms_txt)
  self:assert_equal(false, config.normalise({ title = "t", generate_llms_txt = false }).generate_llms_txt)
  invalid(self, { title = "t", generate_llms_txt = "yes" }, "generate_llms_txt")
  invalid(self, { title = "t", generate_llms_txt = 1 }, "generate_llms_txt")
  invalid(self, { title = "t", generate_llms_txt = {} }, "generate_llms_txt")
end

return T
