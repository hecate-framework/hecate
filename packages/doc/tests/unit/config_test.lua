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
  self:assert_equal("/", normalised.base)
  self:assert_equal("en", normalised.default_locale)
  self:assert_equal(1, #normalised.locales)
  self:assert_equal("en", normalised.locales[1].lang)
  self:assert_equal("README.md", normalised.exclude[1])
  self:assert_equal("2,3", table.concat(normalised.outline, ","))
  self:assert_nil(normalised.nav)
end

function T:test_base_path_is_normalised_to_start_and_end_with_a_slash()
  self:assert_equal("/hecate/", config.normalise({ title = "t", base = "/hecate" }).base)
  self:assert_equal("/hecate/", config.normalise({ title = "t", base = "/hecate///" }).base)
  self:assert_equal("/", config.normalise({ title = "t", base = "/" }).base)
end

function T:test_unsafe_urls_in_repository_and_nav_are_rejected()
  invalid(self, { title = "t", repository = "javascript:alert(1)" }, "repository")
  invalid(self, { title = "t", nav = { { text = "x", link = "javascript:alert(1)" } } }, "nav[1].link")
  config.normalise({ title = "t", repository = "https://github.com/x/y" })
end

function T:test_the_public_url_loses_its_trailing_slash()
  self:assert_equal("https://x.test", config.normalise({ title = "t", url = "https://x.test/" }).url)
end

function T:test_invalid_values_name_the_field()
  invalid(self, nil, "config")
  invalid(self, { title = "" }, "title")
  invalid(self, { title = "t", base = "hecate/" }, "base")
  invalid(self, { title = "t", description = 3 }, "description")
  invalid(self, { title = "t", locales = { { code = "en" }, { code = "en" } } }, "locales[2].code")
  invalid(self, { title = "t", locales = { { code = "e n" } } }, "locales[1].code")
  invalid(self, { title = "t", default_locale = "fr", locales = { { code = "en" } } }, "default_locale")
  invalid(self, { title = "t", nav = { { text = "x" } } }, "nav[1]")
  invalid(self, { title = "t", edit_link = "https://x.test/edit" }, "edit_link")
  invalid(self, { title = "t", source_edit_link = "https://x.test/edit" }, "source_edit_link")
  invalid(self, { title = "t", outline = { 7 } }, "outline")
end

function T:test_a_protocol_relative_or_malformed_base_is_rejected()
  invalid(self, { title = "t", base = "//evil.test/" }, "base")
  invalid(self, { title = "t", base = "//" }, "base")
  invalid(self, { title = "t", base = "/\\evil.test/" }, "base")
  invalid(self, { title = "t", base = "/a b/" }, "base")
  invalid(self, { title = "t", base = "/a?x=1/" }, "base")
  invalid(self, { title = "t", base = 3 }, "base")
  self:assert_equal("/a/b/", config.normalise({ title = "t", base = "/a/b" }).base)
end

function T:test_every_key_is_validated_by_type_and_shape()
  invalid(self, { title = "t", url = 3 }, "url")
  invalid(self, { title = "t", url = "javascript:alert(1)" }, "url")
  invalid(self, { title = "t", url = "/relative" }, "url")
  invalid(self, { title = "t", url = "https://" }, "url")
  invalid(self, { title = "t", exclude = "README.md" }, "exclude")
  invalid(self, { title = "t", exclude = { 1 } }, "exclude[1]")
  invalid(self, { title = "t", exclude = { "a/b.md" } }, "exclude[1]")
  invalid(self, { title = "t", outline = 3 }, "outline")
  invalid(self, { title = "t", outline = { "2" } }, "outline")
  invalid(self, { title = "t", outline = { 2.5 } }, "outline")
  invalid(self, { title = "t", sidebar = "x" }, "sidebar")
  invalid(self, { title = "t", sidebar = { guide = "a" } }, "sidebar.guide")
  invalid(self, { title = "t", sidebar = { guide = { 3 } } }, "sidebar.guide[1]")
  invalid(self, { title = "t", sidebar = { guide = { { link = 3 } } } }, "sidebar.guide[1].link")
  invalid(self, { title = "t", sidebar = { guide = { { text = 3 } } } }, "sidebar.guide[1].text")
  invalid(self, { title = "t", sidebar = { guide = { { items = "x" } } } }, "sidebar.guide[1].items")
  invalid(self, { title = "t", sidebar = { guide = { { items = { 3 } } } } }, "sidebar.guide[1].items[1]")
  invalid(self, { title = "t", strings = "x" }, "strings")
  invalid(self, { title = "t", strings = { en = "x" } }, "strings.en")
  invalid(self, { title = "t", strings = { en = { search = 3 } } }, "strings.en.search")
  invalid(self, { title = "t", repository = 3 }, "repository")
  invalid(self, { title = "t", edit_link = 3 }, "edit_link")
  invalid(self, { title = "t", nav = "x" }, "nav")
  invalid(self, { title = "t", locales = "en" }, "locales")
  invalid(self, { title = "t", default_locale = 3 }, "default_locale")
  invalid(self, { title = "t", locales = { { code = "en", label = 3 } } }, "locales[1].label")
  invalid(self, { title = "t", locales = { { code = "en", lang = 3 } } }, "locales[1].lang")
  local normalised = config.normalise({
    title = "t", url = "https://x.test/docs/", exclude = { "A.md" }, outline = { 2 },
    sidebar = { guide = { "a", { text = { en = "B" }, link = "b", items = { "c" } } } },
    strings = { en = { search = "Find" } },
  })
  self:assert_equal("https://x.test/docs", normalised.url)
  self:assert_equal("A.md", normalised.exclude[1])
end

function T:test_localise_falls_back_to_the_default_locale()
  self:assert_equal("x", config.localise("x", "fr", "en"))
  self:assert_equal("fr!", config.localise({ en = "en!", fr = "fr!" }, "fr", "en"))
  self:assert_equal("en!", config.localise({ en = "en!" }, "fr", "en"))
  self:assert_nil(config.localise(nil, "fr", "en"))
end

return T
