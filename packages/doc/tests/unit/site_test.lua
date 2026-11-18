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
  local arguments = { config = config_with(extra), source = "c", out = "o", fs = fs }
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
  local fs, report = build(files, { url = "https://x.test" })
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
  local fs = build(files, { url = "https://x.test/" })
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
  local fs = build(BASIC, { base = "/docs/" })
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
    ["en/index.md"] = page("Home", "[a](nope.md) ![i](missing.png) [out](../../x.md) [ok](index.md)"),
  }
  local _, report = build(files, { locales = { { code = "en", label = "English" } } })
  self:assert_equal(3, #report.problems)
  self:assert_true(report.problems[1]:find("broken link nope.md", 1, true) ~= nil)
  self:assert_true(report.problems[2]:find("leaves the content root", 1, true) ~= nil)
  self:assert_true(report.problems[3]:find("missing file missing.png", 1, true) ~= nil)
end

function T:test_strict_mode_raises_a_build_error_listing_the_problems()
  local err = self:assert_error(function()
    build({ ["en/index.md"] = page("Home", "[a](nope.md)") }, { locales = { { code = "en", label = "English" } } }, { strict = true })
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
    edit_link = "https://git.test/edit/main/website/{path}",
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
    edit_link = "https://git.test/edit/main/website/{path}",
    source_edit_link = "https://git.test/edit/main/{path}",
  })
  local gen = fs:read("o/en/gen/index.html")
  self:assert_true(gen:find('<a class="edit-link" href="https://git.test/edit/main/packages/x/src/hecate/x/init.lua">', 1, true) ~= nil)
  self:assert_nil(fs:read("o/en/nosource/index.html"):find('class="edit-link"', 1, true))
  self:assert_true(fs:read("o/en/index.html"):find('website/en/index.md', 1, true) ~= nil, "hand-written pages keep theirs")
  local without = build(files, {
    locales = { { code = "en", label = "English" } },
    edit_link = "https://git.test/edit/main/website/{path}",
  })
  self:assert_nil(without:read("o/en/gen/index.html"):find('class="edit-link"', 1, true), "no source pattern, no link")
end

function T:test_french_dates_use_french_month_names()
  local fs = build({ ["en/index.md"] = page("Home"), ["fr/index.md"] = page("Accueil", "x", "last_updated: 2026-02-03\n") },
    { edit_link = "https://git.test/{path}" })
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
  doc.build({ config = config_with(), source = "c", out = "o", fs = fs, clean = true })
  self:assert_nil(fs:read("o/stale.html"))
  self:assert_not_nil(fs:read("o/en/index.html"))
  local foreign = doc.MemoryFileSystem({ ["c/en/index.md"] = page("Home"), ["o/precious.txt"] = "keep" })
  local err = self:assert_error(function()
    doc.build({ config = config_with(), source = "c", out = "o", fs = foreign, clean = true })
  end)
  self:assert_true(core.is_instance_of(err, doc.BuildError))
  self:assert_equal("keep", foreign:read("o/precious.txt"))
end

function T:test_builds_are_deterministic()
  local first = build(BASIC, { url = "https://x.test" }, { last_updated = function() return "2026-10-13" end })
  local second = build(BASIC, { url = "https://x.test" }, { last_updated = function() return "2026-10-13" end })
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
  local site = doc.Site({ config = { title = "t" }, source = "c", fs = fs })
  self:assert_true(core.is_instance_of(self:assert_error(function() site:pages("en") end), core.ArgumentError))
  ---@diagnostic disable-next-line: missing-fields  -- the misuse under test
  self:assert_true(core.is_instance_of(self:assert_error(function() doc.build({}) end), core.ArgumentError))
end

