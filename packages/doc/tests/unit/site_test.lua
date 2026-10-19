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

function T:test_generated_pages_have_no_edit_link()
  local fs = build({
    ["en/index.md"] = page("Home"),
    ["en/gen.md"] = page("Gen", "## S", "generated: true\n"),
  }, {
    locales = { { code = "en", label = "English" } },
    edit_link = "https://git.test/edit/main/website/{path}",
  })
  self:assert_nil(fs:read("o/en/gen/index.html"):find('class="edit-link"', 1, true))
  self:assert_true(fs:read("o/en/index.html"):find('class="edit-link"', 1, true) ~= nil)
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

return T
