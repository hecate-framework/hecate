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

function T:test_localise_falls_back_to_the_default_locale()
  self:assert_equal("x", config.localise("x", "fr", "en"))
  self:assert_equal("fr!", config.localise({ en = "en!", fr = "fr!" }, "fr", "en"))
  self:assert_equal("en!", config.localise({ en = "en!" }, "fr", "en"))
  self:assert_nil(config.localise(nil, "fr", "en"))
end

return T
