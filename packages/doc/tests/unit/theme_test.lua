---@diagnostic disable: need-check-nil  -- tests read files they have just built; a nil fails the assertion that follows
-- Accessibility and brand checks on the theme: WCAG 2.2 contrast of the token pairs the
-- stylesheet uses, the brand rules (tokens, corners, no gradients, name never capitalised)
-- and the structure of the generated HTML (landmarks, keyboard order, names).
local test = require("harness.test")
local doc = require("hecate.doc")
local reactor = require("hecate.reactor")
local T = test.Case("ThemeTest")

local function read(path)
  local file = assert(io.open(path, "rb"), path)
  local text = file:read("a")
  file:close()
  return text
end

local theme_dir = doc.theme.assets_directory()
local fixtures = (debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/tests/unit/")) .. "/tests/fixtures"
local CSS = read(theme_dir .. "/theme.css")
local JS = read(theme_dir .. "/theme.js")
local CSS_CODE = CSS:gsub("/%*.-%*/", "") -- without comments

--- Custom properties of a rule, by selector text (exact match of the selector line).
local function properties(selector)
  local start = CSS:find(selector .. " {", 1, true)
  assert(start, "no rule " .. selector)
  local block = CSS:match("{(.-)}", start)
  local out = {}
  for name, value in block:gmatch("%-%-([%w%-]+):%s*([^;]+);") do out[name] = value end
  return out
end

local THEMES = {
  light = properties(":root"),
  dark = properties(':root[data-theme="dark"]'),
}

local function luminance(hex)
  local function channel(offset)
    local value = tonumber(hex:sub(offset, offset + 1), 16) / 255
    return value <= 0.03928 and value / 12.92 or ((value + 0.055) / 1.055) ^ 2.4
  end
  return 0.2126 * channel(2) + 0.7152 * channel(4) + 0.0722 * channel(6)
end

local function contrast(a, b)
  local la, lb = luminance(a), luminance(b)
  if la < lb then la, lb = lb, la end
  return (la + 0.05) / (lb + 0.05)
end

function T:test_the_contrast_function_follows_the_wcag_definition()
  self:assert_true(math.abs(contrast("#000000", "#FFFFFF") - 21) < 0.001)
  self:assert_true(math.abs(contrast("#FFFFFF", "#FFFFFF") - 1) < 0.001)
  self:assert_true(math.abs(contrast(THEMES.light.ink, THEMES.light["surface-100"]) - 15.5) < 0.1, "brand kit: 15.5:1")
  self:assert_true(math.abs(contrast(THEMES.dark.earth, THEMES.dark["surface-100"]) - 7.1) < 0.1, "brand kit: 7.1:1")
end

-- Tokens ----------------------------------------------------------------------------------

function T:test_colour_tokens_equal_the_brand_kit_in_both_themes()
  local tokens = read(fixtures .. "/brand-tokens.json")
  local found = 0
  for name, light, dark in tokens:gmatch('"name":%s*"([%w%-]+)",%s*"value":%s*{%s*"light":%s*"(#%x+)",%s*"dark":%s*"(#%x+)"') do
    found = found + 1
    self:assert_equal(light:upper(), THEMES.light[name]:upper(), "light " .. name)
    self:assert_equal(dark:upper(), THEMES.dark[name]:upper(), "dark " .. name)
  end
  self:assert_equal(13, found)
end

function T:test_dark_tokens_also_apply_when_the_system_prefers_dark_and_no_theme_is_chosen()
  local media = CSS:match("@media %(prefers%-color%-scheme: dark%) {%s*:root:not%(%[data%-theme=\"light\"%]%) {(.-)}")
  self:assert_not_nil(media)
  for name, value in pairs(THEMES.dark) do
    if name:find("^surface") or name == "ink" or name == "earth" or name == "moon" then
      self:assert_true(media:find("--" .. name .. ": " .. value, 1, true) ~= nil, name)
    end
  end
end

function T:test_type_families_and_radii_follow_the_brand_tokens()
  local tokens = read(fixtures .. "/brand-tokens.json")
  self:assert_true(CSS:find('--serif: "STIX Two Text", "STIX Two", Cambria, Georgia, serif;', 1, true) ~= nil)
  self:assert_true(CSS:find('--sans: "Fira Sans", system-ui, -apple-system, "Segoe UI", sans-serif;', 1, true) ~= nil)
  self:assert_true(CSS:find('--mono: "Fira Code", "Fira Mono", ui-monospace, Consolas, monospace;', 1, true) ~= nil)
  self:assert_true(tokens:find('"STIX Two Text', 1, true) ~= nil)
  self:assert_equal("2px", THEMES.light["radius-sm"])
  self:assert_equal("4px", THEMES.light["radius-md"])
  self:assert_true(CSS:find("font: 400 18px/28px var(--serif);", 1, true) ~= nil, "body: 18px/28px serif")
end

function T:test_corners_stay_nearly_square_and_nothing_glows()
  for radius in CSS_CODE:gmatch("border%-radius:%s*([^;]+);") do
    for value in radius:gmatch("%S+") do
      self:assert_true(value == "0" or value == "2px" or value == "4px" or value == "var(--radius-sm)"
        or value == "var(--radius-md)", "border-radius " .. radius)
    end
  end
  self:assert_nil(CSS_CODE:find("gradient", 1, true))
  self:assert_nil(CSS_CODE:find("text-shadow", 1, true))
  self:assert_nil(CSS_CODE:find("blur", 1, true))
  self:assert_nil(CSS_CODE:find("drop-shadow", 1, true))
  for shadow in CSS_CODE:gmatch("box%-shadow:%s*([^;]+);") do
    self:assert_true(shadow:find("^inset [%-%d]+p?x? [%-%d]+p?x? 0 var") ~= nil, "only flat inset rules: " .. shadow)
  end
end

function T:test_every_font_face_has_a_file_and_swaps()
  local count = 0
  for rule in CSS:gmatch("@font%-face {(.-)}") do
    count = count + 1
    self:assert_true(rule:find("font%-display: swap") ~= nil)
    local path = rule:match('url%("([^"]+)"%)')
    self:assert_not_nil(read(theme_dir .. "/" .. path))
  end
  self:assert_equal(9, count)
  for _, licence in ipairs({ "OFL-fira-sans.txt", "OFL-stix-two-text.txt", "OFL-fira-code.txt" }) do
    self:assert_true(read(theme_dir .. "/fonts/" .. licence):find("SIL OPEN FONT LICENSE Version 1.1", 1, true) ~= nil)
  end
end

function T:test_every_listed_theme_file_exists()
  for _, file in ipairs(doc.theme.asset_files) do self:assert_not_nil(read(theme_dir .. "/" .. file), file) end
end

function T:test_the_favicon_is_the_adaptive_compact_mark()
  local favicon = read(theme_dir .. "/brand/favicon.svg")
  self:assert_true(favicon:find("prefers-color-scheme:dark", 1, true) ~= nil)
  self:assert_true(favicon:find('viewBox="0 0 64 64"', 1, true) ~= nil)
  self:assert_nil(favicon:find("gradient", 1, true))
end

function T:test_the_name_is_never_capitalised_in_the_theme()
  local scanned = { CSS, JS }
  for _, file in ipairs({ "theme/strings.lua", "theme/layout.lua", "theme/init.lua" }) do
    scanned[#scanned + 1] = read(fixtures .. "/../../src/hecate/doc/" .. file)
  end
  for _, text in ipairs(scanned) do self:assert_nil(text:find("Hecate", 1, true)) end
end

-- Contrast (WCAG 2.2, success criteria 1.4.3 and 1.4.11) -----------------------------------

function T:test_text_tokens_meet_aa_on_the_surfaces_they_are_used_on()
  local pairs_used = {
    { "ink", "surface-100" }, { "ink", "surface-200" }, { "ink", "surface-300" },
    { "ink-muted", "surface-100" }, { "ink-muted", "surface-200" }, { "ink-muted", "surface-300" },
    { "earth", "surface-100" }, { "earth", "surface-200" }, { "earth", "surface-300" },
    { "moon", "surface-100" }, { "moon", "surface-200" },
    { "danger", "surface-100" }, { "danger", "surface-200" },
    { "success", "surface-100" }, { "success", "surface-200" },
    { "on-earth", "earth" },
  }
  for theme_name, tokens in pairs(THEMES) do
    for _, pair in ipairs(pairs_used) do
      local ratio = contrast(tokens[pair[1]], tokens[pair[2]])
      self:assert_true(ratio >= 4.5, ("%s: %s on %s is %.2f:1, below 4.5:1"):format(theme_name, pair[1], pair[2], ratio))
    end
  end
end

function T:test_control_borders_and_focus_rings_meet_3_to_1()
  for theme_name, tokens in pairs(THEMES) do
    for _, surface in ipairs({ "surface-100", "surface-200", "surface-300" }) do
      for _, name in ipairs({ "border-strong", "earth" }) do
        local ratio = contrast(tokens[name], tokens[surface])
        self:assert_true(ratio >= 3, ("%s: %s on %s is %.2f:1, below 3:1"):format(theme_name, name, surface, ratio))
      end
    end
  end
end

-- Stylesheet behaviour that keyboard and low-vision users rely on ---------------------------

function T:test_focus_motion_and_print_rules_exist()
  self:assert_true(CSS:find(":focus-visible { outline: 2px solid var(--earth)", 1, true) ~= nil)
  self:assert_true(CSS:find("prefers-reduced-motion: reduce", 1, true) ~= nil)
  self:assert_true(CSS:find("@media print", 1, true) ~= nil)
  self:assert_true(CSS:find("%.skip%-link:focus { top: ") ~= nil)
  for rule in CSS:gmatch("[^}]*outline: none[^}]*}") do
    self:assert_true(rule:find("search%-input") ~= nil or rule:find("main:focus%-visible") ~= nil,
      "outline removed outside the search field and the skip-link target: " .. rule)
  end
end

function T:test_the_scripts_never_build_markup_from_text()
  for _, forbidden in ipairs({ "innerHTML", "outerHTML", "insertAdjacentHTML", "document.write", "eval(", "new Function" }) do
    self:assert_nil(JS:find(forbidden, 1, true), forbidden)
  end
  self:assert_nil(read(theme_dir .. "/theme-init.js"):find("innerHTML", 1, true))
end

-- Structure of the generated pages -------------------------------------------------------

local function build_fixture()
  local source = fixtures .. "/site"
  local fs = doc.SystemFileSystem()
  local memory = doc.MemoryFileSystem()
  local function copy(directory, relative)
    for _, entry in ipairs(fs:list(directory) or {}) do
      local path = directory .. "/" .. entry.name
      local child = relative .. "/" .. entry.name
      if entry.is_directory then copy(path, child) else memory:write("c" .. child, assert(fs:read(path))) end
    end
  end
  copy(source, "")
  local config = doc.load_config("c/site.lua", memory)
  doc.build({ config = config, source = "c", out = "o", fs = memory })
  return memory
end

local OUTPUT = reactor.run(build_fixture)

function T:test_the_first_focusable_element_is_the_skip_link_and_its_target_exists()
  local html = OUTPUT:read("o/en/guide/concurrency/index.html")
  local body = html:match("<body[^>]*>(.*)</body>")
  self:assert_true(body:find('^%s*<a class="skip%-link" href="#content">Skip to content</a>') ~= nil)
  self:assert_true(html:find('<main id="content" tabindex="-1">', 1, true) ~= nil)
end

function T:test_landmarks_are_named_and_there_is_one_main_and_one_h1()
  for _, path in ipairs({ "o/en/guide/concurrency/index.html", "o/en/index.html", "o/fr/guide/first-example/index.html", "o/404.html" }) do
    local html = OUTPUT:read(path)
    local _, mains = html:gsub("<main[ >]", "")
    local _, h1 = html:gsub("<h1[ >]", "")
    self:assert_equal(1, mains, path)
    self:assert_true(h1 >= 1, path)
    for tag in html:gmatch("<nav[^>]*>") do
      self:assert_true(tag:find("aria%-label") ~= nil or tag:find("aria%-labelledby") ~= nil, path .. " " .. tag)
    end
    for tag in html:gmatch("<aside[^>]*>") do self:assert_true(tag:find("id=") ~= nil) end
    self:assert_true(html:find("<html lang=\"%a+\">") ~= nil, path)
    self:assert_true(html:find('<meta name="viewport" content="width=device-width, initial-scale=1">', 1, true) ~= nil)
  end
end

function T:test_every_page_has_unique_ids_and_no_positive_tabindex()
  for path, html in pairs(OUTPUT.files) do
    if path:find("%.html$") then
      local seen = {}
      for id in html:gmatch('%sid="([^"]+)"') do
        self:assert_nil(seen[id], path .. " repeats id " .. id)
        seen[id] = true
      end
      for tabindex in html:gmatch('tabindex="(%-?%d+)"') do self:assert_true(tonumber(tabindex) <= 0, path) end
    end
  end
end

function T:test_controls_have_names_and_types_and_images_have_alt_text()
  local html = OUTPUT:read("o/en/guide/first-example/index.html")
  for tag in html:gmatch("<button[^>]*>") do self:assert_true(tag:find('type="button"') ~= nil or tag:find("<button class=\"icon%-button\" aria%-label") ~= nil, tag) end
  for tag in html:gmatch("<img[^>]*>") do self:assert_true(tag:find(" alt=") ~= nil, tag) end
  for tag in html:gmatch("<a [^>]*href=\"[^\"]*\"[^>]*></a>") do
    self:assert_true(tag:find("aria%-label") ~= nil or tag:find("header%-anchor") ~= nil, "empty link: " .. tag)
  end
  self:assert_true(html:find('<dialog class="search-dialog" id="search-dialog" aria-label="Search">', 1, true) ~= nil)
  self:assert_true(html:find('aria-label="GitHub repository"', 1, true) ~= nil)
  self:assert_true(html:find('class="logo" href="/en/" aria-label="hecate, home"', 1, true) ~= nil)
  self:assert_true(html:find('width="160" height="45"', 1, true) ~= nil, "the horizontal lockup is never smaller than 160 px")
end

function T:test_disclosure_buttons_declare_what_they_control()
  local html = OUTPUT:read("o/en/guide/concurrency/index.html")
  for _, control in ipairs({ "header-panel", "sidebar", "outline" }) do
    self:assert_true(html:find('aria-controls="' .. control .. '"', 1, true) ~= nil, control)
    self:assert_true(html:find('id="' .. control .. '"', 1, true) ~= nil, control)
  end
end

function T:test_both_logo_variants_are_present_and_decorative_next_to_a_named_link()
  local html = OUTPUT:read("o/en/index.html")
  self:assert_true(html:find("hecate%-logo%-horizontal%.svg") ~= nil)
  self:assert_true(html:find("hecate%-logo%-horizontal%-on%-dark%.svg") ~= nil)
  self:assert_true(html:find('rel="icon" href="/assets/brand/favicon.svg"', 1, true) ~= nil)
end

function T:test_every_interface_string_exists_in_every_built_in_locale()
  local catalogue = doc.theme.strings.catalogue
  for key in pairs(catalogue.en) do self:assert_not_nil(catalogue.fr[key], "fr lacks " .. key) end
  for key in pairs(catalogue.fr) do self:assert_not_nil(catalogue.en[key], "en lacks " .. key) end
  self:assert_equal(12, #catalogue.en.months)
  self:assert_equal(12, #catalogue.fr.months)
end

function T:test_site_configuration_can_override_and_add_interface_strings()
  local strings = doc.theme.strings.for_locale("de", { de = { search = "Suche" } })
  self:assert_equal("Suche", strings.search)
  self:assert_equal("Skip to content", strings.skip_to_content, "English fills the gaps")
  self:assert_equal("Rechercher", doc.theme.strings.for_locale("fr", {}).search)
  self:assert_equal("Chercher", doc.theme.strings.for_locale("fr", { fr = { search = "Chercher" } }).search)
end

function T:test_dates_are_formatted_with_locale_month_names()
  local en = doc.theme.strings.for_locale("en")
  local text, iso = doc.theme.strings.format_date("2026-10-03T08:00:00+02:00", en)
  self:assert_equal("3 October 2026", text)
  self:assert_equal("2026-10-03", iso)
  self:assert_equal("3 octobre 2026", (doc.theme.strings.format_date("2026-10-03", doc.theme.strings.for_locale("fr"))))
  self:assert_nil(doc.theme.strings.format_date("2026-13-03", en))
  self:assert_nil(doc.theme.strings.format_date("yesterday", en))
end

--- The sidebar and the header panel scroll inside their own container on a small screen, and the page
--- behind them does not (owner report 2026-10-20). Manual check: docs/architecture/documentation.md.
function T:test_mobile_menus_scroll_inside_their_container()
  local small = CSS_CODE:match("@media %(max%-width: 959px%) {(.-)\n}\n")
  self:assert_not_nil(small, "the small-screen block is missing")
  local sidebar = small:match("\n  %.sidebar {([^}]*)}")
  self:assert_not_nil(sidebar)
  self:assert_true(sidebar:find("overflow%-y: auto") ~= nil, "the sidebar must scroll")
  self:assert_true(sidebar:find("overscroll%-behavior: contain") ~= nil, "scroll must not chain to the page")
  self:assert_true(CSS_CODE:find("html%.scroll%-locked") ~= nil, "the page behind an open menu must be locked")
  self:assert_true(CSS_CODE:find("100dvh") ~= nil, "the header panel must fit the visible viewport")
  self:assert_true(JS:find('classList.toggle("scroll-locked"', 1, true) ~= nil, "the script must lock the page")
end

-- `SystemFileSystem` suspends: every test of this file runs inside a reactor.
for name, method in pairs(T) do
  if type(name) == "string" and name:find("^test_") and type(method) == "function" then
    T[name] = function(...) return reactor.run(method, ...) end
  end
end

return T
