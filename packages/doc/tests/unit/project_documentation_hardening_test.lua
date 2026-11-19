---@diagnostic disable: need-check-nil  -- tests read files they have just built; a nil fails the assertion that follows
-- `generate_project_documentation` and `build` on a tree that is data of the project: overlap of directories, writes through
-- links, Windows paths, strict mode, closed lists of options, empty sites.
local test = require("harness.test")
local doc = require("hecate.doc")
local core = require("hecate.core")
local options_module = require("hecate.doc.internal.options")
local project_documentation = require("hecate.doc.internal.project_documentation")
local T = test.Case("ProjectDocumentationHardeningTest")

local generate = doc.generate_project_documentation

local application = { configuration_schema = function() return { type = "object", properties = { a = { type = "string" } } } end }

local function files(extra)
  local result = { ["docs/en/index.md"] = "# Home\n" }
  for path, data in pairs(extra or {}) do result[path] = data end
  return result
end

local function options(fs, extra)
  local result = { site_configuration = { title = "Shop" }, file_system = fs }
  for key, value in pairs(extra or {}) do result[key] = value end
  return result
end

local function snapshot(fs)
  local keys = {}
  for path, data in pairs(fs.files) do keys[#keys + 1] = path .. "=" .. data end
  table.sort(keys)
  return table.concat(keys, "\n")
end

local function refused(self, fs, extra, argument)
  local before = snapshot(fs)
  local err = self:assert_error(function() generate(options(fs, extra)) end)
  self:assert_true(core.is_instance_of(err, core.ArgumentError), tostring(err))
  self:assert_equal(argument, err.context.argument, tostring(err))
  self:assert_equal(before, snapshot(fs), "nothing was written")
  return tostring(err)
end

-- Overlap ----------------------------------------------------------------------------------------------------------

function T:test_the_output_may_not_be_the_guides_or_hold_them()
  for _, case in ipairs({
    { guides_dir = "docs", output_dir = "docs" }, { guides_dir = "docs", output_dir = "./docs/" },
    { guides_dir = "docs", output_dir = "." }, { guides_dir = "docs/guides", output_dir = "docs" },
    { guides_dir = "docs", output_dir = ".." }, { guides_dir = "a/docs", output_dir = "a" },
  }) do
    local fs = doc.MemoryFileSystem(files({ ["docs/guides/en/index.md"] = "# H\n", ["a/docs/en/index.md"] = "# H\n" }))
    refused(self, fs, case, "output_dir")
  end
end

function T:test_the_output_may_not_be_the_project_directory_or_hold_it()
  local fs = doc.MemoryFileSystem(files({ ["acme/docs/en/index.md"] = "# H\n" }))
  refused(self, fs, { project_dir = "acme", guides_dir = "docs", output_dir = "../acme" }, "output_dir")
  refused(self, fs, { project_dir = "acme/sub", guides_dir = "../docs", output_dir = ".." }, "output_dir")
  refused(self, fs, { project_dir = "acme", guides_dir = "docs", output_dir = "." }, "output_dir")
end

function T:test_the_output_may_not_overlap_the_sources()
  local fs = doc.MemoryFileSystem(files({ ["src/hecate/x.lua"] = "return {}" }))
  for _, output_dir in ipairs({ "src", "src/dist", "." }) do
    refused(self, fs, { guides_dir = "docs", output_dir = output_dir }, "output_dir")
  end
  refused(self, fs, { guides_dir = "docs", output_dir = "dist", sources_dir = "dist/lua" }, "output_dir")
  refused(self, fs, { guides_dir = "docs", output_dir = "lib", sources_dir = "lib/src" }, "output_dir")
end

function T:test_the_default_layout_stays_allowed()
  local fs = doc.MemoryFileSystem(files({ ["docs/site.lua"] = 'return { title = "Shop" }' }))
  local report = generate({ file_system = fs })
  self:assert_not_nil(fs:read("docs/dist/en/index.html"), "the output below the guides")
  self:assert_equal(0, #report.problems, table.concat(report.problems, "\n"))
  local elsewhere = doc.MemoryFileSystem(files({}))
  generate(options(elsewhere, { guides_dir = "docs", output_dir = "build/site" }))
  self:assert_not_nil(elsewhere:read("build/site/en/index.html"))
end

function T:test_the_plain_builder_refuses_an_output_that_holds_the_guides()
  for _, output_dir in ipairs({ "c", "./c/", ".", "..", "/" }) do
    local fs = doc.MemoryFileSystem({ ["c/en/index.md"] = "# H\n" })
    local err = self:assert_error(function()
      doc.build({ site_configuration = { title = "T" }, guides_dir = "c", output_dir = output_dir, file_system = fs,
        clean_output_dir = true })
    end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError), output_dir .. ": " .. tostring(err))
    self:assert_equal("output_dir", err.context.argument)
    self:assert_not_nil(fs:read("c/en/index.md"), "the guides are intact")
  end
  local ok = pcall(doc.build, { site_configuration = { title = "T" }, guides_dir = "c", output_dir = "c/dist",
    file_system = doc.MemoryFileSystem({ ["c/en/index.md"] = "# H\n" }) })
  self:assert_true(ok, "below the guides is the default layout")
end

-- Writes through links ---------------------------------------------------------------------------------------------

function T:test_a_generated_page_is_never_written_through_a_link()
  for _, target in ipairs({ "outside/authorized_keys", "docs/en/other.md" }) do
    local fs = doc.MemoryFileSystem(files({ ["docs/en/other.md"] = "# Other\n" }))
    fs:link("docs/en/configuration.md", target)
    local before = fs.files[target]
    local err = self:assert_error(function()
      generate(options(fs, { guides_dir = "docs", output_dir = "dist", application = application }))
    end)
    self:assert_true(core.is_instance_of(err, doc.BuildError), tostring(err))
    self:assert_not_nil(tostring(err):find("symbolic link", 1, true), tostring(err))
    self:assert_equal(before, fs.files[target], target .. ": the target is untouched (a dangling one is not created)")
    self:assert_nil(fs:read("dist/en/index.html"), "nothing was built")
  end
end

function T:test_the_locale_directory_of_the_guides_may_not_be_a_link()
  local fs = doc.MemoryFileSystem({ ["real/index.md"] = "# H\n" })
  fs:link("docs/en", "real")
  local err = self:assert_error(function()
    generate(options(fs, { guides_dir = "docs", output_dir = "dist", application = application }))
  end)
  self:assert_true(core.is_instance_of(err, doc.BuildError), tostring(err))
  self:assert_nil(fs:read("real/configuration.md"), "nothing was written through the link")
end

function T:test_the_build_never_writes_an_output_file_through_a_link()
  for _, link in ipairs({ "o/en/index.html", "o/en", "o/assets", "o/index.html", "o/en/guide" }) do
    local fs = doc.MemoryFileSystem({ ["c/en/index.md"] = "# H\n", ["c/en/guide/a.md"] = "# A\n", ["victim/file"] = "VICTIM" })
    fs:link(link, link:find("/en/index") and "victim/file" or "victim")
    local err = self:assert_error(function()
      doc.build({ site_configuration = { title = "T" }, guides_dir = "c", output_dir = "o", file_system = fs })
    end)
    self:assert_true(core.is_instance_of(err, doc.BuildError), link .. ": " .. tostring(err))
    self:assert_equal("VICTIM", fs.files["victim/file"], link)
    for path in pairs(fs.files) do self:assert_true(path:sub(1, 6) ~= "victim" or path == "victim/file", path) end
  end
end

function T:test_a_link_at_the_place_of_a_stale_page_is_left_alone()
  local fs = doc.MemoryFileSystem(files({ ["elsewhere/page.md"] = "---\ngenerated: true\n---\n# G\n" }))
  fs:link("docs/en/configuration.md", "elsewhere/page.md")
  generate(options(fs, { guides_dir = "docs", output_dir = "dist" }))
  self:assert_true(fs:is_link("docs/en/configuration.md"), "not ours: not removed")
  self:assert_not_nil(fs:read("elsewhere/page.md"))
end

function T:test_the_code_reference_directory_with_a_link_is_left_alone()
  local reference_site = require("hecate.doc.reference_site")
  local fs = doc.MemoryFileSystem({ ["outside/keep.md"] = "KEEP" })
  fs:link("en/reference/demo/link.md", "outside/keep.md")
  local problems = reference_site.write(fs, "en", { pages = { ["reference/demo/index.md"] = "x" }, order = { "reference/demo/index.md" }, problems = {} }, { "demo" })
  self:assert_equal(1, #problems, "left alone")
  self:assert_equal("KEEP", fs.files["outside/keep.md"])
end

-- Windows paths ----------------------------------------------------------------------------------------------------

function T:test_backslashes_are_separators_at_the_entry_points()
  local fs = doc.MemoryFileSystem({ ["C:/proj/docs/en/index.md"] = "# Home\n" })
  local report = generate(options(fs, { project_dir = "C:\\proj", guides_dir = "docs\\", output_dir = "C:\\proj\\docs\\dist",
    application = application }))
  self:assert_equal(0, #report.problems, table.concat(report.problems, "\n"))
  self:assert_not_nil(fs:read("C:/proj/docs/dist/en/index.html"))
  self:assert_not_nil(fs:read("C:/proj/docs/en/configuration.md"))
  local built = doc.MemoryFileSystem({ ["C:/c/en/index.md"] = "# Home\n" })
  doc.build({ site_configuration = { title = "T" }, guides_dir = "C:\\c", output_dir = "C:\\o\\", file_system = built })
  self:assert_not_nil(built:read("C:/o/en/index.html"))
  local err = self:assert_error(function()
    doc.build({ site_configuration = { title = "T" }, guides_dir = "C:\\c", output_dir = "C:\\c\\", file_system = built })
  end)
  self:assert_equal("output_dir", err.context.argument)
end

function T:test_a_drive_relative_path_is_refused_where_the_rule_applies()
  local field, expected = options_module.invalid({ guides_dir = "C:docs" }, { "guides_dir" })
  self:assert_equal(require("hecate.doc.internal.paths").is_windows() and "guides_dir" or nil, field)
  if field then self:assert_not_nil(expected:find("drive", 1, true)) end
  -- On any platform an absolute form is accepted.
  self:assert_nil(options_module.invalid({ guides_dir = "C:/docs", output_dir = "C:\\o", project_dir = "/p", sources_dir = "\\s" },
    { "guides_dir", "output_dir", "project_dir" }))
end

function T:test_the_sources_directory_must_be_relative_in_every_form()
  for _, value in ipairs({ "/abs", "\\abs", "C:/abs", "C:\\abs", "\\\\server\\share" }) do
    local fs = doc.MemoryFileSystem(files({}))
    local message = refused(self, fs, { guides_dir = "docs", output_dir = "dist", sources_dir = value }, "sources_dir")
    self:assert_not_nil(message:find("plugin", 1, true), "the message says why: " .. message)
  end
  local fs = doc.MemoryFileSystem(files({}))
  generate(options(fs, { guides_dir = "docs", output_dir = "dist", sources_dir = "v:1" })) -- a plain name off Windows
end

-- Strict mode ------------------------------------------------------------------------------------------------------

function T:test_fail_on_problems_raises_for_the_problems_of_the_code_reference()
  local fs = doc.MemoryFileSystem(files({}))
  local err = self:assert_error(function()
    generate(options(fs, { guides_dir = "docs", output_dir = "dist", package_name = "shop", language_server_path = "/nonexistent",
      fail_on_problems = true }))
  end)
  self:assert_true(core.is_instance_of(err, doc.BuildError), tostring(err))
  self:assert_not_nil(tostring(err):find("shop", 1, true), tostring(err))
  local lenient = generate(options(doc.MemoryFileSystem(files({})), { guides_dir = "docs", output_dir = "dist", package_name = "shop",
    language_server_path = "/nonexistent" }))
  self:assert_true(#lenient.problems >= 1, "without the switch the same problems are in the report")
end

function T:test_fail_on_problems_raises_one_error_listing_every_problem_sorted_and_unique()
  local fs = doc.MemoryFileSystem(files({ ["docs/en/a.md"] = "[broken](missing.md)\n" }))
  local err = self:assert_error(function()
    generate(options(fs, { guides_dir = "docs", output_dir = "dist", package_name = "shop", language_server_path = "/nonexistent",
      licences_page = { rocks_tree_dir = "nowhere" }, fail_on_problems = true }))
  end)
  local text = tostring(err)
  for _, part in ipairs({ "broken link", "shop", "nowhere" }) do self:assert_not_nil(text:find(part, 1, true), part .. ": " .. text) end
  local problems = err.context.problems
  local sorted = {}
  for index, problem in ipairs(problems) do sorted[index] = problem end
  table.sort(sorted)
  self:assert_equal(table.concat(sorted, "\n"), table.concat(problems, "\n"), "sorted")
  local seen = {}
  for _, problem in ipairs(problems) do
    self:assert_nil(seen[problem], "unique: " .. problem)
    seen[problem] = true
  end
  local report = generate(options(doc.MemoryFileSystem(files({ ["docs/en/a.md"] = "[broken](missing.md)\n" })), {
    guides_dir = "docs", output_dir = "dist", package_name = "shop", language_server_path = "/nonexistent",
    licences_page = { rocks_tree_dir = "nowhere" } }))
  sorted = {}
  for index, problem in ipairs(report.problems) do sorted[index] = problem end
  table.sort(sorted)
  self:assert_equal(table.concat(sorted, "\n"), table.concat(report.problems, "\n"), "the report holds them sorted too")
end

-- Closed lists -----------------------------------------------------------------------------------------------------

function T:test_an_unknown_option_is_refused_naming_it_and_its_replacement()
  local cases = {
    { out = "x" }, { source = "x" }, { strict = true }, { locale = "en" }, { licenses = true }, { fs = 1 },
    { document = {} }, { configuration = {} }, { secrets = {} }, { pages = {} }, { code = {} }, { fail_on_problem = true },
  }
  for _, case in ipairs(cases) do
    local fs = doc.MemoryFileSystem(files({}))
    local key = next(case)
    local message = refused(self, fs, case, key)
    self:assert_not_nil(message:find("`" .. key .. "`", 1, true), message)
  end
  local message = refused(self, doc.MemoryFileSystem(files({})), { out = "x" }, "out")
  self:assert_not_nil(message:find("option `out` was renamed `output_dir`", 1, true), message)
  message = refused(self, doc.MemoryFileSystem(files({})), { configuration = {} }, "configuration")
  self:assert_not_nil(message:find("single source", 1, true), message)
  message = refused(self, doc.MemoryFileSystem(files({})), { fail_on_problem = true }, "fail_on_problem")
  self:assert_not_nil(message:find("did you mean `fail_on_problems`", 1, true), message)
end

function T:test_the_table_of_licences_page_is_a_closed_list_too()
  local message = refused(self, doc.MemoryFileSystem(files({})), { licences_page = { tree = "x" } }, "tree")
  self:assert_not_nil(message:find("renamed `rocks_tree_dir`", 1, true), message)
  refused(self, doc.MemoryFileSystem(files({})), { licences_page = { whatever = 1 } }, "whatever")
  local licences = require("hecate.doc.licences")
  local err = self:assert_error(function() licences.read(doc.MemoryFileSystem({}), { rocks_tree_dir = "t", tree = "x" }) end)
  self:assert_equal("tree", err.context.argument)
  err = self:assert_error(function() licences.bundled({ diagrams = false, theme_fs = {} }) end)
  self:assert_equal("theme_fs", err.context.argument)
end

function T:test_the_other_entry_points_refuse_unknown_options_too()
  local fs = doc.MemoryFileSystem({ ["c/en/index.md"] = "# H\n" })
  local err = self:assert_error(function() doc.Site({ site_configuration = { title = "T" }, guides_dir = "c", file_system = fs, output_dir = "o" }) end)
  self:assert_equal("output_dir", err.context.argument)
  local reference_site = require("hecate.doc.reference_site")
  err = self:assert_error(function() reference_site.run({ project_dir = ".", locale_dir = "en", file_system = fs, exe = "x" }) end)
  self:assert_equal("exe", err.context.argument)
  err = self:assert_error(function() require("hecate.doc.luals").export("x", "y", { file_system = fs, config = "z" }) end)
  self:assert_equal("config", err.context.argument)
  err = self:assert_error(function() require("hecate.doc.reference").generate({}, { rot = 1 }) end)
  self:assert_equal("rot", err.context.argument)
end

function T:test_a_site_configuration_with_an_old_or_unknown_key_is_refused_before_anything_is_written()
  for _, key in ipairs({ "colors", "theme", "logo", "logos", "audience" }) do
    local fs = doc.MemoryFileSystem(files({}))
    local before = snapshot(fs)
    local err = self:assert_error(function()
      generate(options(fs, { guides_dir = "docs", output_dir = "dist", application = application,
        site_configuration = { title = "Shop", [key] = "x" } }))
    end)
    self:assert_true(core.is_instance_of(err, core.ConfigurationError), key .. ": " .. tostring(err))
    self:assert_equal(key, err.context.field)
    self:assert_equal(before, snapshot(fs))
  end
end

function T:test_the_error_context_names_the_argument_like_the_other_packages()
  local fs = doc.MemoryFileSystem(files({}))
  local err = self:assert_error(function() generate(options(fs, { guides_dir = 3 })) end)
  self:assert_equal("guides_dir", err.context.argument)
  err = self:assert_error(function() doc.build({ site_configuration = { title = "T" }, guides_dir = "c", output_dir = "o",
    ---@diagnostic disable-next-line: missing-fields  -- the incomplete file system is the point of the test
    file_system = {} }) end)
  self:assert_equal("file_system", err.context.argument)
end

function T:test_the_values_of_the_options_are_validated()
  local cases = {
    { file_system = { read = function() end } }, { file_system = "disk" },
    { theme_file_system = {} }, { theme_file_system = "x" }, { last_updated = "2026-01-01" },
    { language_server_path = "" }, { theme_files_dir = "" }, { language_server_config_path = "" },
    { package_name = "../x" }, { package_name = ".hidden" }, { package_name = "a/b" }, { package_name = "a\\b" },
    { package_name = "a..b" }, { package_name = "" },
    { content_locale = "fr" }, { content_locale = "e n" },
  }
  for _, case in ipairs(cases) do
    local fs = doc.MemoryFileSystem(files({}))
    local extra = { guides_dir = "docs", output_dir = "dist" }
    ---@cast extra table<string, any>
    for key, value in pairs(case) do extra[key] = value end
    local key = next(case)
    local before = snapshot(fs)
    local err = self:assert_error(function() generate(options(fs, extra)) end)
    self:assert_true(core.is_instance_of(err, core.ArgumentError), key .. ": " .. tostring(err))
    self:assert_equal(key, err.context.argument, tostring(err))
    self:assert_equal(before, snapshot(fs))
  end
end

function T:test_content_locale_must_be_a_locale_of_the_site()
  local fs = doc.MemoryFileSystem(files({}))
  local message = refused(self, fs, { guides_dir = "docs", output_dir = "dist", content_locale = "fr" }, "content_locale")
  self:assert_not_nil(message:find("en", 1, true), message)
  local with_fr = doc.MemoryFileSystem(files({ ["docs/fr/index.md"] = "# Accueil\n" }))
  generate(options(with_fr, { guides_dir = "docs", output_dir = "dist", content_locale = "fr", application = application,
    site_configuration = { title = "S", locales = { { code = "en" }, { code = "fr" } } } }))
  self:assert_not_nil(with_fr:read("docs/fr/configuration.md"))
end

function T:test_a_site_configuration_and_its_path_together_are_an_error()
  local fs = doc.MemoryFileSystem(files({ ["docs/site.lua"] = 'return { title = "Other" }' }))
  local message = refused(self, fs, { guides_dir = "docs", output_dir = "dist", site_configuration_path = "docs/site.lua" },
    "site_configuration_path")
  self:assert_not_nil(message:find("site_configuration", 1, true), message)
end

function T:test_the_path_of_the_site_configuration_is_relative_to_the_project_not_the_guides()
  local fs = doc.MemoryFileSystem({ ["acme/config/site.lua"] = 'return { title = "Acme" }', ["acme/docs/en/index.md"] = "# H\n" })
  generate({ file_system = fs, project_dir = "acme", site_configuration_path = "config/site.lua" })
  self:assert_not_nil(fs:read("acme/docs/dist/en/index.html"))
  local by_default = doc.MemoryFileSystem({ ["acme/docs/site.lua"] = 'return { title = "Acme" }', ["acme/docs/en/index.md"] = "# H\n" })
  generate({ file_system = by_default, project_dir = "acme" })
  self:assert_not_nil(by_default:read("acme/docs/dist/en/index.html"), "the default is below the guides")
end

function T:test_a_missing_site_configuration_says_the_cause_and_the_remedy()
  local fs = doc.MemoryFileSystem({ ["docs/en/index.md"] = "# H\n" })
  local err = self:assert_error(function() generate({ file_system = fs }) end)
  self:assert_true(core.is_instance_of(err, doc.BuildError), tostring(err))
  local text = tostring(err)
  for _, part in ipairs({ "docs/site.lua", "does not exist", "site_configuration_path", "site_configuration = {" }) do
    self:assert_not_nil(text:find(part, 1, true), part .. ": " .. text)
  end
  local explicit = self:assert_error(function() generate({ file_system = fs, site_configuration_path = "conf/site.lua" }) end)
  self:assert_not_nil(tostring(explicit):find("conf/site.lua", 1, true), tostring(explicit))
end

-- Diagrams ---------------------------------------------------------------------------------------------------------

local FENCE = "# D\n\n```mermaid\ngraph TD\n  A-->B\n```\n"

local function licences_text(fs, extra)
  local result = options(fs, { guides_dir = "docs", output_dir = "docs/dist", licences_page = { rocks_tree_dir = "nowhere" } })
  for key, value in pairs(extra or {}) do result[key] = value end
  local report = generate(result)
  return fs:read("docs/en/third-party-licences.md"), report
end

function T:test_the_scan_for_diagrams_skips_the_output_directory_and_links()
  local fs = doc.MemoryFileSystem(files({ ["docs/dist/en/old.md"] = FENCE, ["outside/d.md"] = FENCE }))
  fs:link("docs/en/linked.md", "outside/d.md")
  fs:link("docs/en/loop", "docs")
  local text = licences_text(fs)
  self:assert_nil(text:find("Mermaid", 1, true), "neither the output nor a link counts")
  local with = doc.MemoryFileSystem(files({ ["docs/en/d.md"] = FENCE }))
  self:assert_not_nil(licences_text(with):find("Mermaid", 1, true))
end

function T:test_the_scan_for_diagrams_reports_where_it_stops()
  local saved_files = project_documentation.LIMITS.scanned_files
  project_documentation.LIMITS.scanned_files = 3
  local pages = {}
  for index = 1, 10 do pages["docs/en/p" .. index .. ".md"] = "# P\n" end
  local _, report = licences_text(doc.MemoryFileSystem(files(pages)))
  project_documentation.LIMITS.scanned_files = saved_files
  local found = false
  for _, problem in ipairs(report.problems) do found = found or (problem:find("diagram", 1, true) ~= nil and problem:find("3 Markdown files", 1, true) ~= nil) end
  self:assert_true(found, table.concat(report.problems, "\n"))
  local deep = {}
  for _ = 1, 40 do deep[#deep + 1] = "d" end
  local _, deep_report = licences_text(doc.MemoryFileSystem(files({ ["docs/en/" .. table.concat(deep, "/") .. "/x.md"] = "# X\n" })))
  found = false
  for _, problem in ipairs(deep_report.problems) do found = found or problem:find("deeper than 32", 1, true) ~= nil end
  self:assert_true(found, table.concat(deep_report.problems, "\n"))
end

return T
