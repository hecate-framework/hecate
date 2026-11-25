---@diagnostic disable: need-check-nil  -- tests read files they have just built; a nil fails the assertion that follows
-- The portability of the names of every file of the site (pages, files next to the guides, `public/`, the files the
-- site configuration names): Windows rules, Normalization Form C, case-fold collisions over the combined namespace,
-- length limits, and the case of `.md` and of `exclude_file_names`.
local test = require("harness.test")
local doc = require("hecate.doc")
local core = require("hecate.core")
local T = test.Case("SitePortabilityTest")

local function page(title, body)
  return ("---\ntitle: %s\n---\n%s\n"):format(title, body or "text")
end

local ONE_LOCALE = { title = "T", locales = { { code = "en", label = "English" } } }

local function build(files, configuration, options)
  local prefixed = {}
  for path, data in pairs(files) do prefixed["c/" .. path] = data end
  prefixed["c/en/index.md"] = prefixed["c/en/index.md"] or page("Home", "welcome")
  local fs = doc.MemoryFileSystem(prefixed)
  local arguments = { site_configuration = configuration or ONE_LOCALE, guides_dir = "c", output_dir = "o", file_system = fs }
  for key, value in pairs(options or {}) do arguments[key] = value end
  return fs, doc.build(arguments)
end

local function mentions(problems, text)
  for _, problem in ipairs(problems) do
    if problem:find(text, 1, true) then return true end
  end
  return false
end

--- Asserts that the build of `files` fails with a `BuildError` whose text holds every fragment; returns the error.
local function refused(self, files, fragments, configuration)
  local err = self:assert_error(function() build(files, configuration) end)
  self:assert_true(core.is_instance_of(err, doc.BuildError), tostring(err))
  for _, fragment in ipairs(fragments) do
    self:assert_not_nil(tostring(err):find(fragment, 1, true), fragment .. " in " .. tostring(err))
  end
  return err
end

-- Windows rules ------------------------------------------------------------------------------------------------------

function T:test_a_file_next_to_the_guides_with_a_windows_problem_is_refused()
  for _, name in ipairs({ "aux.png", "img/con.svg", "con/x.svg", "x.", "a:b.png", "img/NUL.txt", "dir /x.png" }) do
    refused(self, { ["en/" .. name] = "x" }, { "not portable", "en/" .. name })
  end
end

function T:test_a_file_of_public_with_a_windows_problem_is_refused_and_nothing_is_written()
  for _, name in ipairs({ "aux.png", "fonts/con.woff2", "robots." }) do
    local fs = doc.MemoryFileSystem({ ["c/en/index.md"] = page("Home"), ["c/public/" .. name] = "x" })
    local err = self:assert_error(function()
      doc.build({ site_configuration = ONE_LOCALE, guides_dir = "c", output_dir = "o", file_system = fs })
    end)
    self:assert_true(core.is_instance_of(err, doc.BuildError), tostring(err))
    self:assert_not_nil(tostring(err):find("public/" .. name, 1, true), tostring(err))
    self:assert_nil(fs:read("o/.hecate-doc-output"), "a refused build leaves no output")
  end
end

function T:test_a_name_the_site_configuration_gives_is_checked_too()
  refused(self, { ["public/aux.svg"] = "<svg/>" }, { "aux.svg" }, { title = "T", logo_path = "aux.svg" })
  refused(self, { ["public/y.css"] = "x" }, { "x.css", "not in public/" }, { title = "T", stylesheet_path = "x.css" })
end

function T:test_a_configured_name_must_be_spelt_as_the_file_is()
  refused(self, { ["public/logo.svg"] = "<svg/>" }, { "Logo.svg", "differs only by case", "public/logo.svg" },
    { title = "T", logo_path = "Logo.svg" })
  local fs = build({ ["public/logo.svg"] = "<svg/>" }, { title = "T", logo_path = "logo.svg" })
  self:assert_equal("<svg/>", fs:read("o/logo.svg"))
end

function T:test_a_configured_name_must_be_in_nfc()
  refused(self, { ["public/\u{E9}.css"] = "x" }, { "NFC" }, { title = "T", stylesheet_path = "e\u{301}.css" })
end

-- Normalisation ------------------------------------------------------------------------------------------------------

function T:test_a_public_file_is_written_under_its_nfc_name()
  local fs = build({ ["public/img/e\u{301}.svg"] = "<svg/>" })
  self:assert_equal("<svg/>", fs:read("o/img/\u{E9}.svg"))
  self:assert_nil(fs:read("o/img/e\u{301}.svg"))
end

-- Case collisions ----------------------------------------------------------------------------------------------------