function T:test_the_site_exposes_pages_after_loading()
  local fs = doc.MemoryFileSystem({ ["c/en/index.md"] = page("Home"), ["c/en/a.md"] = page("A") })
  local site = doc.Site({ config = { title = "t" }, source = "c", fs = fs }):load()
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
  self:assert_equal("T", doc.load_config("ok.lua", fs).title)
  for _, name in ipairs({ "io.lua", "syntax.lua", "scalar.lua" }) do
    self:assert_true(core.is_instance_of(self:assert_error(function() doc.load_config(name, fs) end), core.ConfigurationError), name)
  end
  self:assert_true(core.is_instance_of(self:assert_error(function() doc.load_config("none.lua", fs) end), doc.BuildError))
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
  local fs = build(files, { url = "https://x.test", locales = { { code = "en", label = "English" } } })
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
  local missing = self:assert_error(function() build(BASIC, { logo = "nope.svg" }) end)
  self:assert_true(core.is_instance_of(missing, doc.BuildError))
  local css = self:assert_error(function() build(BASIC, { theme = "nope.css" }) end)
  self:assert_true(core.is_instance_of(css, doc.BuildError))
end

function T:test_logo_and_theme_are_served_from_public()
  local files = {}
  for path, data in pairs(BASIC) do files[path] = data end
  files["public/brand/logo.svg"] = "<svg/>"
  files["public/brand/logo-dark.svg"] = "<svg/>"
  files["public/theme.css"] = ":root { --moon: #123456; }"
  local fs = build(files, { logo = { light = "brand/logo.svg", dark = "brand/logo-dark.svg" }, theme = "theme.css" })
  local home = fs:read("o/en/index.html")
  self:assert_true(home:find('src="/brand/logo.svg"', 1, true) ~= nil)
  self:assert_true(home:find('src="/brand/logo-dark.svg"', 1, true) ~= nil)
  self:assert_nil(home:find("hecate-logo-horizontal", 1, true))
  local theme_at = home:find("assets/theme.css", 1, true)
  local theme_file_at = home:find('href="/theme.css"', 1, true)
  self:assert_true(theme_at ~= nil and theme_file_at ~= nil and theme_file_at > theme_at, "override file after the theme")
  files["public/brand/logo.svg"] = nil
  local single = build({ ["en/index.md"] = BASIC["en/index.md"], ["public/l.svg"] = "<svg/>" }, { logo = "l.svg" })
  local text = single:read("o/en/index.html")
  self:assert_true(text:find('src="/l.svg"', 1, true) ~= nil)
  self:assert_nil(text:find("logo-dark", 1, true))
end

function T:test_the_sidebar_marker_is_off_unless_the_configuration_asks_for_it()
  local plain = build(BASIC, {}):read("o/en/index.html")
  self:assert_nil(plain:find("sidebar-marker", 1, true))
  local marked = build(BASIC, { sidebar_marker = true }):read("o/en/index.html")
  self:assert_true(marked:find('<body class="doc-page sidebar-marker">', 1, true) ~= nil or
    marked:find('<body class="home sidebar-marker">', 1, true) ~= nil)
end

function T:test_the_default_favicon_is_the_adaptive_hecate_one()
  local home = build(BASIC, {}):read("o/en/index.html")
  self:assert_true(home:find('<link rel="icon" href="/assets/brand/favicon.svg" type="image/svg+xml">', 1, true) ~= nil)
end

function T:test_a_favicon_of_public_replaces_the_default_with_its_type_and_media()
  local files = {}
  for path, data in pairs(BASIC) do files[path] = data end
  files["public/icon.png"] = "png"
  files["public/icon-dark.ico"] = "ico"
  files["public/mark.svg"] = "<svg/>"
  local single = build(files, { favicon = "mark.svg" }):read("o/en/index.html")
  self:assert_true(single:find('<link rel="icon" href="/mark.svg" type="image/svg+xml">', 1, true) ~= nil)
  self:assert_nil(single:find("assets/brand/favicon.svg", 1, true))
  local pair = build(files, { favicon = { light = "icon.png", dark = "icon-dark.ico" } }):read("o/en/index.html")
  self:assert_true(pair:find('<link rel="icon" href="/icon.png" type="image/png" media="(prefers-color-scheme: light)">', 1, true) ~= nil)
  self:assert_true(pair:find('<link rel="icon" href="/icon-dark.ico" type="image/x-icon" media="(prefers-color-scheme: dark)">', 1, true) ~= nil)
  self:assert_nil(pair:find("assets/brand/favicon.svg", 1, true))
  local alone = build(files, { favicon = { light = "icon.png" } }):read("o/en/index.html")
  self:assert_true(alone:find('<link rel="icon" href="/icon.png" type="image/png">', 1, true) ~= nil)
