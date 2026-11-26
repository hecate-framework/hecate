---@diagnostic disable: need-check-nil  -- tests read files they have just built; a nil fails the assertion that follows
-- Details of the theme in the generated pages, checked on each of the three layouts (a documentation page, the home page and
-- the 404 page) and not on one of them: the marker of the sidebar, the favicons, the order of the stylesheets. And the
-- wrapper of the tables of the Markdown renderer in the places a table can be in.
local test = require("harness.test")
local doc = require("hecate.doc")
local markdown = require("hecate.doc.markdown")
local T = test.Case("ThemeDetailsTest")

local function page(title, body, extra)
  return ("---\ntitle: %s\n%s---\n%s\n"):format(title, extra or "", body or "text")
end

local FILES = {
  ["en/index.md"] = page("Home", "welcome", "layout: home\ndescription: Tagline\n"),
  ["en/guide/index.md"] = page("Guide", "start", "order: 1\n"),
  ["en/guide/a.md"] = page("Alpha", "alpha", "order: 2\n"),
  ["fr/index.md"] = page("Accueil", "bienvenue", "layout: home\n"),
  ["fr/guide/a.md"] = page("Alpha fr", "alpha"),
  ["public/mark.svg"] = "<svg/>", ["public/icon.png"] = "png", ["public/icon-dark.ico"] = "ico",
  ["public/override.css"] = ":root { --moon: #123456; }", ["public/my style.css"] = "a { color: red; }",
}

local LOCALES = { { code = "en", label = "English" }, { code = "fr", label = "Fran\u{E7}ais" } }

local function build(extra)
  local prefixed = {}
  for path, data in pairs(FILES) do prefixed["c/" .. path] = data end
  local fs = doc.MemoryFileSystem(prefixed)
  local configuration = { title = "hecate", locales = LOCALES }
  for key, value in pairs(extra or {}) do configuration[key] = value end
  doc.build({ site_configuration = configuration, guides_dir = "c", output_dir = "o", file_system = fs })
  return fs
end

-- The three layouts, in the default locale and in a translation. `up` is the path from the page to the root of the site
-- (every link of a page is relative to it, OQ-148; the 404 page is at the root).
local function layouts()
  return {
    { name = "home (en)", path = "o/en/index.html", body = "home", up = "../" },
    { name = "home (fr)", path = "o/fr/index.html", body = "home", up = "../" },
    { name = "documentation page (en)", path = "o/en/guide/a/index.html", body = "doc-page", up = "../../../" },
    { name = "documentation page (fr)", path = "o/fr/guide/a/index.html", body = "doc-page", up = "../../../" },
    { name = "section index (en)", path = "o/en/guide/index.html", body = "doc-page", up = "../../" },
    { name = "404", path = "o/404.html", body = "doc-page", up = "" },
  }
end

local function count(text, needle)
  local n, at = 0, 1
  while true do
    local found = text:find(needle, at, true)
    if not found then return n end
    n, at = n + 1, found + #needle
  end
end

function T:test_the_sidebar_marker_is_on_the_body_of_every_layout_when_asked_and_on_none_otherwise()
  local plain, marked = build(), build({ sidebar_marker = true })
  for _, layout in ipairs(layouts()) do
    local without, with = plain:read(layout.path), marked:read(layout.path)
    self:assert_not_nil(without, layout.name)
    self:assert_equal(1, count(without, ("<body class=\"%s\">"):format(layout.body)), layout.name .. ": the body class without the marker")
    self:assert_equal(0, count(without, "sidebar-marker"), layout.name)
    self:assert_equal(1, count(with, ("<body class=\"%s sidebar-marker\">"):format(layout.body)), layout.name .. ": the body class with the marker")
    self:assert_equal(1, count(with, "sidebar-marker"), layout.name .. ": once")
  end
  local off = build({ sidebar_marker = false })
  self:assert_equal(0, count(off:read("o/404.html"), "sidebar-marker"))
end

function T:test_the_default_favicon_is_on_every_layout_once_and_never_follows_the_base_path()
  for _, base in ipairs({ "/", "/docs/" }) do
    local fs = build({ base_path = base })
    for _, layout in ipairs(layouts()) do
      local html = fs:read(layout.path)
      self:assert_equal(1, count(html, '<link rel="icon"'), layout.name .. ": one icon")
      self:assert_equal(1, count(html, ('<link rel="icon" href="%sassets/brand/favicon.svg" type="image/svg+xml">'):format(layout.up)),
        layout.name .. ": the adaptive Hecate icon, relative to the page, whatever the base path " .. base)
    end
  end
end

