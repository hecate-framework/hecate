---@diagnostic disable: need-check-nil  -- tests read files they have just built; a nil fails the assertion that follows
local test = require("harness.test")
local doc = require("hecate.doc")
local core = require("hecate.core")
local T = test.Case("SiteTest")

local CONFIG = {
  title = "hecate",
  locales = { { code = "en", label = "English" }, { code = "fr", label = "Français" } },
}

local function config_with(extra)
  local raw = {}
  for key, value in pairs(CONFIG) do raw[key] = value end
  for key, value in pairs(extra or {}) do raw[key] = value end
  return raw
end

--- Builds `files` (paths relative to the content root `c`) into `o`.
local function build(files, extra, options)
  local prefixed = {}
  for path, data in pairs(files) do prefixed["c/" .. path] = data end
  local fs = doc.MemoryFileSystem(prefixed)
  local arguments = { site_configuration = config_with(extra), guides_dir = "c", output_dir = "o", file_system = fs }
  for key, value in pairs(options or {}) do arguments[key] = value end
  return fs, doc.build(arguments)
end

local function page(title, body, extra)
  return ("---\ntitle: %s\n%s---\n%s\n"):format(title, extra or "", body or "text")
end

local BASIC = {
  ["en/index.md"] = page("Home", "welcome"),
  ["en/guide/index.md"] = page("Guide", "start", "order: 1\n"),
  ["en/guide/a.md"] = page("Alpha", "## First\n\ntext\n\n### Second\n\nmore", "order: 2\nhecate: \"0.x\"\nlua: \"5.5\"\n"),
  ["en/guide/b.md"] = page("Beta", "b", "order: 3\n"),
}

