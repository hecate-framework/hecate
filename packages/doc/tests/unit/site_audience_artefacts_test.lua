---@diagnostic disable: need-check-nil  -- tests read files they have just built; a nil fails the assertion that follows
-- What surrounds a page of an audience that a site does not publish (OQ-144): the images next to it, its translation, its
-- section, the 404 page, the text of `llms-full.txt`, the search index, and the Mermaid library that only a page with a
-- diagram needs. Each separate site is complete for its audience and holds nothing of the other.
local test = require("harness.test")
local doc = require("hecate.doc")
local T = test.Case("SiteAudienceArtefactsTest")

local function page(title, body, extra)
  return ("---\ntitle: %s\n%s---\n%s\n"):format(title, extra or "", body or "text")
end

local DIAGRAM = "```mermaid\ngraph TD\n  A --> B\n```\n"
local LOCALES = { { code = "en", label = "English" }, { code = "fr", label = "Fran\u{E7}ais" } }

local function config(extra)
  local out = { title = "T", locales = LOCALES, site_origin = "https://x.test", generate_llms_txt = true,
    audiences = { "user", "maintainer" }, audience_sites = "separate", default_audience = "user" }
  for key, value in pairs(extra or {}) do out[key] = value end
  return out
end

local function build(files, extra)
  local prefixed = {}
  for path, data in pairs(files) do prefixed["c/" .. path] = data end
  local fs = doc.MemoryFileSystem(prefixed)
  local report = doc.build({ site_configuration = config(extra), guides_dir = "c", output_dir = "o", file_system = fs })
  return fs, report
end

local function contains(text, needle) return text:find(needle, 1, true) ~= nil end

-- The tree: a user guide, a maintainer section (`internals`) with its images, a translation labelled for the other audience.
local function tree(extra)
  local files = {
    ["en/index.md"] = page("Home", "welcome ![logo](img/shared.png)"),
    ["en/guide/index.md"] = page("Guide", "start", "order: 1\n"),
    ["en/guide/a.md"] = page("Alpha", "alphaword ![chart](chart.png)", "order: 2\n"),
    ["en/guide/b.md"] = page("Beta", "betaword", "order: 3\n"),
    ["en/internals/index.md"] = page("Internals", "internalsword", "audience: maintainer\n"),
    ["en/internals/design.md"] = page("Hidden Design", "designword ![diagram](secret.png) ![x](design.png)", "audience: maintainer\n"),
    ["en/internals/design.png"] = "DESIGN-PNG",
    ["en/internals/secret.png"] = "SECRET-PNG",
    ["en/guide/chart.png"] = "CHART-PNG",
    ["en/img/shared.png"] = "SHARED-PNG",
    ["fr/index.md"] = page("Accueil", "bienvenue"),
    ["fr/guide/a.md"] = page("Alpha fr", "alphamot"),
    ["fr/guide/b.md"] = page("Beta fr", "betamot", "audience: maintainer\n"),
    ["fr/internals/design.md"] = page("Conception cachee", "conceptionmot", "audience: maintainer\n"),
    ["fr/internals/plan.png"] = "PLAN-PNG",
    ["en/maintainer-home.md"] = page("Maintainer home", "mh", "audience: maintainer\n"),
  }
  for path, data in pairs(extra or {}) do files[path] = data end
  return files
end