function T:test_files_next_to_the_guides_that_differ_only_by_case_are_refused()
  refused(self, { ["en/Img/a.svg"] = "1", ["en/img/a.svg"] = "2" }, { "differ only by case", "en/Img/a.svg", "en/img/a.svg" })
  refused(self, { ["en/Logo.svg"] = "1", ["en/logo.svg"] = "2" }, { "differ only by case" })
end

function T:test_directories_that_differ_only_by_case_are_not_a_collision()
  local fs = build({ ["en/Img/a.svg"] = "1", ["en/img/b.svg"] = "2" })
  self:assert_equal("1", fs:read("o/en/Img/a.svg"))
  self:assert_equal("2", fs:read("o/en/img/b.svg"))
end

function T:test_the_case_fold_covers_greek_and_cyrillic_pages()
  refused(self, { ["en/\u{416}.md"] = page("A"), ["en/\u{436}.md"] = page("B") }, { "differ only by case" })
  refused(self, { ["en/\u{386}.md"] = page("A"), ["en/\u{3AC}.md"] = page("B") }, { "differ only by case" })
  refused(self, { ["en/img/\u{416}.svg"] = "1", ["en/img/\u{436}.svg"] = "2" }, { "differ only by case" })
end

function T:test_a_page_and_a_file_share_one_namespace()
  -- the page `a` is `en/a/index.html`: a file `a` (any case) cannot be written next to it
  refused(self, { ["en/a.md"] = page("A"), ["en/A"] = "file" }, { "file where the other needs a directory" })
  -- the file that is the output file of a page
  refused(self, { ["en/a.md"] = page("A"), ["en/a/index.html"] = "x" }, { "same output file" })
end

function T:test_a_file_that_differs_by_case_from_a_page_output_is_refused()
  refused(self, { ["en/a.md"] = page("A"), ["en/A/index.html"] = "x" }, { "differ only by case" })
end

function T:test_the_fallback_files_of_the_default_locale_join_the_namespace_of_each_locale()
  local files = { ["en/img/a.svg"] = "1", ["fr/index.md"] = page("Accueil"), ["fr/Img/a.svg"] = "2" }
  refused(self, files, { "differ only by case", "fr/Img/a.svg" },
    { title = "T", locales = { { code = "en", label = "English" }, { code = "fr", label = "Fran\u{E7}ais" } } })
end

function T:test_files_of_public_that_differ_only_by_case_are_refused()
  refused(self, { ["public/Logo.svg"] = "1", ["public/logo.svg"] = "2" }, { "differ only by case", "public/Logo.svg" })
  refused(self, { ["public/\u{416}.txt"] = "1", ["public/\u{436}.txt"] = "2" }, { "differ only by case" })
end

function T:test_a_file_of_public_and_a_file_of_a_locale_share_one_namespace()
  refused(self, { ["en/img/a.svg"] = "1", ["public/en/Img/a.svg"] = "2" }, { "differ only by case" })
  refused(self, { ["public/en"] = "a file" }, { "file where the other needs a directory" })
end

function T:test_a_file_of_public_that_differs_by_case_from_a_generated_file_is_refused_before_anything_is_written()
  for _, name in ipairs({ "404.HTML", "Index.html", "Assets/theme.css", "assets/Search-en.js" }) do
    local fs = doc.MemoryFileSystem({ ["c/en/index.md"] = page("Home"), ["c/public/" .. name] = "mine" })
    local err = self:assert_error(function()
      doc.build({ site_configuration = ONE_LOCALE, guides_dir = "c", output_dir = "o", file_system = fs })
    end)
    self:assert_true(core.is_instance_of(err, doc.BuildError), name .. ": " .. tostring(err))
    self:assert_not_nil(tostring(err):find("public/" .. name, 1, true), tostring(err))
    self:assert_nil(fs:read("o/.hecate-doc-output"), "no partial output for " .. name)
  end
end

-- Length -------------------------------------------------------------------------------------------------------------

function T:test_a_segment_over_255_bytes_is_a_problem_and_an_error_under_fail_on_problems()
  local long = ("a"):rep(256) .. ".svg"
  local files = { ["en/img/" .. long] = "x", ["public/" .. ("b"):rep(300) .. ".txt"] = "y" }
  local _, report = build(files)
  self:assert_true(mentions(report.problems, "en/img/" .. ("a"):rep(256)), table.concat(report.problems, "\n"))
  self:assert_true(mentions(report.problems, "260 bytes") or mentions(report.problems, "more than the limit of 255 bytes"),
    table.concat(report.problems, "\n"))
  self:assert_true(mentions(report.problems, "public/"), table.concat(report.problems, "\n"))
  local err = self:assert_error(function() build(files, nil, { fail_on_problems = true }) end)
  self:assert_true(core.is_instance_of(err, doc.BuildError), tostring(err))