function T:test_a_favicon_of_public_is_on_every_layout_in_its_form()
  local cases = {
    { configuration = { favicon_path = "mark.svg" }, links = { '<link rel="icon" href="%smark.svg" type="image/svg+xml">' } },
    { configuration = { favicon_path = { light = "icon.png" } }, links = { '<link rel="icon" href="%sicon.png" type="image/png">' } },
    { configuration = { favicon_path = { light = "icon.png", dark = "icon-dark.ico" } },
      links = { '<link rel="icon" href="%sicon.png" type="image/png" media="(prefers-color-scheme: light)">',
        '<link rel="icon" href="%sicon-dark.ico" type="image/x-icon" media="(prefers-color-scheme: dark)">' } },
  }
  for _, case in ipairs(cases) do
    local fs = build(case.configuration)
    for _, layout in ipairs(layouts()) do
      local html = fs:read(layout.path)
      self:assert_equal(#case.links, count(html, '<link rel="icon"'), layout.name)
      for _, link in ipairs(case.links) do
        link = link:format(layout.up)
        self:assert_equal(1, count(html, link), layout.name .. ": " .. link)
      end
      self:assert_equal(0, count(html, "assets/brand/favicon.svg"), layout.name .. ": the default icon is replaced")
    end
  end
  -- A base path changes no link: the file of `public/` is found relative to the page.
  local below = build({ favicon_path = "mark.svg", base_path = "/docs/" })
  for _, layout in ipairs(layouts()) do
    self:assert_equal(1, count(below:read(layout.path), ('<link rel="icon" href="%smark.svg" type="image/svg+xml">'):format(layout.up)),
      layout.name)
  end
end

local function position(html, needle) return (html:find(needle, 1, true)) end

function T:test_the_override_stylesheet_follows_the_theme_stylesheet_on_every_layout_including_the_404_page()
  local fs = build({ stylesheet_path = "override.css" })
  for _, layout in ipairs(layouts()) do
    local html = fs:read(layout.path)
    local theme_link, override_link = ('href="%sassets/theme.css"'):format(layout.up), ('href="%soverride.css"'):format(layout.up)
    self:assert_equal(1, count(html, theme_link), layout.name .. ": the theme once")
    self:assert_equal(1, count(html, override_link), layout.name .. ": the override once")
    self:assert_equal(2, count(html, 'rel="stylesheet"'), layout.name .. ": two stylesheets, no more")
    local theme, override = position(html, theme_link), position(html, override_link)
    self:assert_true(theme < override, layout.name .. ": the override comes after the theme (the cascade)")
    self:assert_true(override < position(html, "<script"), layout.name .. ": both before the first script")
    self:assert_true(override < position(html, "</head>"), layout.name .. ": in the head")
    local adjacent = ('<link rel="stylesheet" %s>\n<link rel="stylesheet" %s>'):format(theme_link, override_link)
    self:assert_equal(adjacent, html:match(adjacent:gsub("%p", "%%%0")), layout.name .. ": adjacent")
  end
  -- Without an override there is the theme alone, on every layout.
  local plain = build()
  for _, layout in ipairs(layouts()) do self:assert_equal(1, count(plain:read(layout.path), 'rel="stylesheet"'), layout.name) end
  -- The name of the file is percent-encoded; the base path changes no link.
  local spaced = build({ stylesheet_path = "my style.css", base_path = "/docs/" })
  for _, layout in ipairs(layouts()) do
    local html = spaced:read(layout.path)
    local own = ('href="%smy%%20style.css"'):format(layout.up)
    self:assert_equal(1, count(html, own), layout.name)
    self:assert_true(position(html, ('href="%sassets/theme.css"'):format(layout.up)) < position(html, own), layout.name)
  end
  -- The override is the file of the project, copied as it is, and the file of the theme is never replaced by it.
  self:assert_equal(":root { --moon: #123456; }", fs:read("o/override.css"))
  self:assert_not_nil(fs:read("o/assets/theme.css"))
  self:assert_true(fs:read("o/assets/theme.css") ~= fs:read("o/override.css"))
end

-- Tables ---------------------------------------------------------------------------------------------------------------

local function wrapped(html) return count(html, '<div class="table-wrap"><table>') end
local function closed(html) return count(html, "</table></div>") end

function T:test_a_table_in_a_quotation_or_a_list_is_wrapped_inside_it()
  local quote = markdown.render("> | a | b |\n> |---|---|\n> | 1 | 2 |\n").html
  self:assert_equal(1, wrapped(quote))
  self:assert_equal(1, closed(quote))
  self:assert_true(quote:find('<blockquote>\n<div class="table%-wrap"><table>') ~= nil, quote)
  self:assert_true(quote:find("</table></div>\n</blockquote>", 1, true) ~= nil, quote)
  local list = markdown.render("- item\n\n  | a | b |\n  |---|---|\n  | 1 | 2 |\n\n- other\n").html
  self:assert_equal(1, wrapped(list))
  self:assert_equal(1, closed(list))
  self:assert_true(list:find('<li>\n<p>item</p>\n<div class="table%-wrap">') ~= nil, list)
  local nested = markdown.render("> - item\n>\n>   | a |\n>   |---|\n>   | 1 |\n").html
  self:assert_equal(1, wrapped(nested))
  self:assert_equal(1, closed(nested))
end

function T:test_two_tables_are_two_wrappers_each_closed_after_its_own_table()
  local html = markdown.render("| a |\n|---|\n| 1 |\n\ntext between\n\n| b |\n|---|\n| 2 |\n").html
  self:assert_equal(2, wrapped(html))
  self:assert_equal(2, closed(html))
  self:assert_equal(2, count(html, "<table>"))
  self:assert_equal(2, count(html, "</table>"))
  local first_end, second_start = html:find("</table></div>", 1, true), html:find('<div class="table-wrap"><table>', 2, true)
  self:assert_true(first_end < html:find("text between", 1, true) and html:find("text between", 1, true) < second_start,
    "the text lies between the wrappers")
  -- Two tables one after the other, separated by a heading.
  local adjacent = markdown.render("| a |\n|---|\n| 1 |\n\n## h\n\n| b |\n|---|\n| 2 |\n").html
  self:assert_equal(2, wrapped(adjacent))
  self:assert_equal(2, closed(adjacent))
end

function T:test_a_table_in_a_code_fence_is_not_wrapped_and_text_that_looks_like_a_table_tag_is_escaped_text()
  local fenced = markdown.render("```html\n<table>\n<tr><td>x</td></tr>\n</table>\n```\n").html
  self:assert_equal(0, wrapped(fenced))
  self:assert_equal(0, closed(fenced))
  self:assert_nil(fenced:find("<table>", 1, true), "the markup of the example is not live")
  self:assert_nil(fenced:find("table-wrap", 1, true))
  local plain_fence = markdown.render("```\n<table>\n```\n\n    <table>\n    </table>\n").html
  self:assert_equal(0, wrapped(plain_fence))
  self:assert_equal(0, count(plain_fence, "<table>"))
  self:assert_equal(0, count(plain_fence, "</table>"))
  local text = markdown.render("text </table> more and <table> here, and `</table>` as code\n").html
  self:assert_equal(0, wrapped(text))
  self:assert_equal(0, closed(text))
  self:assert_equal(0, count(text, "<table>"))
  self:assert_equal(0, count(text, "</table>"))
  self:assert_true(text:find("&lt;/table&gt;", 1, true) ~= nil, text)
  -- Raw HTML of the page is text, not a table of the page.
  local raw = markdown.render("<table><tr><td>raw</td></tr></table>\n").html
  self:assert_equal(0, wrapped(raw))
  self:assert_equal(0, count(raw, "<table>"))
  -- A real table whose cell holds the text: the cell is escaped, the table is wrapped once.
  local cell = markdown.render("| a |\n|---|\n| `<table>` and </table> |\n").html
  self:assert_equal(1, wrapped(cell))
  self:assert_equal(1, closed(cell))
  self:assert_equal(1, count(cell, "<table>"), "the one table of the page")
  self:assert_equal(1, count(cell, "</table>"))
end

function T:test_a_table_with_empty_cells_is_wrapped_and_keeps_its_cells()
  local html = markdown.render("|  |  |\n|--|--|\n|  |  |\n").html
  self:assert_equal(1, wrapped(html))
  self:assert_equal(1, closed(html))
  self:assert_equal(2, count(html, "<th></th>"))
  self:assert_equal(2, count(html, "<td></td>"))
  local mixed = markdown.render("| a |  | c |\n|---|:-:|--:|\n|  | 2 |  |\n").html
  self:assert_equal(1, wrapped(mixed))
  self:assert_equal(3, select(2, mixed:gsub("<th[ >]", "")))
  self:assert_equal(3, select(2, mixed:gsub("<td[ >]", "")))
end

function T:test_the_wrapper_is_in_the_page_around_a_table_of_a_guide()
  local prefixed = doc.MemoryFileSystem({ ["c/en/index.md"] = page("Home", "| a |\n|---|\n| 1 |\n\n> | b |\n> |---|\n> | 2 |\n\n```html\n<table>\n</table>\n```\n") })
  doc.build({ site_configuration = { title = "T" }, guides_dir = "c", output_dir = "o", file_system = prefixed })
  local html = prefixed:read("o/en/index.html")
  self:assert_equal(2, wrapped(html))
  self:assert_equal(2, closed(html))
  self:assert_equal(2, count(html, "<table>"))
end

return T
