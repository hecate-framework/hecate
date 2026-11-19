---@diagnostic disable: need-check-nil  -- tests read files they have just built; a nil fails the assertion that follows
-- The content tree is data of the project: links, depth, hidden directories, reserved ids, empty sites.
local test = require("harness.test")
local doc = require("hecate.doc")
local core = require("hecate.core")
local Site = require("hecate.doc.site")
local T = test.Case("SiteHardeningTest")

local function page(title, body, extra)
  return ("---\ntitle: %s\n%s---\n%s\n"):format(title, extra or "", body or "text")
end

local function files_of(extra)
  local files = { ["c/en/index.md"] = page("Home", "welcome") }
  for path, data in pairs(extra or {}) do files["c/" .. path] = data end
  return files
end

local function build(fs, configuration, options)
  local arguments = { site_configuration = configuration or { title = "T" }, guides_dir = "c", output_dir = "o", file_system = fs }
  for key, value in pairs(options or {}) do arguments[key] = value end
  return doc.build(arguments)
end

local function mentions(problems, text)
  for _, problem in ipairs(problems) do
    if problem:find(text, 1, true) then return true end
  end
  return false
end

local function anywhere(fs, text)
  for path, data in pairs(fs.files) do
    if path:sub(1, 2) == "o/" and data:find(text, 1, true) then return path end
  end
  return nil
end

-- Symbolic links ---------------------------------------------------------------------------------------------------

function T:test_a_link_to_a_file_in_a_guide_directory_is_skipped_with_a_problem()
  local fs = doc.MemoryFileSystem(files_of({ ["../secret/key"] = "SSH-KEY-CANARY" }))
  fs:link("c/en/key.txt", "secret/key")
  fs:link("c/en/stolen.md", "secret/key")
  local report = build(fs)
  self:assert_nil(anywhere(fs, "SSH-KEY-CANARY"), "the target of a link is never published")
  self:assert_nil(fs:read("o/en/key.txt"))
  self:assert_true(mentions(report.problems, "en/key.txt"), table.concat(report.problems, "\n"))
  self:assert_true(mentions(report.problems, "symbolic link"), table.concat(report.problems, "\n"))
  self:assert_true(mentions(report.problems, "en/stolen.md"))
end

function T:test_a_link_to_a_directory_is_skipped_with_a_problem()
  local fs = doc.MemoryFileSystem(files_of({ ["../outside/page.md"] = page("Out", "OUTSIDE-CANARY") }))
  fs:link("c/en/outside", "outside")
  local report = build(fs)
  self:assert_nil(anywhere(fs, "OUTSIDE-CANARY"))
  self:assert_true(mentions(report.problems, "en/outside"), table.concat(report.problems, "\n"))
end

function T:test_a_link_cycle_ends_with_a_problem_and_no_loop()
  local fs = doc.MemoryFileSystem(files_of({ ["en/guide/a.md"] = page("A", "a") }))
  fs:link("c/en/guide/loop", "c/en")
  fs:link("c/en/up", "c")
  local report = build(fs)
  self:assert_equal(2, (function() local n = 0 for _, p in ipairs(report.problems) do if p:find("symbolic link", 1, true) then n = n + 1 end end return n end)(),
    table.concat(report.problems, "\n"))
  self:assert_equal(2, report.locales.en.pages, "index and guide/a only")
end

function T:test_links_are_an_error_under_fail_on_problems()
  local fs = doc.MemoryFileSystem(files_of({ ["../secret/key"] = "x" }))
  fs:link("c/en/key.txt", "secret/key")
  local err = self:assert_error(function() build(fs, nil, { fail_on_problems = true }) end)
  self:assert_true(core.is_instance_of(err, doc.BuildError), tostring(err))
  self:assert_not_nil(tostring(err):find("symbolic link", 1, true), tostring(err))
end

function T:test_links_in_public_are_skipped_with_a_problem()
  local fs = doc.MemoryFileSystem(files_of({ ["public/ok.txt"] = "fine", ["../secret/key"] = "SSH-KEY-CANARY",
    ["../secret/dir/inner"] = "INNER-CANARY" }))
  fs:link("c/public/id_rsa", "secret/key")
  fs:link("c/public/linked", "secret/dir")
  fs:link("c/public/loop", "c/public")
  local report = build(fs)
  self:assert_equal("fine", fs:read("o/ok.txt"))
  self:assert_nil(anywhere(fs, "SSH-KEY-CANARY"))
  self:assert_nil(anywhere(fs, "INNER-CANARY"))
  for _, name in ipairs({ "public/id_rsa", "public/linked", "public/loop" }) do
    self:assert_true(mentions(report.problems, name), name .. ": " .. table.concat(report.problems, "\n"))
  end
