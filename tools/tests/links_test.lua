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
  local present = { ["website/en/reference/net"] = true }
  local function exists(path) return present[path] == true end
  self:assert_true(links.is_ungenerated_reference("website/en/reference/core/index.md", exists))
  self:assert_false(links.is_ungenerated_reference("website/en/reference/net/Nope.md", exists))
  self:assert_false(links.is_ungenerated_reference("website/en/reference/glossary.md", exists))
  self:assert_false(links.is_ungenerated_reference("docs/glossary.md", exists))
end
return T
