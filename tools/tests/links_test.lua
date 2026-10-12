local test = require("harness.test")
local links = require("lib.links")
local T = test.Case("LinksTest")

function T:test_slug() self:assert_equal("a-b-c", links.slug("A `b` C")) end
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
return T