end

function T:test_a_missing_favicon_fails_the_build()
  local missing = self:assert_error(function() build(BASIC, { favicon = "nope.svg" }) end)
  self:assert_true(core.is_instance_of(missing, doc.BuildError))
end

function T:test_a_missing_logo_fails_before_any_output_is_written()
  local files = {}
  for path, data in pairs(BASIC) do files["c/" .. path] = data end
  local fs = doc.MemoryFileSystem(files)
  self:assert_error(function()
    doc.build({ config = config_with({ logo = { light = "a.svg", dark = "missing.svg" } }), source = "c", out = "o", fs = fs })
  end)
  for path in pairs(fs.files) do self:assert_nil(path:find("^o/"), path .. " was written") end
end

function T:test_the_logo_is_served_on_every_page_under_a_sub_path_base()
  local files = {}
  for path, data in pairs(BASIC) do files[path] = data end
  files["fr/index.md"] = page("Accueil", "bonjour")
  files["public/my logo.svg"] = "<svg/>"
  files["public/c.css"] = "x"
  local fs = build(files, { base = "/docs", logo = "my logo.svg", theme = "c.css" })
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

-- Audiences (OQ-144): a site publishes only the audiences it is asked to.
local AUDIENCE_FILES = {
  ["en/index.md"] = page("Home", "welcome [internals](guide/zeta.md)"),
  ["en/guide/index.md"] = page("Guide", "start", "order: 1\n"),
  ["en/guide/a.md"] = page("Alpha", "alphaword", "order: 2\n"),
  ["en/guide/zeta.md"] = page("Zeta", "xylophone", "order: 3\naudience: maintainer\n"),
  ["en/guide/b.md"] = page("Beta", "betaword", "order: 4\naudience: user\n"),
}

local function with_files(extra)
  local files = {}
  for path, data in pairs(AUDIENCE_FILES) do files[path] = data end
  for path, data in pairs(extra or {}) do files[path] = data end
  return files
end

local ONE_LOCALE = { locales = { { code = "en", label = "English" } }, url = "https://x.test" }
-- A site for the users: unlabelled pages are user pages, and the maintainer pages are not published.
local USER_SITE = { locales = ONE_LOCALE.locales, url = ONE_LOCALE.url, audiences = { "user" }, default_audience = "user" }
-- Both audiences in one combined site.
local MERGED = { locales = ONE_LOCALE.locales, url = ONE_LOCALE.url, audiences = { "user", "maintainer" },
  audience_sites = "merged" }

function T:test_a_page_of_an_unpublished_audience_is_absent_everywhere()
  local fs, report = build(with_files(), USER_SITE)
  self:assert_nil(fs:read("o/en/guide/zeta/index.html"))
  self:assert_equal(4, report.locales.en.pages)
  self:assert_equal(1, report.locales.en.unpublished)
  for _, path in ipairs({ "o/en/guide/a/index.html", "o/en/guide/b/index.html", "o/en/guide/index.html" }) do
    local page_html = fs:read(path)
    self:assert_nil(page_html:find("zeta", 1, true), path)
    self:assert_nil(page_html:find("Zeta", 1, true), path)
  end
  -- Alpha's next page is Beta, not the hidden Zeta.
  self:assert_true(fs:read("o/en/guide/a/index.html"):find('rel="next" href="/en/guide/b/"', 1, true) ~= nil)
  self:assert_true(fs:read("o/en/guide/b/index.html"):find('rel="prev" href="/en/guide/a/"', 1, true) ~= nil)
  local sitemap = fs:read("o/sitemap.xml")
  self:assert_nil(sitemap:find("zeta", 1, true))
  self:assert_true(sitemap:find("/en/guide/a/", 1, true) ~= nil)
  local search_index = fs:read("o/assets/search-en.json")
  self:assert_nil(search_index:find("xylophone", 1, true))
  self:assert_nil(search_index:find("zeta", 1, true))
  self:assert_true(search_index:find("alphaword", 1, true) ~= nil)
