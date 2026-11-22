local test = require("harness.test")
local maintainer_docs = require("lib.maintainer_docs")
local T = test.Case("MaintainerDocsTest")

function T:test_title_is_the_first_heading_and_description_the_first_prose_paragraph()
  local page = maintainer_docs.render("docs/architecture/logging.md", "# Logging\n\nStructured records with severities.\nSecond line.\n\n## Part\n")
  self:assert_true(page:find('description: "Structured records with severities. Second line."', 1, true) ~= nil)
  self:assert_true(page:find("source: docs/architecture/logging.md", 1, true) ~= nil)
  self:assert_true(page:find("generated: true", 1, true) ~= nil)
  self:assert_true(page:find("# Logging", 1, true) ~= nil)
end

function T:test_an_adr_without_prose_before_its_list_gets_a_standard_description()
  local page = maintainer_docs.render("docs/adr/0001-x.md", "# 0001 — Lua 5.5\n\n- **Status:** Accepted\n\n## Context\n\n- only a list\n")
  self:assert_true(page:find('description: "Architecture decision record: 0001 — Lua 5.5"', 1, true) ~= nil)
end

function T:test_links_between_published_documents_stay_relative()
  local page = maintainer_docs.render("docs/architecture/a.md", "# A\n\nSee [b](b.md#x) and [adr](../adr/0001-x.md).\n")
  self:assert_true(page:find("[b](b.md#x)", 1, true) ~= nil)
  self:assert_true(page:find("[adr](../adr/0001-x.md)", 1, true) ~= nil)
end

function T:test_the_glossary_links_to_the_user_site_and_other_files_to_the_repository()
  local page = maintainer_docs.render("docs/architecture/a.md",
    "# A\n\n[g](../glossary.md#term) [q](../open-questions.md) [c](../../packages/core/README.md#api)\n")
  self:assert_true(page:find("[g](../../../../user/en/reference/glossary/#term)", 1, true) ~= nil)
  self:assert_true(page:find("[q](https://github.com/hecate-framework/hecate/blob/main/docs/open-questions.md)", 1, true) ~= nil)
  self:assert_true(page:find("[c](https://github.com/hecate-framework/hecate/blob/main/packages/core/README.md#api)", 1, true) ~= nil)
end

function T:test_the_adr_readme_is_the_index_and_links_inside_code_are_untouched()
  self:assert_equal("website/maintainer/en/adr/index.md", maintainer_docs.target("docs/adr/README.md"))
  self:assert_equal("website/maintainer/en/architecture/logging.md", maintainer_docs.target("docs/architecture/logging.md"))
  local page = maintainer_docs.render("docs/adr/0001-x.md", "# T\n\n`[a](../x.md)`\n")
  self:assert_true(page:find("`[a](../x.md)`", 1, true) ~= nil)
end

return T
