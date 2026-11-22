local test = require("harness.test")
local links = require("lib.links")
local T = test.Case("LinksTest")

function T:test_slug() self:assert_equal("a-b-c", links.slug("A `b` C")) end
function T:test_a_custom_heading_identifier_replaces_the_slug()
  local set = links.anchors("# Title\n#### `Future:value` {#value}\n")
  self:assert_true(set["value"])
  self:assert_nil(set["futurevalue-value"])
  self:assert_true(set["title"])
end

function T:test_anchors_with_duplicates()
  local set = links.anchors("# Title\n## Part\n## Part\n```\n# not\n```\n")
  self:assert_true(set["title"] and set["part"] and set["part-1"])
  self:assert_equal(nil, set["not"])
end
function T:test_extract_skips_external_and_code()
  local l = links.extract("[a](x.md#f) [b](https://e.com) `[c](y.md)`\n")
  self:assert_equal(1, #l)
  self:assert_equal("x.md", l[1].path)
  self:assert_equal("f", l[1].fragment)
end
function T:test_a_link_into_a_reference_directory_that_is_not_generated_is_not_broken()
  local present = { ["website/user/en/reference/net"] = true }
  local function exists(path) return present[path] == true end
  self:assert_true(links.is_ungenerated_reference("website/user/en/reference/core/index.md", exists))
  self:assert_false(links.is_ungenerated_reference("website/user/en/reference/net/Nope.md", exists))
  self:assert_false(links.is_ungenerated_reference("website/user/en/reference/glossary.md", exists))
  self:assert_false(links.is_ungenerated_reference("docs/glossary.md", exists))
end
function T:test_a_link_to_a_generated_reference_page_that_is_not_generated_is_not_broken()
  local present = { ["website/user/en/reference/configuration-keys.md"] = true }
  local function exists(path) return present[path] == true end
  self:assert_true(links.is_ungenerated_reference("website/user/en/reference/error-codes.md", exists))
  self:assert_false(links.is_ungenerated_reference("website/user/en/reference/configuration-keys.md", exists))
  self:assert_false(links.is_ungenerated_reference("website/user/en/reference/other.md", exists))
end
function T:test_a_url_link_to_the_other_tree_resolves_to_its_page()
  -- From website/user/en/explanation/object-model.md the page is served at /user/en/explanation/object-model/.
  local from = "website/user/en/explanation/object-model.md"
  self:assert_equal("website/maintainer/en/explanation/architecture-and-layers",
    links.cross_tree_target(from, "../../../../maintainer/en/explanation/architecture-and-layers/"))
  -- An index page is served at its directory.
  self:assert_equal("website/maintainer/en/how-to/measure-performance",
    links.cross_tree_target("website/user/en/how-to/index.md", "../../../maintainer/en/how-to/measure-performance/"))
  self:assert_equal("website/user/fr/reference/glossary",
    links.cross_tree_target("website/maintainer/fr/explanation/architecture-and-layers.md",
      "../../../../user/fr/reference/glossary/"))
end
function T:test_other_links_are_not_cross_tree_links()
  local from = "website/user/en/explanation/object-model.md"
  self:assert_nil(links.cross_tree_target(from, "../reference/glossary.md"))
  self:assert_nil(links.cross_tree_target(from, "../reference/glossary/")) -- stays in the tree
  self:assert_nil(links.cross_tree_target("docs/x.md", "../../../../maintainer/en/a/"))
  self:assert_nil(links.cross_tree_target(from, "../../../../elsewhere/en/a/"))
end
function T:test_a_missing_generated_architecture_or_adr_page_of_the_maintainer_site_is_not_broken()
  local none = function() return false end
  self:assert_true(links.is_ungenerated_reference("website/maintainer/en/adr/index.md", none))
  self:assert_true(links.is_ungenerated_reference("website/maintainer/en/architecture/logging.md", none))
  self:assert_false(links.is_ungenerated_reference("website/maintainer/en/adr/index.md", function() return true end))
end

function T:test_a_french_page_may_link_to_the_english_page_of_its_own_tree()
  local from = "website/user/fr/explanation/life-of-a-request.md"
  self:assert_equal("website/user/en/how-to/filters",
    links.cross_tree_target(from, "../../../../user/en/how-to/filters/"))
  self:assert_nil(links.cross_tree_target(from, "../../../../user/fr/how-to/filters/"))
end

function T:test_the_other_generated_pages_of_the_maintainer_site_are_not_broken_when_absent()
  local none = function() return false end
  for _, page in ipairs({ "roadmap.md", "open-questions.md", "reviews/phase-2.md" }) do
    self:assert_true(links.is_ungenerated_reference("website/maintainer/en/" .. page, none), page)
  end
  self:assert_false(links.is_ungenerated_reference("website/maintainer/en/index.md", none))
end

return T