end

function T:test_a_link_to_an_unpublished_page_is_reported_like_a_broken_link()
  local _, report = build(with_files(), USER_SITE)
  self:assert_equal(1, #report.problems, table.concat(report.problems, "\n"))
  self:assert_true(report.problems[1]:find("en/index.md", 1, true) ~= nil)
  self:assert_true(report.problems[1]:find("guide/zeta.md", 1, true) ~= nil)
  self:assert_true(report.problems[1]:find("maintainer", 1, true) ~= nil)
  local err = self:assert_error(function() build(with_files(), USER_SITE, { strict = true }) end)
  self:assert_true(core.is_instance_of(err, doc.BuildError))
  self:assert_true(err.message:find("guide/zeta.md", 1, true) ~= nil)
end

function T:test_asking_for_both_audiences_in_a_merged_site_publishes_everything()
  local fs, report = build(with_files(), MERGED, { strict = true })
  self:assert_not_nil(fs:read("o/en/guide/zeta/index.html"))
  self:assert_equal(5, report.locales.en.pages)
  self:assert_equal(0, report.locales.en.unpublished)
  self:assert_true(fs:read("o/sitemap.xml"):find("/en/guide/zeta/", 1, true) ~= nil)
end

function T:test_the_plain_builder_publishes_the_maintainer_audience_and_pages_without_the_key_are_maintainer_pages()
  -- A tree without the key is entirely published: the pages are maintainer documentation.
  local fs, report = build(BASIC)
  self:assert_equal(4, report.locales.en.pages)
  self:assert_not_nil(fs:read("o/en/guide/b/index.html"))
end

function T:test_default_audience_labels_the_pages_without_the_key()
  local files = with_files()
  files["en/index.md"] = page("Home", "welcome", "audience: user\n")
  -- By default an unlabelled page is maintainer documentation and only the maintainer audience is published.
  local fs = build(files, { locales = ONE_LOCALE.locales })
  self:assert_nil(fs:read("o/en/index.html"), "labelled user")
  self:assert_nil(fs:read("o/en/guide/b/index.html"), "labelled user")
  self:assert_not_nil(fs:read("o/en/guide/a/index.html"), "unlabelled, so maintainer")
  self:assert_not_nil(fs:read("o/en/guide/zeta/index.html"))
  -- The other way round.
  local users = build(files, { locales = ONE_LOCALE.locales, audiences = { "user" }, default_audience = "user" })
  self:assert_not_nil(users:read("o/en/index.html"), "labelled user")
  self:assert_not_nil(users:read("o/en/guide/b/index.html"), "labelled user")
  self:assert_not_nil(users:read("o/en/guide/a/index.html"), "unlabelled, so user")
  self:assert_nil(users:read("o/en/guide/zeta/index.html"))
end

function T:test_an_unknown_audience_is_a_build_error_naming_the_file()
  for _, value in ipairs({ "operator", "User", "3", "true", "[user]" }) do
    local err = self:assert_error(function()
      build(with_files({ ["en/guide/a.md"] = page("Alpha", "x", "audience: " .. value .. "\n") }), ONE_LOCALE)
    end)
    self:assert_true(core.is_instance_of(err, doc.BuildError), value)
    self:assert_true(tostring(err):find("guide/a.md", 1, true) ~= nil, tostring(err))
    self:assert_true(tostring(err):find("audience", 1, true) ~= nil, tostring(err))
  end
end

function T:test_an_unpublished_page_is_still_validated()
  local err = self:assert_error(function()
    build(with_files({ ["en/guide/zeta.md"] = "---\ntitle: Z\naudience: nobody\n---\nx\n" }), ONE_LOCALE)
  end)
  self:assert_true(tostring(err):find("guide/zeta.md", 1, true) ~= nil, tostring(err))
end

function T:test_a_translation_does_not_publish_what_its_default_locale_page_hides()
  local files = with_files({ ["fr/guide/zeta.md"] = page("Zeta FR", "x", "audience: user\n") })
  local users = { audiences = { "user" }, default_audience = "user" }
  local fs = build(files, users)
  self:assert_nil(fs:read("o/fr/guide/zeta/index.html"), "the audience of the translation does not override...")
  local files_fr = with_files({ ["fr/guide/zeta.md"] = page("Zeta FR", "x", "audience: maintainer\n") })
  files_fr["en/guide/zeta.md"] = page("Zeta", "x", "order: 3\n")
  local fs2 = build(files_fr, users)
  self:assert_not_nil(fs2:read("o/en/guide/zeta/index.html"))
  self:assert_nil(fs2:read("o/fr/guide/zeta/index.html"), "...and a hidden translation is not replaced by the English page")
end

function T:test_explicit_sidebar_and_home_actions_naming_an_unpublished_page_are_reported()
  local files = with_files({ ["en/index.md"] = page("Home", "x", "layout: home\nactions: [\"Go | guide/zeta\"]\n") })
  local _, report = build(files, { locales = ONE_LOCALE.locales, audiences = { "user" }, default_audience = "user",
    sidebar = { guide = { "guide/a", "guide/zeta" } } })
  local text = table.concat(report.problems, "\n")
  self:assert_true(text:find("zeta", 1, true) ~= nil, text)
  self:assert_true(#report.problems >= 2, text)
end

function T:test_the_theme_file_can_change_fonts_and_ship_font_files_from_public()
  local files = {}
  for path, data in pairs(BASIC) do files[path] = data end
  files["public/own.css"] = '@font-face { font-family: "Own"; src: url("fonts/own.woff2") format("woff2"); }\n'
    .. ":root { --serif: \"Own\", serif; --sans: \"Own\", sans-serif; --mono: \"Own Mono\", monospace; }\n"
  files["public/fonts/own.woff2"] = "wOF2"
  local fs = build(files, { theme = "own.css" })
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

-- llms.txt and llms-full.txt (llmstxt.org): opt-in, the published pages of the default locale.
local LLMS_FILES = {
  ["en/index.md"] = page("Home", "welcome", "description: Start page.\n"),
  ["en/guide/index.md"] = page("Guide", "start", "order: 1\ndescription: Where to begin.\n"),
  ["en/guide/a.md"] = page("Alpha [one]", "alphaword", "order: 2\n"),
  ["en/guide/b.md"] = page("Beta", "betaword", "order: 3\ndescription: \"Second\\nline.\"\n"),
  ["en/guide/zeta.md"] = page("Zeta", "xylophone", "order: 4\naudience: maintainer\ndescription: Hidden.\n"),
  ["en/other/x.md"] = "---\ndescription: An x.\n---\nno heading here\n",
  ["fr/index.md"] = page("Accueil", "bonjour"),
  ["fr/guide/a.md"] = page("Alpha FR", "frenchword"),
}

function T:test_llms_files_are_not_written_unless_asked_and_public_files_pass_through()
  local files = {}
  for path, data in pairs(LLMS_FILES) do files[path] = data end
  files["public/llms.txt"] = "hand-written\n"
  local fs = build(files, { url = "https://x.test" })
  self:assert_equal("hand-written\n", fs:read("o/llms.txt"))
  self:assert_nil(fs:read("o/llms-full.txt"))
end

function T:test_llms_txt_lists_the_published_pages_of_the_default_locale_by_section()
  local fs = build(LLMS_FILES, { url = "https://x.test/", llms = true, audiences = { "user" }, default_audience = "user", description = { en = "A site.", fr = "Un site." } })
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
    "",
    "## Other",
    "",
    "- [X](https://x.test/en/other/x/): An x.",
    "",
  }, "\n")
  self:assert_equal(expected, fs:read("o/llms.txt"))