local function anywhere(fs, directory, needle)
  for path, data in pairs(fs.files) do
    if path:sub(1, #directory) == directory and (contains(data, needle) or contains(path, needle)) then return path end
  end
  return nil
end

function T:test_the_images_of_a_site_are_in_the_site_that_publishes_the_pages_that_use_them()
  local fs = build(tree())
  -- The maintainer site is the one that has the pages of `internals/`: it holds their images.
  self:assert_equal("SECRET-PNG", fs:read("o/maintainer/en/internals/secret.png"))
  self:assert_equal("DESIGN-PNG", fs:read("o/maintainer/en/internals/design.png"))
  -- The user images stay where they are used, and the pages of the user site link to them in their own site.
  self:assert_equal("CHART-PNG", fs:read("o/user/en/guide/chart.png"))
  self:assert_equal("SHARED-PNG", fs:read("o/user/en/img/shared.png"))
  self:assert_true(contains(fs:read("o/user/en/guide/a/index.html"), 'src="/user/en/guide/chart.png"'))
  self:assert_true(contains(fs:read("o/maintainer/en/internals/design/index.html"), 'src="/maintainer/en/internals/secret.png"'))
  -- Not asserted here, because it does not hold (see the report of this test): `en/internals/secret.png`, an image next to
  -- pages that no user can read, is copied into the user site too (assets carry no audience).
end

function T:test_a_hidden_translation_is_not_in_the_locale_switcher_nor_in_the_alternates()
  local fs = build(tree())
  local english = fs:read("o/user/en/guide/b/index.html")
  -- The French page of Beta is for the maintainers: the switcher leads to the French home, and no alternate names it.
  self:assert_nil(fs:read("o/user/fr/guide/b/index.html"))
  self:assert_nil(english:find("/user/fr/guide/b/", 1, true), "no link to the hidden translation")
  self:assert_true(contains(english, 'href="/user/fr/" lang="fr" hreflang="fr"'), "the switcher leads to the French home")
  self:assert_nil(english:find('<link rel="alternate" hreflang="fr"', 1, true), "no alternate for a hidden translation")
  -- A translation that is published still has both.
  local alpha = fs:read("o/user/en/guide/a/index.html")
  self:assert_true(contains(alpha, 'href="/user/fr/guide/a/" lang="fr" hreflang="fr"'))
  self:assert_true(contains(alpha, '<link rel="alternate" hreflang="fr" href="https://x.test/user/fr/guide/a/">'))
  -- A translation never publishes what its original keeps back, and the original of this one is a user page: the page is in
  -- no site at all, and the maintainer site neither has the English page nor links to it.
  self:assert_nil(fs:read("o/maintainer/fr/guide/b/index.html"))
  self:assert_nil(fs:read("o/maintainer/en/guide/b/index.html"))
  local sitemap = fs:read("o/user/sitemap.xml")
  self:assert_nil(sitemap:find("/guide/b/", 1, true) and sitemap:find("/fr/guide/b/", 1, true), "the sitemap of the user site has no hidden translation")
  self:assert_nil(fs:read("o/user/llms.txt"):find("Beta fr", 1, true))
end

function T:test_a_section_whose_pages_are_all_hidden_has_no_link_and_no_group_in_the_site()
  local fs = build(tree())
  for _, path in ipairs({ "o/user/en/index.html", "o/user/en/guide/a/index.html", "o/user/en/guide/index.html", "o/user/fr/index.html", "o/user/404.html" }) do
    local html = fs:read(path)
    self:assert_not_nil(html, path)
    self:assert_nil(html:find("/user/en/internals/", 1, true), path .. ": no link to the hidden section")
    self:assert_nil(html:find("Internals", 1, true), path .. ": no top link, no sidebar group")
    self:assert_nil(html:find("Hidden Design", 1, true), path)
  end
  -- The top link of the visible section is there, and it is the only one.
  local home = fs:read("o/user/en/index.html")
  self:assert_true(contains(home, 'href="/user/en/guide/"'))
  -- The other site has the section and not the guide.
  local maintainer = fs:read("o/maintainer/en/internals/index.html")
  self:assert_true(contains(maintainer, "Internals"))
  self:assert_nil(maintainer:find("/maintainer/en/guide/", 1, true))
  -- An explicit configuration of the navigation that names the hidden section does not bring it back.
  local explicit = build(tree(), { top_links = { { text = "Guide", link = "guide" }, { text = "Internals", link = "internals" } },
    sidebar = { guide = { "guide/a", "guide/b" } } })
  local explicit_home = explicit:read("o/user/en/index.html")
  self:assert_nil(explicit_home:find("/internals/", 1, true), "an explicit top link to a hidden section is dropped")
  self:assert_nil(explicit_home:find("Internals", 1, true))
end

function T:test_the_not_found_page_holds_nothing_of_the_other_audience()
  local fs = build(tree())
  local user_404 = fs:read("o/user/404.html")
  for _, needle in ipairs({ "internals", "Internals", "Hidden Design", "designword", "maintainer", "Maintainer home" }) do
    self:assert_nil(user_404:find(needle, 1, true), "user 404: " .. needle)
  end
  self:assert_true(contains(user_404, 'href="/user/en/guide/"'), "its own navigation")
  local maintainer_404 = fs:read("o/maintainer/404.html")
  for _, needle in ipairs({ "Alpha", "alphaword", "/user/" }) do
    self:assert_nil(maintainer_404:find(needle, 1, true), "maintainer 404: " .. needle)
  end
  self:assert_true(contains(maintainer_404, "/maintainer/en/internals/"))
end

function T:test_llms_full_txt_and_the_search_index_of_a_site_hold_neither_the_ids_nor_the_titles_nor_the_text_of_hidden_pages()
  local fs = build(tree())
  local full = fs:read("o/user/llms-full.txt")
  local short = fs:read("o/user/llms.txt")
  local search = fs:read("o/user/assets/search-en.json") .. fs:read("o/user/assets/search-fr.json")
  for _, needle in ipairs({ "internals", "Internals", "Hidden Design", "designword", "internalsword", "Maintainer home", "maintainer-home",
    "Beta fr", "betamot", "Conception", "conceptionmot" }) do
    self:assert_nil(full:find(needle, 1, true), "llms-full.txt: " .. needle)
    self:assert_nil(short:find(needle, 1, true), "llms.txt: " .. needle)
    self:assert_nil(search:find(needle, 1, true), "search index: " .. needle)
  end
  self:assert_true(contains(full, "alphaword") and contains(full, "https://x.test/user/en/guide/a/"))
  self:assert_true(contains(search, "Alpha"))
  -- The reverse, in the maintainer site.
  local maintainer_full = fs:read("o/maintainer/llms-full.txt")
  local maintainer_search = fs:read("o/maintainer/assets/search-en.json")
  for _, needle in ipairs({ "Alpha", "alphaword", "Beta", "betaword", "/user/", "welcome" }) do
    self:assert_nil(maintainer_full:find(needle, 1, true), "maintainer llms-full.txt: " .. needle)
    self:assert_nil(maintainer_search:find(needle, 1, true), "maintainer search index: " .. needle)
  end
  self:assert_true(contains(maintainer_full, "designword"))
end

local function has_mermaid(fs, prefix)
  return fs:read(prefix .. "assets/mermaid/mermaid.min.js") ~= nil, fs:read(prefix .. "assets/mermaid-init.js") ~= nil
end

function T:test_the_diagram_library_is_written_only_by_the_site_that_has_a_diagram()
  -- A diagram on a user page: the user site has the library and loads it on that page only; the maintainer site has neither.
  local fs = build(tree({ ["en/guide/a.md"] = page("Alpha", "alphaword\n\n" .. DIAGRAM, "order: 2\n") }))
  local library, init = has_mermaid(fs, "o/user/")
  self:assert_true(library and init, "the site with a diagram has the library and its initialiser")
  self:assert_true(contains(fs:read("o/user/en/guide/a/index.html"), "/user/assets/mermaid/mermaid.min.js"))
  self:assert_true(contains(fs:read("o/user/en/guide/a/index.html"), "/user/assets/mermaid-init.js"))
  self:assert_nil(fs:read("o/user/en/guide/b/index.html"):find("mermaid", 1, true), "a page without a diagram loads nothing")
  self:assert_nil(fs:read("o/user/404.html"):find("mermaid", 1, true), "the 404 page loads nothing")
  library, init = has_mermaid(fs, "o/maintainer/")
  self:assert_false(library, "the site without a diagram has no library")
  self:assert_false(init, "nor its initialiser")
  self:assert_nil(anywhere(fs, "o/maintainer/", "mermaid"), "and no page of it mentions mermaid")
  library, init = has_mermaid(fs, "o/")
  self:assert_false(library or init, "the root of the output has none")
  self:assert_nil(fs:read("o/assets/mermaid-init.js"))
end

function T:test_a_diagram_only_on_a_hidden_page_brings_the_library_to_the_site_of_that_audience_only()
  local fs = build(tree({ ["en/internals/design.md"] = page("Hidden Design", "designword\n\n" .. DIAGRAM, "audience: maintainer\n") }))
  local library, init = has_mermaid(fs, "o/user/")
  self:assert_false(library, "the user site has no diagram: no library")
  self:assert_false(init)
  self:assert_nil(anywhere(fs, "o/user/", "mermaid"))
  library, init = has_mermaid(fs, "o/maintainer/")
  self:assert_true(library and init, "the maintainer site has the page with the diagram")
  -- Single site, one audience: the diagram of a page that is not published does not ship the library either.
  local user_only = build(tree({ ["en/internals/design.md"] = page("Hidden Design", "designword\n\n" .. DIAGRAM, "audience: maintainer\n") }),
    { audiences = { "user" } })
  library, init = has_mermaid(user_only, "o/")
  self:assert_false(library or init, "a site that does not publish the page with the diagram")
  self:assert_nil(anywhere(user_only, "o/", "mermaid"))
  -- And both audiences in one merged site: the library is there.
  local merged = build(tree({ ["en/internals/design.md"] = page("Hidden Design", "designword\n\n" .. DIAGRAM, "audience: maintainer\n") }),
    { audience_sites = "merged" })
  library, init = has_mermaid(merged, "o/")
  self:assert_true(library and init)
end

function T:test_a_diagram_in_a_translation_is_enough_for_its_site()
  local fs = build(tree({ ["fr/guide/a.md"] = page("Alpha fr", "alphamot\n\n" .. DIAGRAM) }))
  local library, init = has_mermaid(fs, "o/user/")
  self:assert_true(library and init)
  self:assert_true(contains(fs:read("o/user/fr/guide/a/index.html"), "mermaid-init.js"))
  self:assert_nil(fs:read("o/user/en/guide/a/index.html"):find("mermaid", 1, true))
end

return T
