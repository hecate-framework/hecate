local test = require("harness.test")
local navigation = require("hecate.doc.navigation")
local config = require("hecate.doc.config")
local T = test.Case("NavigationTest")

local PAGES = {
  { id = "index", title = "Home" },
  { id = "guide/index", title = "Guide", order = 1 },
  { id = "guide/routing", title = "Routing", order = 3 },
  { id = "guide/concurrency", title = "Concurrency", order = 2 },
  { id = "guide/zebra", title = "Zebra" },
  { id = "guide/advanced/index", title = "Advanced topics" },
  { id = "guide/advanced/tuning", title = "Tuning" },
  { id = "guide/advanced/caching", title = "Caching" },
  { id = "reference/glossary", title = "Glossary" },
  { id = "reference/api", title = "API" },
}

local function site_config(extra)
  local raw = { title = "t" }
  for key, value in pairs(extra or {}) do raw[key] = value end
  return config.normalise(raw)
end

local function titles(nodes)
  local out = {}
  for _, node in ipairs(nodes) do
    out[#out + 1] = node.items and (node.text .. "{" .. table.concat(titles(node.items), ",") .. "}") or node.text
  end
  return out
end

function T:test_section_of_a_page_is_its_first_directory()
  self:assert_equal("guide", navigation.section_of("guide/x"))
  self:assert_equal("guide", navigation.section_of("guide/advanced/x"))
  self:assert_nil(navigation.section_of("index"))
end

function T:test_automatic_sidebar_orders_by_front_matter_then_title()
  local nodes, problems = navigation.sidebar("guide", PAGES, site_config(), "en")
  self:assert_equal(0, #problems)
  self:assert_equal("Guide{Guide,Concurrency,Routing,Zebra}|Advanced topics{Caching,Tuning}",
    table.concat(titles(nodes), "|"))
end

function T:test_automatic_sidebar_links_groups_to_their_index_page()
  local nodes = navigation.sidebar("guide", PAGES, site_config(), "en")
  self:assert_equal("guide/advanced/index", nodes[2].link)
  self:assert_equal("guide/index", nodes[1].items[1].link)
  self:assert_nil(rawget(nodes[1], "order"), "sorting keys are not leaked")
end

function T:test_a_directory_without_an_index_page_gets_a_humanised_name()
  local nodes = navigation.sidebar("how-to", {
    { id = "how-to/a", title = "A" }, { id = "how-to/deep-dive/b", title = "B" },
  }, site_config(), "en")
  self:assert_equal("How to{A}|Deep dive{B}", table.concat(titles(nodes), "|"))
end

function T:test_explicit_sidebar_replaces_the_automatic_one()
  local nodes, problems = navigation.sidebar("guide", PAGES, site_config({
    sidebar = { guide = {
      { text = { en = "Start", fr = "Début" }, items = { "guide/routing", "guide/index" } },
      "guide/zebra",
      { text = "Missing", items = { "guide/nope" } },
    } },
  }), "en")
  self:assert_equal("Start{Routing,Guide}|Zebra|Missing{}", table.concat(titles(nodes), "|"))
  self:assert_equal(1, #problems)
  self:assert_true(problems[1]:find("guide/nope", 1, true) ~= nil)
end

function T:test_explicit_sidebar_text_follows_the_locale()
  local nodes = navigation.sidebar("guide", PAGES, site_config({
    sidebar = { guide = { { text = { en = "Start", fr = "Début" }, items = { "guide/routing" } } } },
  }), "fr")
  self:assert_equal("Début", nodes[1].text)
end

function T:test_reading_order_and_neighbours_follow_the_sidebar()
  local nodes = navigation.sidebar("guide", PAGES, site_config(), "en")
  self:assert_equal("guide/index,guide/concurrency,guide/routing,guide/zebra,guide/advanced/index,guide/advanced/caching,guide/advanced/tuning",
    table.concat(navigation.reading_order(nodes), ","))
  local previous, following = navigation.neighbours(nodes, "guide/routing")
  self:assert_equal("guide/concurrency", previous)
  self:assert_equal("guide/zebra", following)
  local first_previous, first_next = navigation.neighbours(nodes, "guide/index")
  self:assert_nil(first_previous)
  self:assert_equal("guide/concurrency", first_next)
  local last_previous, last_next = navigation.neighbours(nodes, "guide/advanced/tuning")
  self:assert_equal("guide/advanced/caching", last_previous)
  self:assert_nil(last_next)
  local none_previous, none_next = navigation.neighbours(nodes, "reference/api")
  self:assert_nil(none_previous)
  self:assert_nil(none_next)
end

function T:test_top_links_default_to_the_sections()
  local links = navigation.top_links(PAGES, site_config(), "en")
  self:assert_equal(2, #links)
  self:assert_equal("Guide", links[1].text)
  self:assert_equal("guide/index", links[1].id)
  self:assert_equal("guide", links[1].section)
  self:assert_equal("Reference", links[2].text)
  self:assert_equal("reference/api", links[2].id, "a section without an index links to its first page")
end

function T:test_configured_top_links_are_localised_external_or_skipped_when_empty()
  local links = navigation.top_links(PAGES, site_config({
    nav = {
      { text = { en = "Guides", fr = "Guides FR" }, link = "guide/" },
      { text = "Source", link = "https://example.test/repo" },
      { text = "Nothing", link = "tutorials/" },
      { text = "Glossary", link = "reference/glossary" },
    },
  }), "fr")
  self:assert_equal(3, #links)
  self:assert_equal("Guides FR", links[1].text)
  self:assert_equal("https://example.test/repo", links[2].url)
  self:assert_nil(links[2].id)
  self:assert_equal("reference/glossary", links[3].id)
end

return T