end

function T:test_llms_links_follow_the_base_without_a_public_url()
  local fs = build(LLMS_FILES, { llms = true, audiences = { "user" }, default_audience = "user", base = "/docs/" })
  local text = fs:read("o/llms.txt")
  self:assert_not_nil(text:find("- [Home](/docs/en/): Start page.", 1, true), text)
  self:assert_nil(text:find("> ", 1, true), "no summary without a description")
end

function T:test_llms_full_txt_concatenates_the_markdown_of_the_published_pages()
  local fs = build(LLMS_FILES, { url = "https://x.test", llms = true, audiences = { "user" }, default_audience = "user" })
  local text = fs:read("o/llms-full.txt")
  self:assert_not_nil(text:find("alphaword", 1, true))
  self:assert_not_nil(text:find("betaword", 1, true))
  self:assert_not_nil(text:find("Source: https://x.test/en/guide/a/", 1, true))
  self:assert_nil(text:find("xylophone", 1, true), "an unpublished audience is absent")
  self:assert_nil(text:find("frenchword", 1, true), "the default locale only")
  self:assert_nil(text:find("description:", 1, true), "front matter is not part of the Markdown")
  self:assert_true(text:find("alphaword", 1, true) < text:find("betaword", 1, true), "reading order")
  -- A page without a heading in its body gets one from its title.
  self:assert_not_nil(text:find("# X\n\nno heading here", 1, true), text)
  self:assert_equal("\n", text:sub(-1))
  self:assert_nil(text:find("\n\n\n", 1, true))