end

function T:test_a_link_to_a_file_next_to_the_pages_is_not_copied_as_an_asset()
  local fs = doc.MemoryFileSystem(files_of({ ["../secret/key"] = "SSH-KEY-CANARY" }))
  fs:link("c/en/picture.png", "secret/key")
  build(fs)
  self:assert_nil(fs:read("o/en/picture.png"))
  self:assert_nil(anywhere(fs, "SSH-KEY-CANARY"))
end

-- Depth and size ---------------------------------------------------------------------------------------------------

function T:test_a_tree_deeper_than_the_limit_is_cut_with_a_problem()
  self:assert_equal(32, Site.LIMITS.depth)
  local deep = {}
  for _ = 1, 33 do deep[#deep + 1] = "d" end
  local fs = doc.MemoryFileSystem(files_of({ ["en/" .. table.concat(deep, "/") .. "/page.md"] = page("Deep", "deep") }))
  local report = build(fs)
  self:assert_true(mentions(report.problems, "deeper than 32"), table.concat(report.problems, "\n"))
  self:assert_equal(1, report.locales.en.pages)
  local public = doc.MemoryFileSystem(files_of({ ["public/" .. table.concat(deep, "/") .. "/file.txt"] = "x" }))
  self:assert_true(mentions(build(public).problems, "deeper than 32"))
end

function T:test_a_tree_with_more_entries_than_the_limit_is_cut_with_a_problem()
  local saved = Site.LIMITS.entries
  Site.LIMITS.entries = 5
  local extra = {}
  for index = 1, 12 do extra["en/p" .. index .. ".md"] = page("P" .. index, "p") end
  local fs = doc.MemoryFileSystem(files_of(extra))
  local ok, report = pcall(build, fs)
  local public = {}
  for index = 1, 12 do public["public/f" .. index .. ".txt"] = "x" end
  local fs_public = doc.MemoryFileSystem(files_of(public))
  local ok_public, report_public = pcall(build, fs_public)
  Site.LIMITS.entries = saved
  self:assert_true(ok, tostring(report))
  self:assert_true(mentions(report.problems, "more than 5 entries"), table.concat(report.problems, "\n"))
  self:assert_true(report.locales.en.pages < 13)
  self:assert_true(ok_public, tostring(report_public))
  self:assert_true(mentions(report_public.problems, "more than 5 entries"), table.concat(report_public.problems, "\n"))
end

function T:test_the_default_limits_are_documented_numbers()
  self:assert_equal(32, Site.LIMITS.depth)
  self:assert_equal("number", type(Site.LIMITS.entries))
  self:assert_true(Site.LIMITS.entries >= 10000)
end

-- Hidden directories -----------------------------------------------------------------------------------------------

function T:test_hidden_files_and_directories_of_public_are_not_copied()
  local fs = doc.MemoryFileSystem(files_of({ ["public/.git/config"] = "GIT-CANARY", ["public/.env"] = "ENV-CANARY",
    ["public/assets2/.hidden/x.txt"] = "HIDDEN-CANARY", ["public/visible.txt"] = "ok" }))
  build(fs)
  self:assert_equal("ok", fs:read("o/visible.txt"))
  for _, canary in ipairs({ "GIT-CANARY", "ENV-CANARY", "HIDDEN-CANARY" }) do self:assert_nil(anywhere(fs, canary), canary) end
end

-- Links written in a page ------------------------------------------------------------------------------------------

function T:test_a_backslash_in_an_absolute_path_link_is_percent_encoded_and_reported()
  local fs = doc.MemoryFileSystem(files_of({ ["en/a.md"] = page("A", "[x](/\\evil.example/path) and [y](/ok/page)") }))
  local report = build(fs, { title = "T", base_path = "/docs/" })
  local html = fs:read("o/en/a/index.html")
  self:assert_nil(html:find("/\\evil", 1, true), "no raw backslash in an absolute-path link")
  self:assert_not_nil(html:find("%5Cevil.example/path", 1, true), html)
  self:assert_true(mentions(report.problems, "backslash"), table.concat(report.problems, "\n"))
  self:assert_not_nil(html:find('href="/docs/ok/page"', 1, true), "an ordinary absolute-path link is kept")
end

function T:test_the_origin_is_percent_encoded_in_llms_txt()
  local fs = doc.MemoryFileSystem(files_of({}))
  build(fs, { title = "T", site_origin = "https://a(b)c<d.test", generate_llms_txt = true })
  local text = fs:read("o/llms.txt")
  self:assert_nil(text:find("(b)", 1, true), text)
  self:assert_nil(text:find("<d", 1, true), text)
  self:assert_not_nil(text:find("https://a%28b%29c%3Cd.test/en/", 1, true), text)
  self:assert_not_nil(fs:read("o/llms-full.txt"):find("Source: https://a%28b%29c%3Cd.test/en/", 1, true))
end

-- Reserved identifiers ---------------------------------------------------------------------------------------------

function T:test_a_heading_id_that_the_theme_uses_is_a_problem()
  local fs = doc.MemoryFileSystem(files_of({ ["en/a.md"] = page("A", "## Content\n\n## Sidebar\n\n## Fine\n\n## Search {#search-dialog}\n\n## Mine {#mine}") }))
  local report = build(fs)
  for _, id in ipairs({ "content", "sidebar", "search-dialog" }) do
    self:assert_true(mentions(report.problems, '"' .. id .. '"'), id .. ": " .. table.concat(report.problems, "\n"))
  end
  self:assert_false(mentions(report.problems, '"fine"'))
  self:assert_false(mentions(report.problems, '"mine"'))
  self:assert_true(mentions(report.problems, "{#"), "the message names the remedy")
end

-- Empty sites and home pages ---------------------------------------------------------------------------------------

function T:test_a_locale_without_a_page_of_the_published_audience_is_a_problem()
  local fs = doc.MemoryFileSystem(files_of({}))
  local report = build(fs, { title = "T", audiences = { "user" }, default_audience = "maintainer" })
  self:assert_true(mentions(report.problems,
    'no page of the published audience "user" in locale en: pages without an audience key are "maintainer" (default_audience); label pages or set default_audience'),
    table.concat(report.problems, "\n"))
  local err = self:assert_error(function()
    build(doc.MemoryFileSystem(files_of({})), { title = "T", audiences = { "user" }, default_audience = "maintainer" }, { fail_on_problems = true })
  end)
  self:assert_true(core.is_instance_of(err, doc.BuildError))
end

function T:test_a_site_without_a_home_page_is_a_problem()
  local fs = doc.MemoryFileSystem({ ["c/en/guide.md"] = page("Guide", "g") })
  local report = build(fs)
  self:assert_true(mentions(report.problems,
    'site "maintainer" (locale en) has no home page: add c/en/index.md with audience: maintainer'), table.concat(report.problems, "\n"))
  local with_home = build(doc.MemoryFileSystem(files_of({})))
  self:assert_equal(0, #with_home.problems)
  -- A separate site per audience has its own home page.
  local separate = build(doc.MemoryFileSystem({ ["c/en/index.md"] = page("Home", "h", "audience: user\n"),
    ["c/en/design.md"] = page("Design", "d", "audience: maintainer\n") }),
    { title = "T", audiences = { "user", "maintainer" } })
  self:assert_true(mentions(separate.problems, 'site "maintainer" (locale en) has no home page'), table.concat(separate.problems, "\n"))
  self:assert_false(mentions(separate.problems, 'site "user"'), table.concat(separate.problems, "\n"))
  self:assert_equal(1, #separate.sites[1].problems + #separate.sites[2].problems, "the problem belongs to the site of the audience")
end

function T:test_the_cross_audience_link_message_tells_the_two_cases_apart()
  local files = { ["c/en/index.md"] = page("Home", "[to users](guide.md)", "audience: maintainer\n"),
    ["c/en/guide.md"] = page("Guide", "g", "audience: user\n") }
  local separate = build(doc.MemoryFileSystem(files), { title = "T", audiences = { "user", "maintainer" } })
  self:assert_true(mentions(separate.problems, 'targets a page of the "user" audience, which is published in another site'
    .. ": use an absolute URL or move the page"), table.concat(separate.problems, "\n"))
  local alone = build(doc.MemoryFileSystem(files), { title = "T", audiences = { "maintainer" } })
  self:assert_true(mentions(alone.problems, 'targets a page of the "user" audience, which is not published'),
    table.concat(alone.problems, "\n"))
  self:assert_false(mentions(alone.problems, "another site"))
end

return T
