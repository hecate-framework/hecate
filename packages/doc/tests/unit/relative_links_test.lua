---@diagnostic disable: need-check-nil  -- tests read files they have just built; a nil fails the assertion that follows
-- OQ-148: a built site is static files that open from the file system (file://) and from any static host. Every local `href`,
-- `src` and `url(...)` of every page and stylesheet is a path relative to the file that holds it and leads to a file of the
-- output; no root-relative reference is left, whatever `base_path` and `site_origin` say. The search index is a script.
local test = require("harness.test")
local doc = require("hecate.doc")
local reactor = require("hecate.reactor")
local T = test.Case("RelativeLinksTest")

local here = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
local package_dir = here:match("^(.*)/tests/unit/")
local links = dofile(package_dir .. "/tests/links.lua")

local LOCALES = { { code = "en", label = "English" }, { code = "fr", label = "Fran\u{E7}ais" } }

local function page(title, body, extra)
  return ("---\ntitle: %s\n%s---\n%s\n"):format(title, extra or "", body or "text")
end

-- A site with the references of every kind: pages at three depths, a translation with fallbacks, files next to the pages, a
-- diagram, links written as relative, root-relative and with fragments, names that need percent-encoding, and the files of
-- `public/` named by the configuration (logo pair, favicon pair, override stylesheet that loads a font of its own).
local FILES = {
  ["en/index.md"] = page("Home", "[guide](guide/) [a](guide/a.md#first) [root](/en/guide/b/) [site](/) ![d](img/d.svg) ![s](img/my%20pic.svg)\n\n"
    .. "[odd](a%20b/caf\u{e9}.md#frag)", "layout: home\ndescription: Tagline\nactions: [\"Go | guide/ | primary\", \"Odd | a b/caf\u{e9} \"]\n"),
  ["en/guide/index.md"] = page("Guide", "start [up](../index.md) [deep](deep/er/x.md)", "order: 1\n"),
  ["en/guide/a.md"] = page("Alpha", "## First\n\ntext\n\n```mermaid\ngraph TD\n  A --> B\n```\n", "order: 2\n"),
  ["en/guide/b.md"] = page("Beta", "b ![d](../img/d.svg)", "order: 3\n"),
  ["en/guide/deep/er/x.md"] = page("Deep", "x [home](../../../index.md)"),
  ["en/a b/caf\u{e9}.md"] = page("Cafe", "c [back](../index.md)"),
  ["en/img/d.svg"] = "<svg/>",
  ["en/img/my pic.svg"] = "<svg/>",
  ["fr/index.md"] = page("Accueil", "bonjour [guide](guide/) ![d](img/d.svg)", "layout: home\n"),
  ["fr/guide/a.md"] = page("Alpha fr", "alpha"),
  ["public/my logo.svg"] = "<svg/>", ["public/my logo dark.svg"] = "<svg/>",
  ["public/icon.png"] = "png", ["public/icon-dark.ico"] = "ico",
  ["public/override.css"] = '@font-face { font-family: "Own"; src: url("fonts/own.woff2") format("woff2"), url(fonts/own.woff); }\n'
    .. 'a { background: url(\'data:image/svg+xml;utf8,<svg/>\'); }\n',
  ["public/fonts/own.woff2"] = "wOF2", ["public/fonts/own.woff"] = "wOFF",
}

local function build(extra)
  local prefixed = {}
  for path, data in pairs(FILES) do prefixed["c/" .. path] = data end
  local fs = doc.MemoryFileSystem(prefixed)
  local configuration = {
    title = "hecate", locales = LOCALES,
    logo_path = { light = "my logo.svg", dark = "my logo dark.svg" },
    favicon_path = { light = "icon.png", dark = "icon-dark.ico" },
    stylesheet_path = "override.css",
  }
  for key, value in pairs(extra or {}) do configuration[key] = value end
  local report = doc.build({ site_configuration = configuration, guides_dir = "c", output_dir = "o", file_system = fs })
  return fs, report
end

local function assert_resolves(self, files, what)
  local problems, checked = links.check(files)
  self:assert_equal(0, #problems, what .. ":\n" .. table.concat(problems, "\n"))
  self:assert_true(checked > 100, what .. ": only " .. checked .. " references were checked")
end

function T:test_every_local_reference_of_a_built_site_leads_to_a_file_relative_to_the_page_that_holds_it()
  local fs, report = build()
  self:assert_equal(0, #report.problems, table.concat(report.problems, "\n"))
  assert_resolves(self, links.files_below(fs, "o/"), "default configuration")
end

function T:test_the_base_path_and_the_origin_change_no_link_of_a_page()
  local plain = links.files_below((build()), "o/")
  for _, extra in ipairs({
    { base_path = "/" },
    { base_path = "/docs/" },
    { base_path = "/a/b/c" },
    { base_path = "/docs/", site_origin = "https://x.test" },
    { site_origin = "https://x.test/" },
  }) do
    local files = links.files_below((build(extra)), "o/")
    local name = "base_path " .. tostring(extra.base_path) .. ", origin " .. tostring(extra.site_origin)
    assert_resolves(self, files, name)
    for path, data in pairs(plain) do
      -- Same pages, same links: the pages differ only in the canonical and alternate addresses that the origin adds, and in
      -- the not-found page, which holds absolute addresses with an origin (a host serves it for any address).
      if path:find("%.html$") and path ~= "404.html" and not extra.site_origin then
        self:assert_equal(data, files[path], name .. ": " .. path)
      end
    end
  end
end

function T:test_the_not_found_page_is_relative_to_the_root_without_an_origin_and_absolute_with_one()
  local without = build({ base_path = "/docs/" }):read("o/404.html")
  self:assert_not_nil(without:find('href="assets/theme.css"', 1, true))
  self:assert_not_nil(without:find('href="en/index.html"', 1, true))
  local with = build({ base_path = "/docs/", site_origin = "https://x.test" }):read("o/404.html")
  self:assert_not_nil(with:find('href="https://x.test/docs/assets/theme.css"', 1, true))
  self:assert_not_nil(with:find('href="https://x.test/docs/en/index.html"', 1, true))
  self:assert_not_nil(with:find('src="https://x.test/docs/my%20logo.svg"', 1, true))
  self:assert_not_nil(with:find('"root":"https://x.test/docs/"', 1, true))
  self:assert_nil(with:find('href="/', 1, true))
end

function T:test_no_page_holds_a_root_relative_local_reference()
  for _, extra in ipairs({ {}, { base_path = "/docs/" }, { base_path = "/docs/", site_origin = "https://x.test" } }) do
    local fs = build(extra)
    for path, data in pairs(links.files_below(fs, "o/")) do
      if path:find("%.html$") then
        self:assert_nil(data:find('href="/', 1, true), path .. ": href=\"/")
        self:assert_nil(data:find('src="/', 1, true), path .. ": src=\"/")
        self:assert_nil(data:find('url=/', 1, true), path .. ": url=/")
        self:assert_nil(data:find('"root":"/', 1, true), path .. ": root")
      end
    end
  end
end

function T:test_a_link_to_a_page_names_its_index_file_because_a_file_system_lists_a_directory()
  local fs = build()
  local home = fs:read("o/en/index.html")
  self:assert_not_nil(home:find('href="guide/index.html"', 1, true))
  self:assert_not_nil(home:find('href="guide/a/index.html#first"', 1, true))
  self:assert_not_nil(home:find('href="guide/b/index.html"', 1, true), "a root-relative link to a page")
  self:assert_not_nil(home:find('href="index.html"', 1, true), "a root-relative link to the site root is the root page of the locale")
  self:assert_nil(home:find('href="guide/"', 1, true))
  local deep = fs:read("o/en/guide/deep/er/x/index.html")
  self:assert_not_nil(deep:find('href="../../../../index.html"', 1, true), "four levels below the locale directory")
  self:assert_not_nil(deep:find('href="../../../../../assets/theme.css"', 1, true))
  self:assert_not_nil(fs:read("o/en/a b/café/index.html"):find('href="../../index.html"', 1, true))
end

function T:test_the_search_index_is_a_script_loaded_by_a_relative_path_and_registered_for_its_locale()
  local fs = build()
  for _, code in ipairs({ "en", "fr" }) do
    local text = fs:read("o/assets/search-" .. code .. ".js")
    self:assert_not_nil(text, code)
    self:assert_nil(fs:read("o/assets/search-" .. code .. ".json"), "no JSON file: a browser refuses to fetch it from file://")
    self:assert_not_nil(text:find("(window.hecateDocSearchIndex = window.hecateDocSearchIndex || {})[\"" .. code .. "\"] = {", 1, true), text:sub(1, 120))
    self:assert_equal(";\n", text:sub(-2))
    self:assert_not_nil(text:find('"u":"' .. code .. '/', 1, true), "a document is addressed from the root of the site")
    self:assert_nil(text:find('"u":"/', 1, true))
  end
  local html = fs:read("o/en/guide/a/index.html")
  self:assert_not_nil(html:find('"index":"../../../assets/search-en.js"', 1, true))
  self:assert_not_nil(html:find('"root":"../../../"', 1, true))
  local script = fs:read("o/assets/theme.js")
  self:assert_nil(script:find("fetch(", 1, true), "the theme loads the index as a script")
  self:assert_not_nil(script:find("hecateDocSearchIndex", 1, true))
  self:assert_not_nil(script:find("config.root", 1, true), "a result is prefixed with the path to the root of the site")
end

function T:test_the_search_index_script_is_deterministic()
  local first, second = build(), build()
  self:assert_equal(first:read("o/assets/search-en.js"), second:read("o/assets/search-en.js"))
end

function T:test_the_stylesheets_load_their_fonts_and_images_by_relative_paths()
  local fs = build()
  local css = fs:read("o/assets/theme.css")
  self:assert_not_nil(css:find('url("fonts/fira-sans-latin-400-normal.woff2")', 1, true))
  self:assert_nil(css:find('url("/', 1, true))
  self:assert_not_nil(fs:read("o/fonts/own.woff2"))
  local _, checked = links.check(links.files_below(fs, "o/"))
  self:assert_true(checked > 0)
end

-- A check that sees nothing proves nothing: the checker finds each kind of mistake it is meant to.
function T:test_the_checker_reports_a_missing_file_a_root_relative_reference_and_a_reference_out_of_the_output()
  local problems = links.check({
    ["en/index.html"] = '<a href="../fr/index.html">x</a><a href="/en/">y</a><img src="missing.png"><link href="../../x.css">'
      .. '<a href="#here">z</a><a href="https://x.test/">w</a><a href="mailto:a@b.test">m</a>',
    ["fr/index.html"] = "<p>&lt;a href=\"/code\"&gt;</p><meta http-equiv=\"refresh\" content=\"0; url=gone/index.html\">",
    ["style.css"] = 'a { background: url("nowhere.svg"); } b { background: url(data:image/png;base64,AA) }',
  })
  local text = table.concat(problems, "\n")
  self:assert_equal(5, #problems, text)
  self:assert_not_nil(text:find('root-relative a href "/en/"', 1, true), text)
  self:assert_not_nil(text:find("no file of the output", 1, true), text)
  self:assert_not_nil(text:find("climbs above the root", 1, true), text)
  self:assert_not_nil(text:find("meta refresh", 1, true), text)
  self:assert_not_nil(text:find("css url", 1, true), text)
end

-- The fixture site of the package: two locales, fallbacks, a sitemap, files, reference pages and a diagram.
local function build_fixture()
  local source = package_dir .. "/tests/fixtures/site"
  local system = doc.SystemFileSystem()
  local memory = doc.MemoryFileSystem()
  local function copy(directory, relative)
    for _, entry in ipairs(system:list(directory) or {}) do
      local path, child = directory .. "/" .. entry.name, relative .. "/" .. entry.name
      if entry.is_directory then copy(path, child) else memory:write("c" .. child, assert(system:read(path))) end
    end
  end
  copy(source, "")
  doc.build({ site_configuration = doc.load_site_configuration(memory, "c/site.lua"), guides_dir = "c", output_dir = "o", file_system = memory })
  return memory
end

function T:test_every_local_reference_of_the_fixture_site_leads_to_a_file()
  local memory = reactor.run(build_fixture)
  local problems, checked = links.check(links.files_below(memory, "o/"))
  self:assert_equal(0, #problems, table.concat(problems, "\n"))
  self:assert_true(checked > 200, "references checked: " .. checked)
end

-- A project build writes one site per audience below one output directory and a redirect at its root.
function T:test_the_sites_of_a_project_and_its_root_redirect_resolve()
  local fs = doc.MemoryFileSystem({
    ["docs/user/en/index.md"] = "# Shop\n\n[guide](guide.md)\n",
    ["docs/user/en/guide.md"] = "# Guide\n\nx\n",
    ["docs/maintainer/en/index.md"] = "# Shop, inside\n\nwelcome\n",
  })
  doc.generate_project_documentation({
    site_configuration = { title = "Shop", base_path = "/shop/", site_origin = "https://x.test" },
    guides_dir = "docs", output_dir = "dist", file_system = fs, audiences = { "user", "maintainer" },
  })
  local files = links.files_below(fs, "dist/")
  self:assert_not_nil(files["index.html"])
  local problems, checked = links.check(files)
  self:assert_equal(0, #problems, table.concat(problems, "\n"))
  self:assert_true(checked > 20, tostring(checked))
  self:assert_not_nil(files["index.html"]:find("url=user/en/index.html", 1, true))
  self:assert_not_nil(files["index.html"]:find('<link rel="canonical" href="https://x.test/shop/user/en/">', 1, true))
end

return T