end

function T:test_llms_files_are_deterministic_and_ask_for_the_published_audiences()
  local first = build(LLMS_FILES, { url = "https://x.test", llms = true, audiences = { "user" }, default_audience = "user" })
  local second = build(LLMS_FILES, { url = "https://x.test", llms = true, audiences = { "user" }, default_audience = "user" })
  self:assert_equal(first:read("o/llms.txt"), second:read("o/llms.txt"))
  self:assert_equal(first:read("o/llms-full.txt"), second:read("o/llms-full.txt"))
  local both = build(LLMS_FILES, { url = "https://x.test", llms = true, audiences = { "user", "maintainer" },
    audience_sites = "merged" })
  self:assert_not_nil(both:read("o/llms.txt"):find("[Zeta](https://x.test/en/guide/zeta/): Hidden.", 1, true))
  self:assert_not_nil(both:read("o/llms-full.txt"):find("xylophone", 1, true))
end

function T:test_a_file_of_public_named_like_a_llms_file_collides_when_llms_is_on()
  local files = {}
  for path, data in pairs(LLMS_FILES) do files[path] = data end
  files["public/llms-full.txt"] = "mine"
  local err = self:assert_error(function() build(files, { llms = true }) end)
  self:assert_true(core.is_instance_of(err, doc.BuildError))
  self:assert_not_nil(tostring(err):find("llms-full.txt", 1, true), tostring(err))
end

-- Separate sites (OQ-144, owner decision of 2026-11-18): one complete site per audience.
local SEPARATE_FILES = {
  ["en/index.md"] = page("Home", "welcome", "audience: user\n"),
  ["en/guide/index.md"] = page("Guide", "start", "order: 1\naudience: user\n"),
  ["en/guide/a.md"] = page("Alpha", "alphaword [to the maintainers](../internals/design.md)", "order: 2\naudience: user\n"),
  ["en/guide/img.md"] = page("Pictures", "![x](pic.svg)", "order: 3\naudience: user\n"),
  ["en/guide/pic.svg"] = "<svg/>",
  ["en/internals/index.md"] = page("Internals", "inside", "order: 5\n"),
  ["en/internals/design.md"] = page("Design", "xylophone", "order: 6\n"),
  ["public/logo.svg"] = "<svg/>",
}
local SEPARATE = { locales = ONE_LOCALE.locales, url = "https://x.test", audiences = { "user", "maintainer" }, llms = true }

