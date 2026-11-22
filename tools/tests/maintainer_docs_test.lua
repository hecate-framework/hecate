local test = require("harness.test")
local maintainer_docs = require("lib.maintainer_docs")
local T = test.Case("MaintainerDocsTest")

function T:test_title_is_the_first_heading_and_description_the_first_prose_paragraph()
  local page = maintainer_docs.render("docs/architecture/logging.md", "# Logging\n\nStructured records with severities.\nSecond line.\n\n## Part\n")
  self:assert_true(page:find('description: "Structured records with severities. Second line."', 1, true) ~= nil)
  self:assert_true(page:find('source: "docs/architecture/logging.md"', 1, true) ~= nil)
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


local function links_of(source, text) return maintainer_docs.render(source, "# T\n\n" .. text .. "\n") end

function T:test_a_link_with_a_title_and_a_reference_definition_are_rewritten()
  local page = links_of("docs/architecture/a.md", '[t](../open-questions.md "the title")\n\n[ref]: ../roadmap.md\n[b]: b.md')
  self:assert_true(page:find('[t](https://github.com/hecate-framework/hecate/blob/main/docs/open-questions.md "the title")', 1, true) ~= nil)
  self:assert_true(page:find("[ref]: https://github.com/hecate-framework/hecate/blob/main/docs/roadmap.md", 1, true) ~= nil)
  self:assert_true(page:find("[b]: b.md", 1, true) ~= nil)
end

function T:test_double_backtick_spans_and_longer_fences_are_left_alone()
  local page = links_of("docs/architecture/a.md", "``[c](../x.md)`` and `a` [d](../y.md)")
  self:assert_true(page:find("``[c](../x.md)``", 1, true) ~= nil)
  self:assert_true(page:find("[d](https://github.com/hecate-framework/hecate/blob/main/docs/y.md)", 1, true) ~= nil)
  local fenced = links_of("docs/architecture/a.md", "````\n```\n[c](../x.md)\n```\n````\n[e](../z.md)")
  self:assert_true(fenced:find("[c](../x.md)", 1, true) ~= nil)
  self:assert_true(fenced:find("[e](https://github.com/hecate-framework/hecate/blob/main/docs/z.md)", 1, true) ~= nil)
end

function T:test_a_link_that_leaves_the_repository_is_left_as_written()
  local page = links_of("docs/architecture/a.md", "[x](../../../../etc/x.md)")
  self:assert_true(page:find("[x](../../../../etc/x.md)", 1, true) ~= nil)
end

function T:test_a_readme_link_of_an_adr_becomes_the_index_and_the_glossary_depth_follows_the_page()
  local page = maintainer_docs.render("docs/adr/0001-x.md", "# T\n\n[i](README.md#f)\n")
  self:assert_true(page:find("[i](index.md#f)", 1, true) ~= nil)
  local from_adr = maintainer_docs.render("docs/adr/0001-x.md", "# T\n\n[g](../glossary.md)\n")
  self:assert_true(from_adr:find("[g](../../../../user/en/reference/glossary/)", 1, true) ~= nil)
  local from_index = maintainer_docs.render("docs/adr/README.md", "# T\n\n[g](../glossary.md)\n")
  self:assert_true(from_index:find("[g](../../../user/en/reference/glossary/)", 1, true) ~= nil)
end

function T:test_crlf_sources_give_clean_titles_and_the_front_matter_is_quoted()
  local title, description = maintainer_docs.describe("# Title\r\n\r\nFirst \"quoted\" \\ text.\r\n")
  self:assert_equal("Title", title)
  self:assert_equal('First "quoted" \\ text.', description)
  local page = maintainer_docs.render("docs/architecture/a b.md", "# Title\r\n\r\nFirst \"quoted\" \\ text.\r\n")
  self:assert_true(page:find('description: "First \\"quoted\\" \\\\ text."', 1, true) ~= nil)
  self:assert_true(page:find('source: "docs/architecture/a b.md"', 1, true) ~= nil)
  self:assert_nil(page:find("\r", 1, true))
end

function T:test_the_marker_follows_the_first_heading_and_is_recognised()
  local page = maintainer_docs.render("docs/architecture/a.md", "# Title\n\nBody.\n")
  local heading, marker, body = page:find("# Title", 1, true), page:find("Generated by lua tools/run.lua gen-maintainer-docs", 1, true), page:find("\nBody.\n", 1, true)
  self:assert_true(heading < marker and marker < body)
  self:assert_true(maintainer_docs.is_generated(page))
  self:assert_false(maintainer_docs.is_generated("# Title\n"))
end

function T:test_an_architecture_page_without_prose_gets_a_description_of_its_own_kind()
  local _, adr = maintainer_docs.describe("")
  self:assert_equal("Architecture decision record: Untitled", adr)
  local page = maintainer_docs.render("docs/architecture/a.md", "# Title\n\n- a list\n")
  self:assert_true(page:find('description: "Architecture specification: Title"', 1, true) ~= nil)
end

return T