end

function T:test_a_page_id_segment_over_255_bytes_is_a_problem()
  local _, report = build({ ["en/" .. ("p"):rep(256) .. ".md"] = page("P") })
  self:assert_true(mentions(report.problems, "more than the limit of 255 bytes"), table.concat(report.problems, "\n"))
end

function T:test_a_segment_of_255_bytes_is_accepted()
  local _, report = build({ ["en/" .. ("a"):rep(251) .. ".svg"] = "x" })
  self:assert_false(mentions(report.problems, "255 bytes"), table.concat(report.problems, "\n"))
end

function T:test_an_output_path_of_260_characters_or_more_is_a_problem_reported_with_the_file()
  local deep = ("d"):rep(60)
  local id = table.concat({ deep, deep, deep, deep, "page" }, "/")
  local _, report = build({ ["en/" .. id .. ".md"] = page("Deep") })
  self:assert_true(mentions(report.problems, "o/en/" .. id .. "/index.html"), table.concat(report.problems, "\n"))
  self:assert_true(mentions(report.problems, "260") == false and mentions(report.problems, "259"), table.concat(report.problems, "\n"))
  local err = self:assert_error(function() build({ ["en/" .. id .. ".md"] = page("Deep") }, nil, { fail_on_problems = true }) end)
  self:assert_true(core.is_instance_of(err, doc.BuildError), tostring(err))
  local short = ("d"):rep(20)
  local _, ok = build({ ["en/" .. short .. "/" .. short .. ".md"] = page("Short") })
  self:assert_false(mentions(ok.problems, "Windows"), table.concat(ok.problems, "\n"))
end

function T:test_the_output_directory_counts_in_the_path_length()
  local id = ("d"):rep(60) .. "/" .. ("e"):rep(60) .. "/page"
  local path = "o/en/" .. id .. "/index.html"
  self:assert_true(#path < 259)
  local _, fine = build({ ["en/" .. id .. ".md"] = page("P") })
  self:assert_false(mentions(fine.problems, "Windows"), table.concat(fine.problems, "\n"))
  local fs = doc.MemoryFileSystem({ ["c/en/index.md"] = page("Home"), ["c/en/" .. id .. ".md"] = page("P") })
  local report = doc.build({ site_configuration = ONE_LOCALE, guides_dir = "c", output_dir = ("x"):rep(150), file_system = fs })
  self:assert_true(mentions(report.problems, "Windows"), table.concat(report.problems, "\n"))
end

-- Case of `.md` and of `exclude_file_names` -------------------------------------------------------------------------

function T:test_the_md_suffix_is_matched_without_regard_to_case()
  local fs = build({ ["en/Guide.MD"] = page("Guide", "text"), ["en/Other.Md"] = page("Other", "[g](Guide.MD)") })
  self:assert_not_nil(fs:read("o/en/Guide/index.html"))
  self:assert_not_nil(fs:read("o/en/Other/index.html"))
  self:assert_nil(fs:read("o/en/Guide.MD"), "an upper-case suffix is a page, not a file next to the pages")
  self:assert_not_nil(fs:read("o/en/Other/index.html"):find('href="../Guide/index.html"', 1, true))
end

function T:test_exclude_file_names_is_matched_without_regard_to_case()
  local fs = build({ ["en/Readme.md"] = page("R"), ["en/README.MD"] = page("R2"), ["en/guide/readme.md"] = page("R3"),
    ["en/guide/index.md"] = page("Guide") })
  for _, path in ipairs({ "o/en/Readme/index.html", "o/en/README/index.html", "o/en/guide/readme/index.html" }) do
    self:assert_nil(fs:read(path), path)
  end
  self:assert_not_nil(fs:read("o/en/guide/index.html"))
  local custom = build({ ["en/Notes.TXT"] = "x", ["en/a.md"] = page("A") }, { title = "T", exclude_file_names = { "notes.txt" } })
  self:assert_nil(custom:read("o/en/Notes.TXT"))
  local kept = build({ ["en/Notes.TXT"] = "x", ["en/a.md"] = page("A") })
  self:assert_equal("x", kept:read("o/en/Notes.TXT"))
end

function T:test_an_excluded_name_that_differs_only_in_normalisation_is_excluded()
  local fs = build({ ["en/caf\u{E9}.txt"] = "x", ["en/a.md"] = page("A") }, { title = "T", exclude_file_names = { "cafe\u{301}.txt" } })
  self:assert_nil(fs:read("o/en/caf\u{E9}.txt"))
end

return T