function T:test_several_audiences_are_written_as_one_complete_site_each()
  local fs, report = build(SEPARATE_FILES, SEPARATE)
  for _, audience in ipairs({ "user", "maintainer" }) do
    for _, file in ipairs({ "404.html", "index.html", "sitemap.xml", "llms.txt", "llms-full.txt",
      "assets/theme.css", "assets/theme.js", "assets/search-en.json", ".hecate-doc-output", "logo.svg" }) do
      self:assert_not_nil(fs:read("o/" .. audience .. "/" .. file), audience .. "/" .. file)
    end
  end
  -- Own pages, and only those.
  self:assert_not_nil(fs:read("o/user/en/index.html"))
  self:assert_not_nil(fs:read("o/maintainer/en/internals/index.html"))
  self:assert_not_nil(fs:read("o/user/en/guide/a/index.html"))
  self:assert_nil(fs:read("o/user/en/internals/design/index.html"))
  self:assert_not_nil(fs:read("o/maintainer/en/internals/design/index.html"))
  self:assert_nil(fs:read("o/maintainer/en/guide/a/index.html"))
  self:assert_equal("<svg/>", fs:read("o/user/en/guide/pic.svg"))
  -- Own search index, sitemap, llms.txt, navigation: nothing of the other audience.
  self:assert_nil(fs:read("o/user/assets/search-en.json"):find("xylophone", 1, true))
  self:assert_not_nil(fs:read("o/user/assets/search-en.json"):find("alphaword", 1, true))
  self:assert_not_nil(fs:read("o/maintainer/assets/search-en.json"):find("xylophone", 1, true))
  self:assert_nil(fs:read("o/maintainer/assets/search-en.json"):find("alphaword", 1, true))
  self:assert_nil(fs:read("o/user/sitemap.xml"):find("internals", 1, true))
  self:assert_not_nil(fs:read("o/user/sitemap.xml"):find("https://x.test/user/en/guide/a/", 1, true))
  self:assert_not_nil(fs:read("o/maintainer/sitemap.xml"):find("https://x.test/maintainer/en/internals/design/", 1, true))
  self:assert_nil(fs:read("o/user/llms.txt"):find("Design", 1, true))
  self:assert_not_nil(fs:read("o/maintainer/llms.txt"):find("https://x.test/maintainer/en/internals/design/", 1, true))
  self:assert_nil(fs:read("o/maintainer/llms-full.txt"):find("alphaword", 1, true))
  local user_page = fs:read("o/user/en/guide/a/index.html")
  self:assert_nil(user_page:find("/maintainer/", 1, true), "no link into the other site")
  self:assert_not_nil(user_page:find('href="/user/assets/theme.css"', 1, true), "assets of its own site")
  self:assert_not_nil(user_page:find("/user/assets/search-en.json", 1, true))
  -- The root holds the marker and a redirect to the first audience.
  self:assert_not_nil(fs:read("o/.hecate-doc-output"))
  self:assert_not_nil(fs:read("o/index.html"):find('content="0; url=/user/en/"', 1, true))
  self:assert_nil(fs:read("o/en/index.html"))
  self:assert_nil(fs:read("o/assets/theme.css"))
  -- The report lists the sites.
  self:assert_equal(2, #report.sites)
  self:assert_equal("user", report.sites[1].directory)
  self:assert_equal("maintainer", report.sites[2].directory)
  self:assert_equal("user", report.sites[1].audiences[1])
  self:assert_equal(4, report.sites[1].locales.en.pages)
  self:assert_equal(2, report.sites[2].locales.en.pages)
  self:assert_equal(4, report.sites[2].locales.en.unpublished, "the pages of the other audience")
  self:assert_equal(0, report.locales.en.unpublished, "every page is in one of the sites")
  self:assert_equal(6, report.locales.en.pages)
  local count = 2
  for _, entry in ipairs(report.sites) do count = count + entry.files end
  self:assert_equal(count, report.files)
end

function T:test_a_link_to_a_page_of_another_audience_is_a_problem_of_its_own_site_naming_the_audience()
  local _, report = build(SEPARATE_FILES, SEPARATE)
  self:assert_equal(0, #report.sites[2].problems)
  self:assert_equal(1, #report.sites[1].problems, table.concat(report.sites[1].problems, "\n"))
  local problem = report.sites[1].problems[1]
  self:assert_true(problem:find("en/guide/a.md", 1, true) ~= nil, problem)
  self:assert_true(problem:find("internals/design.md", 1, true) ~= nil, problem)
  self:assert_true(problem:find("maintainer", 1, true) ~= nil, problem)
  self:assert_equal(problem, report.problems[1])
  local err = self:assert_error(function() build(SEPARATE_FILES, SEPARATE, { strict = true }) end)
  self:assert_true(core.is_instance_of(err, doc.BuildError))
  self:assert_true(err.message:find("maintainer", 1, true) ~= nil, err.message)
end

function T:test_the_default_publishes_one_maintainer_site_at_the_root()
  local fs, report = build(SEPARATE_FILES, { locales = ONE_LOCALE.locales })
  self:assert_not_nil(fs:read("o/en/internals/design/index.html"), "maintainer pages, and the pages without the key")
  self:assert_nil(fs:read("o/en/guide/a/index.html"), "a user page is not published")
  self:assert_nil(fs:read("o/maintainer/en/index.html"))
  self:assert_equal(1, #report.sites)
  self:assert_equal("", report.sites[1].directory)
  self:assert_equal("maintainer", report.sites[1].audiences[1])
  self:assert_equal(2, report.locales.en.pages)
  self:assert_equal(4, report.locales.en.unpublished)
end

function T:test_a_single_audience_keeps_the_layout_at_the_root_whatever_the_switch()
  for _, mode in ipairs({ "separate", "merged" }) do
    local fs = build(SEPARATE_FILES, { locales = ONE_LOCALE.locales, audiences = { "user" }, audience_sites = mode })
    self:assert_nil(fs:read("o/user/en/index.html"), mode)
    self:assert_nil(fs:read("o/en/internals/design/index.html"), mode)
    self:assert_not_nil(fs:read("o/en/guide/a/index.html"), mode)
  end
end

function T:test_the_merged_switch_writes_both_audiences_in_one_site()
  local fs, report = build(SEPARATE_FILES, { locales = ONE_LOCALE.locales, audiences = { "user", "maintainer" },
    audience_sites = "merged" }, { strict = true })
  self:assert_not_nil(fs:read("o/en/guide/a/index.html"))
  self:assert_not_nil(fs:read("o/en/internals/design/index.html"))
  self:assert_nil(fs:read("o/user/en/index.html"))
  self:assert_equal(1, #report.sites)
  self:assert_equal(2, #report.sites[1].audiences)
  self:assert_equal(6, report.locales.en.pages)
end

function T:test_separate_sites_follow_the_base_and_can_be_cleaned()
  local files = {}
  for path, data in pairs(SEPARATE_FILES) do files["c/" .. path] = data end
  local fs = doc.MemoryFileSystem(files)
  local arguments = { config = config_with({ locales = ONE_LOCALE.locales, base = "/docs/", audiences = { "maintainer", "user" } }),
    source = "c", out = "o", fs = fs, clean = true }
  doc.build(arguments)
  self:assert_not_nil(fs:read("o/index.html"):find('url=/docs/maintainer/en/', 1, true), "the first audience listed")
  self:assert_not_nil(fs:read("o/user/en/guide/a/index.html"):find('href="/docs/user/assets/theme.css"', 1, true))
  fs:write("o/stale.txt", "old")
  fs:write("o/user/stale.txt", "old")
  doc.build(arguments)
  self:assert_nil(fs:read("o/stale.txt"), "the output directory was cleaned (the marker is at its root)")
  self:assert_nil(fs:read("o/user/stale.txt"))
  self:assert_not_nil(fs:read("o/user/en/index.html"))
  local foreign = doc.MemoryFileSystem(files)
  foreign:write("o/mine.txt", "mine")
  arguments.fs = foreign
  self:assert_error(function() doc.build(arguments) end)
  self:assert_equal("mine", foreign:read("o/mine.txt"))
end

function T:test_a_failing_separate_build_writes_nothing()
  local files = {}
  for path, data in pairs(SEPARATE_FILES) do files["c/" .. path] = data end
  files["c/en/internals/bad.md"] = "---\ntitle: Bad\naudience: nobody\n---\nx\n"
  local fs = doc.MemoryFileSystem(files)
  self:assert_error(function()
    doc.build({ config = config_with({ locales = ONE_LOCALE.locales, audiences = { "user", "maintainer" } }),
      source = "c", out = "o", fs = fs })
  end)
  self:assert_nil(fs:read("o/index.html"))
  self:assert_nil(fs:read("o/user/en/index.html"))
end

return T