function T:test_pages_are_written_as_directory_urls_with_the_support_files()
  local fs, report = build(BASIC)
  for _, path in ipairs({
    "o/en/index.html", "o/en/guide/index.html", "o/en/guide/a/index.html", "o/index.html", "o/404.html",
    "o/assets/theme.css", "o/assets/theme.js", "o/assets/theme-init.js", "o/assets/search-en.json",
    "o/assets/brand/favicon.svg", "o/assets/fonts/fira-sans-latin-400-normal.woff2", "o/.hecate-doc-output",
  }) do
    self:assert_not_nil(fs:read(path), path)
  end
  self:assert_nil(fs:read("o/sitemap.xml"), "no sitemap without a public url")
  self:assert_equal(4, report.locales.en.pages)
  self:assert_equal(0, #report.problems)
end

function T:test_the_root_redirects_to_the_default_locale()
  local fs = build(BASIC)
  local root = fs:read("o/index.html")
  self:assert_true(root:find('content="0; url=/en/"', 1, true) ~= nil)
  self:assert_true(root:find('<a href="/en/">', 1, true) ~= nil)
end

function T:test_a_page_has_navigation_outline_and_neighbours()
  local fs = build(BASIC)
  local html = fs:read("o/en/guide/a/index.html")
  self:assert_true(html:find('<a href="/en/guide/a/" aria-current="page">Alpha</a>', 1, true) ~= nil)
  self:assert_true(html:find('<a href="/en/guide/b/">Beta</a>', 1, true) ~= nil)
  self:assert_true(html:find('rel="prev" href="/en/guide/"', 1, true) ~= nil)
  self:assert_true(html:find('rel="next" href="/en/guide/b/"', 1, true) ~= nil)
  self:assert_true(html:find('<li class="level-2"><a href="#first">First</a></li>', 1, true) ~= nil)
  self:assert_true(html:find('<li class="level-3"><a href="#second">Second</a></li>', 1, true) ~= nil)
  self:assert_true(html:find("Written for hecate 0.x and Lua 5.5", 1, true) ~= nil)
  self:assert_true(html:find('<a href="/en/guide/" aria-current="true">Guide</a>', 1, true) ~= nil, "section link is current")
  self:assert_true(html:find("<title>Alpha | hecate</title>", 1, true) ~= nil)
end

function T:test_the_home_layout_has_a_hero_and_no_sidebar_or_outline()
  local files = {
    ["en/index.md"] = page("hecate", "## Section\n\nx", "layout: home\ndescription: Tagline\nactions: [\"Go | guide/ | primary\", \"Repo | https://x.test/r\"]\n"),
    ["en/guide/index.md"] = page("Guide"),
  }
  local fs = build(files)
  local html = fs:read("o/en/index.html")
  self:assert_true(html:find('<h1 class="hero-title">hecate</h1>', 1, true) ~= nil)
  self:assert_true(html:find('<p class="hero-tagline">Tagline</p>', 1, true) ~= nil)
  self:assert_true(html:find('<a class="button button-primary" href="/en/guide/">Go</a>', 1, true) ~= nil)
  self:assert_true(html:find('<a class="button" href="https://x.test/r">Repo</a>', 1, true) ~= nil)
  self:assert_nil(html:find('class="sidebar"', 1, true))
  self:assert_nil(html:find('class="outline"', 1, true))
  self:assert_true(html:find("<title>hecate</title>", 1, true) ~= nil)
end

function T:test_home_actions_with_an_unsafe_scheme_are_not_linked()
  local files = {
    ["en/index.md"] = page("hecate", "x", "layout: home\nactions: [\"Bad | javascript:alert(1)\", \"Ok | https://x.test/r\"]\n"),
  }
  local fs = build(files)
  local html = fs:read("o/en/index.html")
  self:assert_nil(html:lower():find("javascript:", 1, true))
  self:assert_true(html:find('href="https://x.test/r"', 1, true) ~= nil)
end

function T:test_a_missing_translation_falls_back_with_a_visible_notice()
  local files = {}
  for path, data in pairs(BASIC) do files[path] = data end
  files["fr/guide/a.md"] = page("Alpha FR", "bonjour", "source_revision: abc1234\n")
  local fs, report = build(files, { site_origin = "https://x.test" })
  self:assert_equal(3, report.locales.fr.fallbacks)
  local translated = fs:read("o/fr/guide/a/index.html")
  self:assert_nil(translated:find('class="notice"', 1, true))
  self:assert_true(translated:find("Alpha FR", 1, true) ~= nil)
  local fallback = fs:read("o/fr/guide/b/index.html")
  self:assert_true(fallback:find('<p class="notice" role="note">', 1, true) ~= nil)
  self:assert_true(fallback:find("pas encore traduite", 1, true) ~= nil)
  self:assert_true(fallback:find('<div lang="en">', 1, true) ~= nil, "the content stays marked as English")
  self:assert_true(fallback:find("<title>Beta | hecate</title>", 1, true) ~= nil)
  self:assert_true(fallback:find('<html lang="fr">', 1, true) ~= nil)
  self:assert_true(fallback:find("Page suivante", 1, true) == nil or fallback:find("Page précédente", 1, true) ~= nil)
end

function T:test_the_locale_switch_links_to_the_same_page()
  local fs = build(BASIC)
  local html = fs:read("o/en/guide/a/index.html")
  self:assert_true(html:find('<a href="/fr/guide/a/" lang="fr" hreflang="fr">Français</a>', 1, true) ~= nil)
  self:assert_true(html:find('<a href="/en/guide/a/" lang="en" hreflang="en" aria-current="true">English</a>', 1, true) ~= nil)
end

function T:test_a_single_locale_site_has_no_locale_switch()
  local fs = build(BASIC, { locales = { { code = "en", label = "English" } } })
  self:assert_nil(fs:read("o/en/index.html"):find("locale-menu", 1, true))
  self:assert_nil(fs:read("o/fr/index.html"))
end

function T:test_alternates_canonical_and_sitemap_need_a_public_url_and_skip_fallbacks()
  local files = {}
  for path, data in pairs(BASIC) do files[path] = data end
  files["fr/guide/a.md"] = page("Alpha FR")
  local fs = build(files, { site_origin = "https://x.test/" })
  local html = fs:read("o/en/guide/a/index.html")
  self:assert_true(html:find('<link rel="canonical" href="https://x.test/en/guide/a/">', 1, true) ~= nil)
  self:assert_true(html:find('<link rel="alternate" hreflang="fr" href="https://x.test/fr/guide/a/">', 1, true) ~= nil)
  local beta = fs:read("o/en/guide/b/index.html")
  self:assert_nil(beta:find('hreflang="fr" href="https://x.test/fr/guide/b/"', 1, true), "a fallback is not a translation")
  local sitemap = fs:read("o/sitemap.xml")
  self:assert_true(sitemap:find("<loc>https://x.test/fr/guide/a/</loc>", 1, true) ~= nil)
  self:assert_nil(sitemap:find("https://x.test/fr/guide/b/", 1, true))
end

function T:test_the_base_path_prefixes_every_url()
  local fs = build(BASIC, { base_path = "/docs/" })
  local html = fs:read("o/en/guide/a/index.html")
  self:assert_true(html:find('href="/docs/assets/theme.css"', 1, true) ~= nil)
  self:assert_true(html:find('src="/docs/assets/theme.js"', 1, true) ~= nil)
  self:assert_true(html:find('<a href="/docs/en/guide/b/">Beta</a>', 1, true) ~= nil)
  self:assert_true(html:find('"index":"/docs/assets/search-en.json"', 1, true) ~= nil)
  self:assert_true(html:find('href="/docs/en/"', 1, true) ~= nil)
  self:assert_nil(html:find('href="/en/', 1, true))
  self:assert_true(fs:read("o/index.html"):find('url=/docs/en/', 1, true) ~= nil)
  self:assert_true(fs:read("o/assets/search-en.json"):find('"u":"/docs/en/guide/a/#first"', 1, true) ~= nil)
end

function T:test_markdown_links_are_resolved_against_the_page_and_the_locale()
  local files = {
    ["en/guide/index.md"] = page("Guide", "[a](a.md) [b](./b.md#frag) [up](../index.md) [dir](../guide/) [abs](/en/x) [web](https://e.test/p) [anchor](#top)"),
    ["en/guide/a.md"] = page("A"),
    ["en/guide/b.md"] = page("B"),
    ["en/index.md"] = page("Home"),
    ["fr/guide/index.md"] = page("Guide FR", "[a](a.md)"),
  }
  local fs, report = build(files)
  self:assert_equal(0, #report.problems)
  local html = fs:read("o/en/guide/index.html")
  for _, expected in ipairs({ 'href="/en/guide/a/"', 'href="/en/guide/b/#frag"', 'href="/en/"', 'href="/en/guide/"', 'href="/en/x"',
    'href="https://e.test/p"', 'href="#top"' }) do
    self:assert_true(html:find(expected, 1, true) ~= nil, expected)
  end
  self:assert_true(fs:read("o/fr/guide/index.html"):find('href="/fr/guide/a/"', 1, true) ~= nil, "links stay in the locale")
end

function T:test_broken_links_missing_files_and_escaping_links_are_reported()
  local files = {
    ["en/index.md"] = page("Home", "[a](nope.md) ![i](missing.png) [out](../x.md) [ok](index.md)"),
  }
  local _, report = build(files, { locales = { { code = "en", label = "English" } } })
  self:assert_equal(3, #report.problems)
  self:assert_true(report.problems[1]:find("broken link nope.md", 1, true) ~= nil)
  self:assert_true(report.problems[2]:find("leaves the locale directory", 1, true) ~= nil)
  self:assert_true(report.problems[3]:find("missing file missing.png", 1, true) ~= nil)
end

function T:test_strict_mode_raises_a_build_error_listing_the_problems()
  local err = self:assert_error(function()
    build({ ["en/index.md"] = page("Home", "[a](nope.md)") }, { locales = { { code = "en", label = "English" } } }, { fail_on_problems = true })
  end)
  self:assert_true(core.is_instance_of(err, doc.BuildError))
  self:assert_true(err.message:find("nope.md", 1, true) ~= nil)
  self:assert_equal(1, #err.context.problems)
end

function T:test_files_next_to_pages_are_copied_with_fallback_to_the_default_locale()
  local files = {
    ["en/index.md"] = page("Home", "![d](img/d.svg)"),
    ["en/img/d.svg"] = "<svg/>",
    ["fr/index.md"] = page("Accueil", "![d](img/d.svg)"),
    ["en/.hidden"] = "no",
    ["en/README.md"] = "# not a page",
    ["public/robots.txt"] = "ok",
  }
  local fs, report = build(files)
  self:assert_equal(0, #report.problems)
  self:assert_equal("<svg/>", fs:read("o/en/img/d.svg"))
  self:assert_equal("<svg/>", fs:read("o/fr/img/d.svg"))
  self:assert_equal("ok", fs:read("o/robots.txt"))
  self:assert_nil(fs:read("o/en/.hidden"))
  self:assert_nil(fs:read("o/en/README/index.html"))
  self:assert_true(fs:read("o/fr/index.html"):find('src="/fr/img/d.svg"', 1, true) ~= nil)
end

function T:test_the_body_heading_is_the_h1_and_front_matter_title_overrides_the_label_only()
  -- OQ-35 (owner decision 2026-10-13): the body's single `#` heading is the page title;
  -- front matter `title` only overrides the navigation and `<title>` label.
  local files = {
    ["en/b.md"] = page("Short label", "# The long heading\n\nbody"),
  }
  local fs = build(files, { locales = { { code = "en", label = "English" } } })
  local html = fs:read("o/en/b/index.html")
  self:assert_true(html:find("<title>Short label | hecate</title>", 1, true) ~= nil)
  self:assert_true(html:find('<h1 class="page-title">The long heading</h1>', 1, true) ~= nil)
  self:assert_equal(1, select(2, html:gsub("<h1", "")), "exactly one h1")
end

function T:test_the_title_comes_from_front_matter_then_a_leading_heading()
  local files = {
    ["en/a.md"] = "# From heading\n\nbody",
    ["en/b.md"] = page("From front matter", "# Heading too\n\nbody"),
    ["en/c.md"] = "no title at all",
    ["en/index.md"] = page("Home"),
  }
  local _, report = build(files, { locales = { { code = "en", label = "English" } } })
  local fs = build(files, { locales = { { code = "en", label = "English" } } })
  self:assert_true(fs:read("o/en/a/index.html"):find("<title>From heading | hecate</title>", 1, true) ~= nil)
  self:assert_true(fs:read("o/en/b/index.html"):find("<title>From front matter | hecate</title>", 1, true) ~= nil)
  self:assert_true(fs:read("o/en/c/index.html"):find("<title>C | hecate</title>", 1, true) ~= nil)
  self:assert_equal(1, #report.problems)
  self:assert_true(report.problems[1]:find("en/c.md: no title", 1, true) ~= nil)
  local once = select(2, fs:read("o/en/a/index.html"):gsub("<h1", ""))
  self:assert_equal(1, once, "the leading heading is not repeated")
end

function T:test_edit_link_last_updated_and_outline_switches()
  local files = {
    ["en/index.md"] = page("Home"),
    ["en/a.md"] = page("A", "## S", "last_updated: 2026-10-13\n"),
    ["en/b.md"] = page("B", "## S", "outline: false\n"),
  }
  local fs = build(files, {
    locales = { { code = "en", label = "English" } },
    edit_link_template = "https://git.test/edit/main/website/{path}",
  }, { last_updated = function(path) return path == "c/en/b.md" and "2026-01-02T10:00:00Z" or "not a date" end })
  local a = fs:read("o/en/a/index.html")
  self:assert_true(a:find('<a class="edit-link" href="https://git.test/edit/main/website/en/a.md">', 1, true) ~= nil)
  self:assert_true(a:find('<time datetime="2026-10-13">13 October 2026</time>', 1, true) ~= nil, "front matter wins")
  local b = fs:read("o/en/b/index.html")
  self:assert_true(b:find('<time datetime="2026-01-02">2 January 2026</time>', 1, true) ~= nil, "provider date")
  self:assert_nil(b:find('class="outline"', 1, true))
  local home = fs:read("o/en/index.html")
  self:assert_nil(home:find("<time", 1, true), "a date that cannot be read is left out")
end

function T:test_generated_pages_link_to_their_source_file_or_have_no_edit_link()
  local files = {
    ["en/index.md"] = page("Home"),
    ["en/gen.md"] = page("Gen", "## S", 'generated: true\nsource: "packages/x/src/hecate/x/init.lua"\n'),
    ["en/nosource.md"] = page("No source", "## S", "generated: true\n"),
  }
  local fs = build(files, {
    locales = { { code = "en", label = "English" } },
    edit_link_template = "https://git.test/edit/main/website/{path}",
    source_edit_link_template = "https://git.test/edit/main/{path}",
  })
  local gen = fs:read("o/en/gen/index.html")
  self:assert_true(gen:find('<a class="edit-link" href="https://git.test/edit/main/packages/x/src/hecate/x/init.lua">', 1, true) ~= nil)
  self:assert_nil(fs:read("o/en/nosource/index.html"):find('class="edit-link"', 1, true))
  self:assert_true(fs:read("o/en/index.html"):find('website/en/index.md', 1, true) ~= nil, "hand-written pages keep theirs")
  local without = build(files, {
    locales = { { code = "en", label = "English" } },
    edit_link_template = "https://git.test/edit/main/website/{path}",
  })
  self:assert_nil(without:read("o/en/gen/index.html"):find('class="edit-link"', 1, true), "no source pattern, no link")
end

function T:test_french_dates_use_french_month_names()
  local fs = build({ ["en/index.md"] = page("Home"), ["fr/index.md"] = page("Accueil", "x", "last_updated: 2026-02-03\n") },
    { edit_link_template = "https://git.test/{path}" })
  self:assert_true(fs:read("o/fr/index.html"):find('<time datetime="2026-02-03">3 février 2026</time>', 1, true) ~= nil)
end

function T:test_two_files_for_one_url_raise()
  local err = self:assert_error(function()
    build({ ["en/a.md"] = page("A"), ["en/a/index.md"] = page("A2") }, { locales = { { code = "en", label = "English" } } })
  end)
  self:assert_true(core.is_instance_of(err, doc.BuildError))
  self:assert_true(err.message:find("same URL", 1, true) ~= nil)
end

function T:test_page_ids_that_are_not_windows_file_names_raise()
  local names = { "what?", "a:b", "star*", 'quote"', "lt<", "gt>", "pipe|", "dot.", "space ", "CON", "con", "Aux", "NUL",
    "COM1", "lpt9", "CON.txt", "guide/prn", "guide./a" }
  for _, name in ipairs(names) do
    local err = self:assert_error(function()
      build({ ["en/index.md"] = page("Home"), ["en/" .. name .. ".md"] = page("X") }, { locales = { { code = "en", label = "English" } } })
    end)
    self:assert_true(core.is_instance_of(err, doc.BuildError), name)
    self:assert_true(err.message:find("Windows", 1, true) ~= nil, name .. ": " .. err.message)
    self:assert_true(err.context.path:find("c/en/", 1, true) == 1, name .. ": the path names the file")
  end
end

function T:test_a_page_id_that_is_not_a_windows_file_name_raises_in_a_translation_too()
  local err = self:assert_error(function() build({ ["en/index.md"] = page("Home"), ["fr/a?.md"] = page("A") }) end)
  self:assert_true(core.is_instance_of(err, doc.BuildError))
end

function T:test_names_that_only_look_reserved_are_pages()
  local fs = build({ ["en/index.md"] = page("Home"), ["en/console.md"] = page("C"), ["en/com10.md"] = page("D"),
    ["en/.hidden?.md"] = page("H") }, { locales = { { code = "en", label = "English" } } })
  self:assert_not_nil(fs:read("o/en/console/index.html"))
  self:assert_not_nil(fs:read("o/en/com10/index.html"))
end

function T:test_ids_that_differ_only_in_unicode_normalisation_raise()
  local err = self:assert_error(function()
    build({ ["en/index.md"] = page("Home"), ["en/caf\u{E9}.md"] = page("A"), ["en/cafe\u{301}.md"] = page("B") },
      { locales = { { code = "en", label = "English" } } })
  end)
  self:assert_true(core.is_instance_of(err, doc.BuildError))
  self:assert_true(err.message:find("normalisation", 1, true) ~= nil, err.message)
  local in_directory = self:assert_error(function()
    build({ ["en/index.md"] = page("Home"), ["en/\u{C5}/a.md"] = page("A"), ["en/A\u{30A}/a.md"] = page("B") },
      { locales = { { code = "en", label = "English" } } })
  end)
  self:assert_true(core.is_instance_of(in_directory, doc.BuildError))
end

function T:test_ids_of_other_scripts_that_differ_only_in_normalisation_raise()
  local locales = { locales = { { code = "en", label = "English" } } }
  for name, pair in pairs({ cyrillic = { "\u{439}", "\u{438}\u{306}" }, greek = { "\u{3AC}", "\u{3B1}\u{301}" },
    hangul = { "\u{AC01}", "\u{1100}\u{1161}\u{11A8}" }, marks = { "a\u{301}\u{323}", "a\u{323}\u{301}" } }) do
    local err = self:assert_error(function()
      build({ ["en/index.md"] = page("Home"), ["en/" .. pair[1] .. ".md"] = page("A"), ["en/" .. pair[2] .. ".md"] = page("B") }, locales)
    end)
    self:assert_true(core.is_instance_of(err, doc.BuildError), name)
  end
end

function T:test_a_decomposed_name_is_the_same_page_as_the_composed_one_in_another_locale()
  local fs = build({ ["en/index.md"] = page("Home"), ["en/caf\u{E9}.md"] = page("Coffee"),
    ["fr/index.md"] = page("Accueil"), ["fr/cafe\u{301}.md"] = page("Caf\u{E9}") })
  self:assert_not_nil(fs:read("o/fr/caf\u{E9}/index.html"))
  self:assert_true(fs.files["o/fr/cafe\u{301}/index.html"] == nil, "one directory, in composed form")
  self:assert_true(fs:read("o/fr/caf\u{E9}/index.html"):find("Caf\u{E9}", 1, true) ~= nil)
end

function T:test_a_link_written_in_decomposed_form_finds_the_composed_page()
  local fs = build({ ["en/index.md"] = "---\ntitle: Home\n---\n[go](cafe\u{301}.md)\n", ["en/caf\u{E9}.md"] = page("Coffee") },
    { locales = { { code = "en", label = "English" } } })
  self:assert_true(fs:read("o/en/index.html"):find("caf%C3%A9/", 1, true) ~= nil)
end

function T:test_a_site_without_default_locale_pages_raises()
  local err = self:assert_error(function() build({ ["fr/a.md"] = page("A") }) end)
  self:assert_true(core.is_instance_of(err, doc.BuildError))
end

function T:test_clean_removes_stale_files_of_a_previous_build_only()
  local fs = build(BASIC)
  fs:write("o/stale.html", "old")
  doc.build({ site_configuration = config_with(), guides_dir = "c", output_dir = "o", file_system = fs, clean_output_dir = true })
  self:assert_nil(fs:read("o/stale.html"))
  self:assert_not_nil(fs:read("o/en/index.html"))
  local foreign = doc.MemoryFileSystem({ ["c/en/index.md"] = page("Home"), ["o/precious.txt"] = "keep" })
  local err = self:assert_error(function()
    doc.build({ site_configuration = config_with(), guides_dir = "c", output_dir = "o", file_system = foreign, clean_output_dir = true })
  end)
  self:assert_true(core.is_instance_of(err, doc.BuildError))
  self:assert_equal("keep", foreign:read("o/precious.txt"))
end

function T:test_builds_are_deterministic()
  local first = build(BASIC, { site_origin = "https://x.test" }, { last_updated = function() return "2026-10-13" end })
  local second = build(BASIC, { site_origin = "https://x.test" }, { last_updated = function() return "2026-10-13" end })
  local count = 0
  for path, data in pairs(first.files) do
    count = count + 1
    self:assert_true(second.files[path] == data, path)
  end
  self:assert_true(count > 20)
  for path in pairs(second.files) do self:assert_not_nil(first.files[path]) end
end

function T:test_the_site_api_rejects_misuse()
  local fs = doc.MemoryFileSystem()
  ---@diagnostic disable-next-line: missing-fields  -- the misuse under test
  self:assert_true(core.is_instance_of(self:assert_error(function() doc.Site({}) end), core.ArgumentError))
  local site = doc.Site({ site_configuration = { title = "t" }, guides_dir = "c", file_system = fs })
  self:assert_true(core.is_instance_of(self:assert_error(function() site:pages("en") end), core.ArgumentError))
  ---@diagnostic disable-next-line: missing-fields  -- the misuse under test
  self:assert_true(core.is_instance_of(self:assert_error(function() doc.build({}) end), core.ArgumentError))
end

function T:test_the_site_exposes_pages_after_loading()
  local fs = doc.MemoryFileSystem({ ["c/en/index.md"] = page("Home"), ["c/en/a.md"] = page("A") })
  local site = doc.Site({ site_configuration = { title = "t" }, guides_dir = "c", file_system = fs }):load()
  self:assert_equal(2, #site:pages("en"))
  self:assert_equal("A", site:page("en", "a").title)
  self:assert_equal("/en/a/", site:page("en", "a").url)
  self:assert_nil(site:page("en", "zzz"))
end

function T:test_configuration_files_run_without_an_environment()
  local fs = doc.MemoryFileSystem({
    ["ok.lua"] = "return { title = 'T' }",
    ["io.lua"] = "return { title = io.open('x') }",
    ["syntax.lua"] = "return {",
    ["scalar.lua"] = "return 3",
  })
  self:assert_equal("T", doc.load_site_configuration(fs, "ok.lua").title)
  for _, name in ipairs({ "io.lua", "syntax.lua", "scalar.lua" }) do
    self:assert_true(core.is_instance_of(self:assert_error(function() doc.load_site_configuration(fs, name) end), core.ConfigurationError), name)
  end
  self:assert_true(core.is_instance_of(self:assert_error(function() doc.load_site_configuration(fs, "none.lua") end), doc.BuildError))
end

function T:test_generated_pages_keep_their_header_comment_out_of_the_output()
  local fs = build({ ["en/reference/gen.md"] = "<!-- Generated by gen-reference. Do not edit by hand. -->\n---\n" })
  self:assert_nil(fs:read("o/en/reference/gen/index.html"):find("Generated by gen-reference", 1, true))
end

function T:test_a_page_that_is_not_valid_utf8_raises_a_build_error_naming_the_file()
  local err = self:assert_error(function()
    build({ ["en/index.md"] = page("Home", "ok"), ["en/bad.md"] = "---\ntitle: Bad\n---\nbroken \xFF\xFE text\n" })
  end)
  self:assert_true(core.is_instance_of(err, doc.BuildError), tostring(err))
  self:assert_true(err.context.path:find("en/bad.md", 1, true) ~= nil, tostring(err.context.path))
  self:assert_true(tostring(err):find("UTF-8", 1, true) ~= nil, tostring(err))
  self:assert_true(tostring(err):find("position 27", 1, true) ~= nil, tostring(err))
end

function T:test_two_outputs_that_differ_only_by_case_are_refused()
  local err = self:assert_error(function()
    build({ ["en/index.md"] = page("Home", "ok"), ["en/Guide.md"] = page("Upper", "u"), ["en/guide.md"] = page("Lower", "l") },
      { locales = { { code = "en", label = "English" } } })
  end)
  self:assert_true(core.is_instance_of(err, doc.BuildError), tostring(err))
  local message = tostring(err)
  self:assert_true(message:find("en/Guide/index.html", 1, true) ~= nil and message:find("en/guide/index.html", 1, true) ~= nil,
    message)
  local public = self:assert_error(function()
    build({ ["en/index.md"] = page("Home", "ok"), ["public/EN/INDEX.HTML"] = "mine" },
      { locales = { { code = "en", label = "English" } } })
  end)
  self:assert_true(core.is_instance_of(public, doc.BuildError), tostring(public))
end

function T:test_a_public_file_that_collides_with_a_generated_file_is_refused()
  for _, name in ipairs({ "404.html", "index.html", "assets/theme.css", "en/index.html", "en/guide/index.html",
    "assets/search-en.json" }) do
    local err = self:assert_error(function()
      build({ ["en/index.md"] = page("Home", "ok"), ["en/guide/index.md"] = page("Guide", "g"), ["public/" .. name] = "mine" },
        { locales = { { code = "en", label = "English" } } })
    end, nil)
    self:assert_true(core.is_instance_of(err, doc.BuildError), name .. ": " .. tostring(err))
    self:assert_true(tostring(err):find(name, 1, true) ~= nil, tostring(err))
    self:assert_true(tostring(err):find("public/", 1, true) ~= nil, tostring(err))
  end
  local fs = build({ ["en/index.md"] = page("Home", "ok"), ["public/extra/robots.txt"] = "fine" },
    { locales = { { code = "en", label = "English" } } })
  self:assert_equal("fine", fs:read("o/extra/robots.txt"))
end

function T:test_page_ids_are_percent_encoded_in_urls_and_links()
  local files = {
    ["en/index.md"] = page("Home", "[odd](a%20b/caf\u{e9}.md) [h](a%20b/caf\u{e9}.md#frag)\n\n![i](img%20x.svg) [q](a%20b/q%23%25.md)"),
    ["en/guide/index.md"] = page("Guide", "g"),
    ["en/a b/caf\u{e9}.md"] = page("Cafe", "c"),
    ["en/a b/q#%.md"] = page("Query", "q"),
    ["en/img x.svg"] = "<svg/>",
  }
  local fs = build(files, { site_origin = "https://x.test", locales = { { code = "en", label = "English" } } })
  local home = fs:read("o/en/index.html")
  self:assert_true(home:find('href="/en/a%20b/caf%C3%A9/"', 1, true) ~= nil, "link to a page with a space and an accent")
  self:assert_true(home:find('href="/en/a%20b/caf%C3%A9/#frag"', 1, true) ~= nil)
  self:assert_nil(home:find('href="/en/a b/', 1, true))
  self:assert_true(home:find("/en/a%20b/q%23%25/", 1, true) ~= nil, "# and % are encoded")
  local sitemap = fs:read("o/sitemap.xml")
  self:assert_true(sitemap:find("https://x.test/en/a%20b/caf%C3%A9/", 1, true) ~= nil)
  self:assert_nil(sitemap:find("a b", 1, true))
  self:assert_equal("<svg/>", fs:read("o/en/img x.svg"))
  self:assert_true(home:find('src="/en/img%20x.svg"', 1, true) ~= nil)
  self:assert_not_nil(fs:read("o/en/a b/café/index.html"), "files keep their real names on disk")
end

function T:test_a_logo_or_theme_file_missing_from_public_fails_the_build()
  local missing = self:assert_error(function() build(BASIC, { logo_path = "nope.svg" }) end)
  self:assert_true(core.is_instance_of(missing, doc.BuildError))
  local css = self:assert_error(function() build(BASIC, { stylesheet_path = "nope.css" }) end)
  self:assert_true(core.is_instance_of(css, doc.BuildError))
end

function T:test_logo_and_theme_are_served_from_public()
  local files = {}
  for path, data in pairs(BASIC) do files[path] = data end
  files["public/brand/logo.svg"] = "<svg/>"
  files["public/brand/logo-dark.svg"] = "<svg/>"
  files["public/theme.css"] = ":root { --moon: #123456; }"
  local fs = build(files, { logo_path = { light = "brand/logo.svg", dark = "brand/logo-dark.svg" }, stylesheet_path = "theme.css" })
  local home = fs:read("o/en/index.html")
  self:assert_true(home:find('src="/brand/logo.svg"', 1, true) ~= nil)
  self:assert_true(home:find('src="/brand/logo-dark.svg"', 1, true) ~= nil)
  self:assert_nil(home:find("hecate-logo-horizontal", 1, true))
  local theme_at = home:find("assets/theme.css", 1, true)
  local theme_file_at = home:find('href="/theme.css"', 1, true)
  self:assert_true(theme_at ~= nil and theme_file_at ~= nil and theme_file_at > theme_at, "override file after the theme")
  files["public/brand/logo.svg"] = nil
  local single = build({ ["en/index.md"] = BASIC["en/index.md"], ["public/l.svg"] = "<svg/>" }, { logo_path = "l.svg" })
  local text = single:read("o/en/index.html")
  self:assert_true(text:find('src="/l.svg"', 1, true) ~= nil)
  self:assert_nil(text:find("logo-dark", 1, true))
end

function T:test_the_sidebar_marker_is_off_unless_the_configuration_asks_for_it()
  local plain = build(BASIC, {}):read("o/en/index.html")
  self:assert_nil(plain:find("sidebar-marker", 1, true))
  local marked = build(BASIC, { sidebar_marker = true }):read("o/en/index.html")
  -- BASIC's `en/index.md` is a documentation page (no `layout: home`): exactly this body class, not either of two
  -- (the home layout and the 404 page are in `theme_details_test.lua`).
  self:assert_true(marked:find('<body class="doc-page sidebar-marker">', 1, true) ~= nil, marked:match("<body[^>]*>"))
  self:assert_nil(marked:find('<body class="home', 1, true))
end

function T:test_the_default_favicon_is_the_adaptive_hecate_one()
  local home = build(BASIC, {}):read("o/en/index.html")
  self:assert_true(home:find('<link rel="icon" href="/assets/brand/favicon.svg" type="image/svg+xml">', 1, true) ~= nil)
  self:assert_nil(home:find('<link rel="icon"', home:find('<link rel="icon"', 1, true) + 1, true), "one icon link, not one per scheme")
end

function T:test_a_favicon_of_public_replaces_the_default_with_its_type_and_media()
  local files = {}
  for path, data in pairs(BASIC) do files[path] = data end
  files["public/icon.png"] = "png"
  files["public/icon-dark.ico"] = "ico"
  files["public/mark.svg"] = "<svg/>"
  local single = build(files, { favicon_path = "mark.svg" }):read("o/en/index.html")
  self:assert_true(single:find('<link rel="icon" href="/mark.svg" type="image/svg+xml">', 1, true) ~= nil)
  self:assert_nil(single:find("assets/brand/favicon.svg", 1, true))
  local pair = build(files, { favicon_path = { light = "icon.png", dark = "icon-dark.ico" } }):read("o/en/index.html")
  self:assert_true(pair:find('<link rel="icon" href="/icon.png" type="image/png" media="(prefers-color-scheme: light)">', 1, true) ~= nil)
  self:assert_true(pair:find('<link rel="icon" href="/icon-dark.ico" type="image/x-icon" media="(prefers-color-scheme: dark)">', 1, true) ~= nil)
  self:assert_nil(pair:find("assets/brand/favicon.svg", 1, true))
  local alone = build(files, { favicon_path = { light = "icon.png" } }):read("o/en/index.html")
  self:assert_true(alone:find('<link rel="icon" href="/icon.png" type="image/png">', 1, true) ~= nil)
end

function T:test_a_missing_favicon_fails_the_build()
  local missing = self:assert_error(function() build(BASIC, { favicon_path = "nope.svg" }) end)
  self:assert_true(core.is_instance_of(missing, doc.BuildError))
end

function T:test_a_missing_logo_fails_before_any_output_is_written()
  local files = {}
  for path, data in pairs(BASIC) do files["c/" .. path] = data end
  local fs = doc.MemoryFileSystem(files)
  self:assert_error(function()
    doc.build({ site_configuration = config_with({ logo_path = { light = "a.svg", dark = "missing.svg" } }), guides_dir = "c", output_dir = "o", file_system = fs })
  end)
  for path in pairs(fs.files) do self:assert_nil(path:find("^o/"), path .. " was written") end
end

function T:test_the_logo_is_served_on_every_page_under_a_sub_path_base()
  local files = {}
  for path, data in pairs(BASIC) do files[path] = data end
  files["fr/index.md"] = page("Accueil", "bonjour")
  files["public/my logo.svg"] = "<svg/>"
  files["public/c.css"] = "x"
  local fs = build(files, { base_path = "/docs", logo_path = "my logo.svg", stylesheet_path = "c.css" })
  for _, path in ipairs({ "o/en/index.html", "o/fr/index.html", "o/404.html" }) do
    local text = fs:read(path)
    self:assert_not_nil(text:find('src="/docs/my%20logo.svg"', 1, true), path)
    self:assert_not_nil(text:find('href="/docs/c.css"', 1, true), path)
  end
end

function T:test_case_variants_of_a_page_id_and_normalised_asset_names_are_detected_when_scanning()
  local err = self:assert_error(function()
    build({ ["en/index.md"] = page("Home", "ok"), ["en/A.md"] = page("A", "a"), ["en/a.md"] = page("a", "b") })
  end)
  self:assert_not_nil(tostring(err):find("differ only by case", 1, true), tostring(err))
  local files = { ["en/index.md"] = page("Home", "ok"), ["en/img/e\u{301}.svg"] = "<svg/>", ["en/img/\u{E9}.svg"] = "<svg/>" }
  local clash = self:assert_error(function() build(files) end)
  self:assert_not_nil(tostring(clash):find("Unicode normalisation", 1, true), tostring(clash))
end

function T:test_decomposed_sidebar_ids_and_asset_links_resolve()
  local fs, report = build({
    ["en/index.md"] = page("Home", "![p](img/e\u{301}.svg)"), ["en/caf\u{E9}.md"] = page("Cafe", "x"),
    ["en/img/e\u{301}.svg"] = "<svg/>",
  }, { sidebar = { ["caf\u{E9}"] = { "cafe\u{301}" } } })
  self:assert_equal(0, #report.problems, table.concat(report.problems, "\n"))
  self:assert_equal("<svg/>", fs:read("o/en/img/\u{E9}.svg"))
end

-- Audiences (OQ-144, owner decision of 2026-11-21): the plain builder knows no audience. A documentation site is built from
-- one content tree; the two audiences are two trees, each built into its own directory.
local ONE_LOCALE = { locales = { { code = "en", label = "English" } }, site_origin = "https://x.test" }

function T:test_the_old_front_matter_key_audience_is_refused_naming_the_file_and_the_new_layout()
  for _, value in ipairs({ "user", "maintainer", "operator", "3", "true" }) do
    local files = {}
    for path, data in pairs(BASIC) do files[path] = data end
    files["en/guide/a.md"] = page("Alpha", "x", "audience: " .. value .. "\n")
    local err = self:assert_error(function() build(files, ONE_LOCALE) end)
    self:assert_true(core.is_instance_of(err, doc.BuildError), value)
    local text = tostring(err)
    self:assert_true(text:find("c/en/guide/a.md", 1, true) ~= nil, text)
    self:assert_true(text:find("`audience`", 1, true) ~= nil, text)
    self:assert_true(text:find("<guides_dir>/<audience>/<locale>/", 1, true) ~= nil, "the message names the new layout: " .. text)
  end
  -- A translation that still carries the key is refused too, and nothing is written.
  local files = {}
  for path, data in pairs(BASIC) do files[path] = data end
  files["fr/guide/a.md"] = page("Alpha FR", "x", "audience: user\n")
  local prefixed = {}
  for path, data in pairs(files) do prefixed["c/" .. path] = data end
  local fs = doc.MemoryFileSystem(prefixed)
  local err = self:assert_error(function()
    doc.build({ site_configuration = config_with(), guides_dir = "c", output_dir = "o", file_system = fs })
  end)
  self:assert_true(tostring(err):find("c/fr/guide/a.md", 1, true) ~= nil, tostring(err))
  self:assert_nil(fs:read("o/en/index.html"))
end

function T:test_two_content_trees_are_two_independent_sites_built_by_the_plain_builder()
  local files = {
    ["user/en/index.md"] = page("Welcome users", "welcome ![x](pic.svg)"),
    ["user/en/guide/index.md"] = page("Guide", "start", "order: 1\ndescription: For users.\n"),
    ["user/en/guide/a.md"] = page("Alpha", "alphaword [there](https://x.test/maintainer/en/design/)", "order: 2\n"),
    ["user/en/pic.svg"] = "<svg id=\"user\"/>",
    ["user/public/logo.svg"] = "<svg id=\"user-logo\"/>",
    ["maintainer/en/index.md"] = page("Welcome maintainers", "inside"),
    ["maintainer/en/internals/index.md"] = page("Internals", "start", "order: 1\ndescription: For maintainers.\n"),
    ["maintainer/en/internals/design.md"] = page("Design", "xylophone", "order: 2\n"),
    ["maintainer/public/own.svg"] = "<svg id=\"maintainer\"/>",
  }
  local fs = doc.MemoryFileSystem((function()
    local prefixed = {}
    for path, data in pairs(files) do prefixed["c/" .. path] = data end
    return prefixed
  end)())
  local reports = {}
  for _, audience in ipairs({ "user", "maintainer" }) do
    reports[audience] = doc.build({
      site_configuration = config_with({ locales = ONE_LOCALE.locales, site_origin = ONE_LOCALE.site_origin, generate_llms_txt = true,
        base_path = "/" .. audience .. "/" }),
      guides_dir = "c/" .. audience, output_dir = "o/" .. audience, file_system = fs, fail_on_problems = true,
    })
    self:assert_equal(0, #reports[audience].problems, audience)
  end
  -- Each site has its own pages, files, navigation, search index, sitemap, llms.txt and 404 page.
  for _, audience in ipairs({ "user", "maintainer" }) do
    for _, file in ipairs({ "404.html", "index.html", "sitemap.xml", "llms.txt", "llms-full.txt", "assets/theme.css",
      "assets/search-en.json", ".hecate-doc-output", "en/index.html" }) do
      self:assert_not_nil(fs:read("o/" .. audience .. "/" .. file), audience .. "/" .. file)
    end
  end
  self:assert_equal(3, reports.user.locales.en.pages)
  self:assert_equal(3, reports.maintainer.locales.en.pages)
  -- A page of one tree is in no file of the other site.
  self:assert_nil(fs:read("o/user/en/internals/design/index.html"))
  self:assert_nil(fs:read("o/maintainer/en/guide/a/index.html"))
  for _, file in ipairs({ "assets/search-en.json", "sitemap.xml", "llms.txt", "llms-full.txt", "404.html", "en/index.html" }) do
    local user_text, maintainer_text = fs:read("o/user/" .. file), fs:read("o/maintainer/" .. file)
    self:assert_nil(user_text:find("xylophone", 1, true), "user " .. file)
    self:assert_nil(user_text:find("internals", 1, true), "user " .. file)
    self:assert_nil(maintainer_text:find("alphaword", 1, true), "maintainer " .. file)
    self:assert_nil(maintainer_text:find("/guide/", 1, true), "maintainer " .. file)
  end
  self:assert_not_nil(fs:read("o/user/sitemap.xml"):find("https://x.test/user/en/guide/a/", 1, true))
  self:assert_not_nil(fs:read("o/maintainer/sitemap.xml"):find("https://x.test/maintainer/en/internals/design/", 1, true))
  self:assert_not_nil(fs:read("o/maintainer/llms.txt"):find("For maintainers.", 1, true))
  self:assert_nil(fs:read("o/user/llms.txt"):find("For maintainers.", 1, true))
  -- Own navigation, own theme assets (each tree is served below its own base path).
  local user_page = fs:read("o/user/en/guide/a/index.html")
  self:assert_not_nil(user_page:find('href="/user/assets/theme.css"', 1, true))
  self:assert_nil(user_page:find("/maintainer/assets", 1, true))
  self:assert_not_nil(fs:read("o/maintainer/en/internals/design/index.html"):find('href="/maintainer/assets/theme.css"', 1, true))
  -- Each tree has its own `public/` and its own files next to the pages.
  self:assert_equal("<svg id=\"user-logo\"/>", fs:read("o/user/logo.svg"))
  self:assert_nil(fs:read("o/maintainer/logo.svg"))
  self:assert_equal("<svg id=\"maintainer\"/>", fs:read("o/maintainer/own.svg"))
  self:assert_nil(fs:read("o/user/own.svg"))
  self:assert_equal("<svg id=\"user\"/>", fs:read("o/user/en/pic.svg"))
  self:assert_nil(fs:read("o/maintainer/en/pic.svg"))
  -- Each tree needs its own home page: the other tree's `index.md` does not count.
  local lonely = doc.MemoryFileSystem({ ["c/user/en/index.md"] = page("Home"), ["c/maintainer/en/design.md"] = page("Design") })
  local report = doc.build({ site_configuration = config_with({ locales = ONE_LOCALE.locales }), guides_dir = "c/maintainer",
    output_dir = "o/maintainer", file_system = lonely })
  self:assert_equal(1, #report.problems, table.concat(report.problems, "\n"))
  self:assert_true(report.problems[1]:find("no home page in locale en: add c/maintainer/en/index.md", 1, true) ~= nil, report.problems[1])
end

function T:test_a_relative_link_that_leaves_the_tree_is_left_as_written_and_one_that_leaves_the_locale_is_a_problem()
  -- The tree of another audience is a sibling directory, so a link to its site climbs out of the tree: the builder cannot
  -- check it and leaves it for the browser, which reads it against the URL of the page. A link to the content root only
  -- (`../x.md`: the locale directories are there) is a mistake or a link to another locale, and stays a problem.
  local files = {
    ["en/index.md"] = page("Home", "[a](../../user/en/) [b](../../../user/en/guide/) [c](../x.md) [d](index.md)"),
    ["en/guide/index.md"] = page("Guide", "[e](../../../../user/en/) [f](../../x.md)"),
  }
  local fs, report = build(files, ONE_LOCALE)
  self:assert_equal(2, #report.problems, table.concat(report.problems, "\n"))
  self:assert_true(report.problems[1]:find("en/guide/index.md: link ../../x.md leaves the locale directory", 1, true) ~= nil, report.problems[1])
  self:assert_true(report.problems[2]:find("en/index.md: link ../x.md leaves the locale directory", 1, true) ~= nil, report.problems[2])
  local home = fs:read("o/en/index.html")
  self:assert_true(home:find('href="../../user/en/"', 1, true) ~= nil, "left as written")
  self:assert_true(home:find('href="../../../user/en/guide/"', 1, true) ~= nil, "left as written")
  self:assert_true(fs:read("o/en/guide/index.html"):find('href="../../../../user/en/"', 1, true) ~= nil)
end

function T:test_the_theme_file_can_change_fonts_and_ship_font_files_from_public()
  local files = {}
  for path, data in pairs(BASIC) do files[path] = data end
  files["public/own.css"] = '@font-face { font-family: "Own"; src: url("fonts/own.woff2") format("woff2"); }\n'
    .. ":root { --serif: \"Own\", serif; --sans: \"Own\", sans-serif; --mono: \"Own Mono\", monospace; }\n"
  files["public/fonts/own.woff2"] = "wOF2"
  local fs = build(files, { stylesheet_path = "own.css" })
  self:assert_equal("wOF2", fs:read("o/fonts/own.woff2"), "a font file of public/ is copied, next to the theme file")
  self:assert_not_nil(fs:read("o/own.css"):find('url("fonts/own.woff2")', 1, true), "the theme file is served as written")
  -- The theme file comes after the stylesheet of the theme, so its custom properties win at equal specificity.
  local home = fs:read("o/en/index.html")
  self:assert_true(home:find("assets/theme.css", 1, true) < home:find('href="/own.css"', 1, true))
end

function T:test_a_file_of_public_cannot_replace_the_stylesheet_of_the_theme()
  local files = {}
  for path, data in pairs(BASIC) do files[path] = data end
  files["public/assets/theme.css"] = ":root { --earth: red; }"
  local err = self:assert_error(function() build(files) end)
  self:assert_true(core.is_instance_of(err, doc.BuildError))
end

-- llms.txt and llms-full.txt (llmstxt.org): opt-in, the pages of the default locale.
local LLMS_FILES = {
  ["en/index.md"] = page("Home", "welcome", "description: Start page.\n"),
  ["en/guide/index.md"] = page("Guide", "start", "order: 1\ndescription: Where to begin.\n"),
  ["en/guide/a.md"] = page("Alpha [one]", "alphaword", "order: 2\n"),
  ["en/guide/b.md"] = page("Beta", "betaword", "order: 3\ndescription: \"Second\\nline.\"\n"),
  ["en/guide/zeta.md"] = page("Zeta", "xylophone", "order: 4\ndescription: Last page.\n"),
  ["en/other/x.md"] = "---\ndescription: An x.\n---\nno heading here\n",
  ["fr/index.md"] = page("Accueil", "bonjour"),
  ["fr/guide/a.md"] = page("Alpha FR", "frenchword"),
}

function T:test_llms_files_are_not_written_unless_asked_and_public_files_pass_through()
  local files = {}
  for path, data in pairs(LLMS_FILES) do files[path] = data end
  files["public/llms.txt"] = "hand-written\n"
  local fs = build(files, { site_origin = "https://x.test" })
  self:assert_equal("hand-written\n", fs:read("o/llms.txt"))
  self:assert_nil(fs:read("o/llms-full.txt"))
end

function T:test_llms_txt_lists_the_pages_of_the_default_locale_by_section()
  local fs = build(LLMS_FILES, { site_origin = "https://x.test/", generate_llms_txt = true, description = { en = "A site.", fr = "Un site." } })
  local expected = table.concat({
    "# hecate",
    "",
    "> A site.",
    "",
    "- [Home](https://x.test/en/): Start page.",
    "",
    "## Guide",
    "",
    "- [Guide](https://x.test/en/guide/): Where to begin.",
    "- [Alpha \\[one\\]](https://x.test/en/guide/a/)",
    "- [Beta](https://x.test/en/guide/b/): Second line.",
    "- [Zeta](https://x.test/en/guide/zeta/): Last page.",
    "",
    "## Other",
    "",
    "- [X](https://x.test/en/other/x/): An x.",
    "",
  }, "\n")
  self:assert_equal(expected, fs:read("o/llms.txt"))
end

function T:test_llms_links_follow_the_base_without_a_public_url()
  local fs = build(LLMS_FILES, { generate_llms_txt = true, base_path = "/docs/" })
  local text = fs:read("o/llms.txt")
  self:assert_not_nil(text:find("- [Home](/docs/en/): Start page.", 1, true), text)
  self:assert_nil(text:find("> ", 1, true), "no summary without a description")
end

function T:test_llms_full_txt_concatenates_the_markdown_of_the_pages()
  local fs = build(LLMS_FILES, { site_origin = "https://x.test", generate_llms_txt = true })
  local text = fs:read("o/llms-full.txt")
  self:assert_not_nil(text:find("alphaword", 1, true))
  self:assert_not_nil(text:find("betaword", 1, true))
  self:assert_not_nil(text:find("Source: https://x.test/en/guide/a/", 1, true))
  self:assert_not_nil(text:find("xylophone", 1, true))
  self:assert_nil(text:find("frenchword", 1, true), "the default locale only")
  self:assert_nil(text:find("description:", 1, true), "front matter is not part of the Markdown")
  self:assert_true(text:find("alphaword", 1, true) < text:find("betaword", 1, true), "reading order")
  -- A page without a heading in its body gets one from its title.
  self:assert_not_nil(text:find("# X\n\nno heading here", 1, true), text)
  self:assert_equal("\n", text:sub(-1))
  self:assert_nil(text:find("\n\n\n", 1, true))
end

function T:test_llms_files_are_deterministic()
  local first = build(LLMS_FILES, { site_origin = "https://x.test", generate_llms_txt = true })
  local second = build(LLMS_FILES, { site_origin = "https://x.test", generate_llms_txt = true })
  self:assert_equal(first:read("o/llms.txt"), second:read("o/llms.txt"))
  self:assert_equal(first:read("o/llms-full.txt"), second:read("o/llms-full.txt"))
  self:assert_not_nil(first:read("o/llms.txt"):find("[Zeta](https://x.test/en/guide/zeta/): Last page.", 1, true))
  self:assert_not_nil(first:read("o/llms-full.txt"):find("xylophone", 1, true))
end

function T:test_a_file_of_public_named_like_a_llms_file_collides_when_llms_is_on()
  local files = {}
  for path, data in pairs(LLMS_FILES) do files[path] = data end
  files["public/llms-full.txt"] = "mine"
  local err = self:assert_error(function() build(files, { generate_llms_txt = true }) end)
  self:assert_true(core.is_instance_of(err, doc.BuildError))
  self:assert_not_nil(tostring(err):find("llms-full.txt", 1, true), tostring(err))
end

return T
